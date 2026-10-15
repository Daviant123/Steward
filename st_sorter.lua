--[[
Steward sorter.

Works one move at a time: read the live bags, pick the single most important move, do it,
wait, and read again. Nothing is planned from stale data, so a failed move can't cascade.

Wardrobe isolation:
  * Gear in a wardrobe only ever moves to another wardrobe (through the inventory, because
    the game can only move items to or from the inventory).
  * While a wardrobe item is in the inventory it is on the "transit" list (saved to disk), so
    even after a crash or reload it goes back into a wardrobe first and is never sorted into
    another bag or handed to a porter.
]]

local res = require('resources')
local store = require('st_store')
local rules = require('st_rules')
local journal = require('st_journal')

local sorter = { running = false, stop_requested = false, moved = 0, status = 'Idle' }
local settings, log

local INV = 0

------------------------------------------------------------------------
-- Live bag snapshot
------------------------------------------------------------------------
local function le32(n)
    return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
end

local function hex(s)
    return ((s or ''):gsub('.', function(c) return ('%02x'):format(c:byte()) end))
end

-- Bags that refused our moves (a put failed 3 times): treated as full for 30 minutes.
sorter.refuse = {}
function sorter.refused(id)
    local t = sorter.refuse[id]
    if t and os.clock() < t then return true end
    sorter.refuse[id] = nil
    return false
end

function sorter.item_key(it)
    return tostring(it.id) .. ':' .. hex(it.extdata)
end

local function in_mog_house()
    local info = windower.ffxi.get_info()
    return info and info.mog_house == true
end

function sorter.snapshot()
    local all = windower.ffxi.get_items()
    local mh = in_mog_house()
    local st = { bags = {}, mog_house = mh }
    for name, id in pairs(rules.bag_ids) do
        local info = windower.ffxi.get_bag_info(id)
        local raw = all and all[name]
        local enabled = info ~= nil and info.enabled ~= false and (info.max or 0) > 0 and raw ~= nil
        local bag = { id = id, name = name, enabled = enabled, max = info and info.max or 0, items = {}, used = 0 }
        if enabled and type(raw) == 'table' then
            -- All 80 slots, not just 1..max: a bag can hold more than its current size (Storage shrinks
            -- when furniture is taken down, but the items stay). Seen in a real log: Storage "35/36"
            -- refused every item because it really held more than 36.
            for index = 1, math.max(bag.max, 80) do
                local it = raw[index]
                if type(it) == 'table' and it.id and it.id ~= 0 and it.id ~= 0xFFFF then
                    bag.items[index] = { id = it.id, count = it.count or 1, status = it.status or 0,
                                         extdata = it.extdata, index = index }
                    bag.used = bag.used + 1
                end
            end
        end
        -- The game's own item count wins if it's higher (items we can't see still take room).
        local real_used = (enabled and info and tonumber(info.count)) or 0
        bag.free = math.max(0, bag.max - math.max(bag.used, real_used))
        if sorter.refused(id) then bag.free = 0 bag.refused = true end
        bag.access = enabled and (not rules.mog_house_only[id] or mh) and id ~= 3
        st.bags[id] = bag
    end
    return st
end

------------------------------------------------------------------------
-- Transit list (wardrobe gear currently in the inventory)
------------------------------------------------------------------------
local transit = {}      -- key -> os.time() when it left the wardrobe

local function load_transit()
    transit = {}
    for entry in (settings.transit or ''):gmatch('[^;]+') do
        local k, t = entry:match('^(.-)@(%d+)$')
        if k then transit[k] = tonumber(t) end
    end
end

local function save_transit()
    local parts = {}
    for k, t in pairs(transit) do parts[#parts + 1] = k .. '@' .. t end
    local s = table.concat(parts, ';')
    if s ~= settings.transit then
        settings.transit = s
        store.save(settings)
    end
end

function sorter.in_transit(it) return transit[sorter.item_key(it)] ~= nil end

-- Forget transit entries for items that are no longer in the inventory (they made it home).
-- New entries get 15 seconds, since the server can take a moment to show the item.
local function prune_transit(st)
    local present = {}
    for _, it in pairs(st.bags[INV].items) do present[sorter.item_key(it)] = true end
    local changed = false
    for k, t in pairs(transit) do
        if not present[k] and os.time() - t > 15 then transit[k] = nil changed = true end
    end
    if changed then save_transit() end
end

------------------------------------------------------------------------
-- Where things belong
------------------------------------------------------------------------
local function wardrobe_count(st)
    local n = 0
    for _, id in ipairs(rules.wardrobes) do if st.bags[id].enabled then n = n + 1 end end
    return n
end

-- Wardrobe bag id for a gear group ('weapons', 'head', ...).
function sorter.wardrobe_for_group(st, group)
    local n = tonumber(settings.wardrobes[group])
    local id = n and rules.wardrobes[n]
    if id and st.bags[id].enabled then return id end
    local def = rules.default_layout(wardrobe_count(st))[group]
    -- default numbers refer to the enabled wardrobes in order
    local k = 0
    for _, wid in ipairs(rules.wardrobes) do
        if st.bags[wid].enabled then
            k = k + 1
            if k == def then return wid end
        end
    end
    return rules.wardrobes[1]
end

-- Wardrobe bag id this gear belongs in.
function sorter.wardrobe_for(st, item_id)
    return sorter.wardrobe_for_group(st, rules.slot_group(item_id))
end

local function stack_size(item_id)
    local item = res.items[item_id]
    return item and item.stack or 1
end

local function partial_stack(bag, item_id)
    local max = stack_size(item_id)
    if max <= 1 then return nil end
    for index, it in pairs(bag.items) do
        if it.id == item_id and it.count < max then return index, max - it.count end
    end
    return nil
end

-- Can this bag take (part of) this item right now? Returns dest_slot (or 0x52 = any), count.
-- A FULL stack only goes to a free slot: topping up a partial stack with it just leaves a new partial
-- stack behind (real logs: 99 Beitetsu -> 8 onto a partial + 91 into a new slot, again and again).
-- whole = true: only if the whole stack fits (used for moves between wardrobes, so a stack of ammo
-- is never split and left in a "wrong" wardrobe to be moved again).
local function room_for(bag, it, whole)
    if not bag or not bag.access or bag.refused then return nil end
    local max = stack_size(it.id)
    if it.count >= max then
        if bag.free > 0 then return 0x52, it.count end
        return nil
    end
    local idx, room = partial_stack(bag, it.id)
    if idx and room >= it.count then return idx, it.count end
    if bag.free > 0 then
        if idx then return idx, room end     -- top up; the rest gets a free slot in the same bag next
        return 0x52, it.count
    end
    if idx and not whole then return idx, room end
    return nil
end

-- Home bag for a non-wardrobe item, plus whether the bag it's in now is acceptable.
local function home_for(st, it, cur_bag)
    local cat = rules.category(it.id)
    local home = settings.rules[cat] or 'stay'
    if home == 'stay' then return nil end
    if home == cur_bag then return nil end
    local order = rules.bag_order(cat, home)
    -- Already in one of its allowed bags: leave it (no shuffling between overflow bags).
    for _, b in ipairs(order) do
        if b == cur_bag then return nil end
    end
    for _, b in ipairs(order) do
        local bag = st.bags[rules.bag_ids[b]]
        if b == cur_bag then return nil end
        local slot, count = room_for(bag, it)
        if slot then return bag, slot, count end
    end
    return nil
end

------------------------------------------------------------------------
-- Planner: the next single move, or nil when everything is in place
------------------------------------------------------------------------
sorter.skip = {}

-- Items held in the inventory on purpose (porter prep): id -> expiry (os.clock()).
sorter.hold_ids = {}
function sorter.held(id)
    local t = sorter.hold_ids[id]
    if t and os.clock() < t then return true end
    sorter.hold_ids[id] = nil
    return false
end
function sorter.hold(ids, seconds)
    for id in pairs(ids) do sorter.hold_ids[id] = os.clock() + (seconds or 3600) end
end
function sorter.release(ids)
    if not ids then sorter.hold_ids = {} return end
    for id in pairs(ids) do sorter.hold_ids[id] = nil end
end

local function sig(a) return ('%s:%d:%d:%d'):format(a.kind, a.bag, a.index, a.item) end

------------------------------------------------------------------------
-- Split stacks: one stackable item in partial stacks in more than one place
------------------------------------------------------------------------
-- Returns { [item_id] = { {bag=id, index=i, count=n}, ... } } for items with 2+ partial stacks
-- where at least one is outside the inventory. Wardrobes, the temporary bag, bags you can't
-- open here, Keep-list, held, in-transit, equipped/bazaar items and categories set to 'stay' or
-- 'inventory' (those are gathered into the inventory by the normal sort) are left out.
function sorter.split_stacks(st, keep)
    keep = keep or rules.name_set(settings.lists.keep)
    local found = {}
    for id, bag in pairs(st.bags) do
        if bag.access and not rules.is_wardrobe[id] and id ~= 3 then
            for index, it in pairs(bag.items) do
                local max = stack_size(it.id)
                if max > 1 and it.count < max and it.status == 0
                    and not keep[rules.item_name(it.id):lower()] and not sorter.held(it.id)
                    and not transit[sorter.item_key(it)]
                    and (settings.rules[rules.category(it.id)] or 'stay') ~= 'stay'
                    and settings.rules[rules.category(it.id)] ~= 'inventory' then
                    found[it.id] = found[it.id] or {}
                    table.insert(found[it.id], { bag = id, index = index, count = it.count, max = max })
                end
            end
        end
    end
    local out = {}
    for item_id, list in pairs(found) do
        local outside = false
        for _, s in ipairs(list) do if s.bag ~= INV then outside = true end end
        if #list >= 2 and outside then out[item_id] = list end
    end
    return out
end

-- The next single move that merges a split stack, or nil.
function sorter.merge_move(st, keep)
    local inv = st.bags[INV]
    local splits = sorter.split_stacks(st, keep)
    local ids = {}
    for id in pairs(splits) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local list = splits[id]
        -- Target: a partial stack outside the inventory: its home bag first, then its other allowed
        -- bags, then the biggest stack.
        local cat = rules.category(id)
        local home = settings.rules[cat]
        local rank = {}
        for _, b in ipairs(rules.bag_order(cat, home)) do
            if rules.bag_ids[b] then rank[rules.bag_ids[b]] = (b == home) and 2 or 1 end
        end
        local function better(s, t)
            local rs, rt = rank[s.bag] or 0, rank[t.bag] or 0
            if rs ~= rt then return rs > rt end
            if s.count ~= t.count then return s.count > t.count end
            if s.bag ~= t.bag then return s.bag < t.bag end
            return s.index < t.index
        end
        local target
        for _, s in ipairs(list) do
            if s.bag ~= INV and (not target or better(s, target)) then target = s end
        end
        -- Source: the smallest other partial stack (inventory ones first: they need one move).
        local source
        for _, s in ipairs(list) do
            if s ~= target then
                if not source
                    or ((s.bag == INV) and source.bag ~= INV)
                    or (((s.bag == INV) == (source.bag == INV)) and s.count < source.count) then
                    source = s
                end
            end
        end
        if target and source then
            local name = rules.item_name(id)
            local tname = rules.pretty_bag[st.bags[target.bag].name]
            if source.bag == INV then
                local count = math.min(source.count, target.max - target.count)
                if count > 0 then
                    return { kind = 'put', bag = target.bag, index = source.index, item = id, count = count,
                             dest_slot = target.index, why = ('merge split stack of %s onto %s[%d]'):format(name, tname, target.index) }
                end
            elseif inv.free >= 3 then
                return { kind = 'get', bag = source.bag, index = source.index, item = id, count = source.count,
                         why = ('merge split stack: %s %s -> %s'):format(name, rules.pretty_bag[st.bags[source.bag].name], tname) }
            end
        end
    end
    return nil
end

function sorter.plan(st, opts)
    opts = opts or {}
    local inv = st.bags[INV]
    local keep = rules.name_set(settings.lists.keep)

    local function ok(a) return not sorter.skip[sig(a)] end

    -- 1) Wardrobe gear sitting in the inventory goes back into a wardrobe before anything else.
    for index, it in pairs(inv.items) do
        if transit[sorter.item_key(it)] and it.status == 0 then
            local target = st.bags[sorter.wardrobe_for(st, it.id)]
            local slot, count = room_for(target, it, true)
            if not slot then
                for _, wid in ipairs(rules.wardrobes) do
                    slot, count = room_for(st.bags[wid], it, true)
                    if slot then target = st.bags[wid] break end
                end
            end
            if not slot then slot, count = room_for(target, it) end   -- last resort: any room at all
            if slot then
                local a = { kind = 'put', bag = target.id, index = index, item = it.id, count = count,
                            dest_slot = slot, transit_key = sorter.item_key(it),
                            why = 'back to ' .. rules.pretty_bag[target.name] }
                if ok(a) then return a end
            end
        end
    end

    -- 2) Wardrobe gear in the wrong wardrobe (by gear slot).
    if opts.wardrobes and inv.free >= 1 then
        for _, wid in ipairs(rules.wardrobes) do
            local w = st.bags[wid]
            if w.enabled then
                for index, it in pairs(w.items) do
                    if it.status == 0 and rules.is_gear(it.id) then   -- only gear is ever sorted between wardrobes
                        local tid = sorter.wardrobe_for(st, it.id)
                        if tid ~= wid then
                            local slot = room_for(st.bags[tid], it, true)
                            if slot then
                                local a = { kind = 'get', bag = wid, index = index, item = it.id, count = it.count,
                                            transit_key = sorter.item_key(it),
                                            why = ('%s -> %s'):format(rules.pretty_bag[w.name], rules.pretty_bag[st.bags[tid].name]) }
                                if ok(a) then return a end
                            end
                        end
                    end
                end
            end
        end
    end

    if not opts.bags then return nil end

    -- 2b) Merge split stacks (idea from dupefind by Lili): the same stackable item in partial stacks
    --     in two places wastes a slot. Pull the smaller one into the inventory, then put it onto the
    --     bigger stack. Inventory-only duplicates are left to the game's own stack request.
    if settings.merge_stacks ~= false then
        local a = sorter.merge_move(st, keep)
        if a and ok(a) then return a end
    end

    -- 3) Inventory items that have a home elsewhere.
    for index, it in pairs(inv.items) do
        local name = rules.item_name(it.id):lower()
        if it.status == 0 and not keep[name] and not transit[sorter.item_key(it)] and not sorter.held(it.id) then
            local bag, slot, count = home_for(st, it, 'inventory')
            if bag and bag.name ~= 'inventory' then
                local a = { kind = 'put', bag = bag.id, index = index, item = it.id, count = count, dest_slot = slot,
                            why = rules.pretty_bag[bag.name] }
                if ok(a) then return a end
            end
        end
    end

    -- 3b) Inventory goal: keep at least settings.free_goal slots free (as close as possible).
    --     Puts away anything that isn't kept, equipped, in transit or set to stay;
    --     loose items before gear. Home bag first, else any of Satchel / Sack / Case.
    --     Never into a wardrobe.
    local free_goal = tonumber(settings.free_goal) or 0
    local goal = inv.max - free_goal            -- most items the inventory should hold
    if free_goal > 0 and inv.used > goal then
        local cands = {}
        for index, it in pairs(inv.items) do
            local name = rules.item_name(it.id):lower()
            local home = settings.rules[rules.category(it.id)] or 'stay'
            if it.status == 0 and not keep[name] and not transit[sorter.item_key(it)] and not sorter.held(it.id)
                and home ~= 'stay' and home ~= 'inventory' then
                cands[#cands + 1] = { index = index, it = it, gear = rules.is_gear(it.id), name = name }
            end
        end
        table.sort(cands, function(a, b)
            if a.gear ~= b.gear then return not a.gear end
            return a.name < b.name
        end)
        for _, c in ipairs(cands) do
            local order = rules.bag_order(rules.category(c.it.id), settings.rules[rules.category(c.it.id)])
            for _, b in ipairs({ 'satchel', 'sack', 'case' }) do order[#order + 1] = b end
            for _, b in ipairs(order) do
                local bag = st.bags[rules.bag_ids[b] or -1]
                local slot, count = room_for(bag, c.it)
                if slot and b ~= 'inventory' then
                    local a = { kind = 'put', bag = bag.id, index = c.index, item = c.it.id, count = count, dest_slot = slot,
                                why = ('free-slot goal %d (now %d free): %s'):format(free_goal, inv.free, rules.pretty_bag[bag.name]) }
                    if ok(a) then return a end
                end
            end
        end
    end

    -- 4) Items in the wrong storage bag: pull into the inventory (step 3 puts them away).
    --    Leaves two inventory slots free so wardrobe moves always have room.
    if inv.free >= 3 then
        for id, bag in pairs(st.bags) do
            if id ~= INV and not rules.is_wardrobe[id] and bag.access then
                for index, it in pairs(bag.items) do
                    if it.status == 0 then
                        local name = rules.item_name(it.id):lower()
                        local home = settings.rules[rules.category(it.id)] or 'stay'
                        local dest = (home == 'inventory') and inv or home_for(st, it, bag.name)
                        if dest and not keep[name] then
                            local a = { kind = 'get', bag = id, index = index, item = it.id, count = it.count,
                                        why = ('%s -> %s'):format(rules.pretty_bag[bag.name], rules.pretty_bag[dest.name]) }
                            if ok(a) then return a end
                        end
                    end
                end
            end
        end
    end
    return nil
end

------------------------------------------------------------------------
-- Executing moves
------------------------------------------------------------------------
function sorter.execute(a)
    local src, dst, src_index, dest_slot
    if a.kind == 'get' then
        src, dst, src_index, dest_slot = a.bag, INV, a.index, 0x52
    else
        src, dst, src_index, dest_slot = INV, a.bag, a.index, a.dest_slot or 0x52
    end
    -- Same "move item" request the game sends when you move an item by hand (as Organizer does).
    journal.write('MOVE', '%s x%d  %s[%d] -> %s%s  (%s)', rules.item_name(a.item), a.count or 1,
        rules.bag_names[src] or src, src_index, rules.bag_names[dst] or dst,
        (dest_slot ~= 0x52) and ('[' .. dest_slot .. ']') or '', a.why or '')
    local before = windower.ffxi.get_items(src)
    before = before and before[src_index]
    sorter.pending = { bag = src, index = src_index, id = before and before.id or a.item,
                       count = before and before.count or (a.count or 1) }
    windower.packets.inject_outgoing(0x029, string.char(0x29, 6, 0, 0) .. le32(a.count or 1)
        .. string.char(src, dst, src_index, dest_slot))
    if a.transit_key then
        if a.kind == 'get' then transit[a.transit_key] = os.time() end
        save_transit()
    end
end

-- Has the game applied the last move yet? (the source slot changed)
function sorter.confirmed()
    local p = sorter.pending
    if not p then return true end
    local items = windower.ffxi.get_items(p.bag)
    local it = items and items[p.index]
    if not it or it.id ~= p.id or (it.count or 0) ~= p.count then
        sorter.pending = nil
        return true
    end
    return false
end

-- Only move things when it's safe: logged in, standing idle, not mid-zone.
function sorter.safe()
    local p = windower.ffxi.get_player()
    if not p then return false end
    if p.status ~= 0 then return false end
    if sorter.pause_until and os.clock() < sorter.pause_until then return false end
    return true
end

-- Run until nothing is left to move. opts = {bags=bool, wardrobes=bool, auto=bool}
-- Each step runs inside pcall; the wait between steps happens OUTSIDE pcall, because
-- Windower's Lua cannot sleep (yield) inside pcall.
function sorter.run(opts)
    if sorter.running then return end
    opts = opts or {}
    sorter.last_opts = opts
    sorter.running, sorter.stop_requested, sorter.moved = true, false, 0
    sorter.skip = {}
    sorter.status = 'Sorting...'
    local last, repeats = nil, 0
    do
        local st = sorter.snapshot()
        local parts = {}
        for _, n in ipairs({ 'inventory', 'satchel', 'sack', 'case', 'safe', 'safe2', 'locker', 'storage',
                             'wardrobe', 'wardrobe2', 'wardrobe3', 'wardrobe4', 'wardrobe5', 'wardrobe6', 'wardrobe7', 'wardrobe8' }) do
            local b = st.bags[rules.bag_ids[n]]
            parts[#parts + 1] = n .. '=' .. (b.enabled and (b.used .. '/' .. b.max .. (b.access and '' or '(locked)')) or 'off')
        end
        journal.write('SORT', 'start (%s%s%s) mog_house=%s  %s', opts.auto and 'auto ' or 'manual ',
            opts.bags and 'bags ' or '', opts.wardrobes and 'wardrobes' or '', tostring(st.mog_house), table.concat(parts, ' '))
    end

    local function step()
        if not sorter.safe() then sorter.status = 'Paused (not idle)' return 'stop' end
        if opts.auto and sorter.guard and not sorter.guard.allow_auto() then return 'stop' end
        local st = sorter.snapshot()
        prune_transit(st)
        local a = sorter.plan(st, opts)
        if not a then return 'done' end
        local s = sig(a)
        if s == last then
            repeats = repeats + 1
            if repeats >= 3 then
                sorter.skip[s] = true
                log(('Could not move %s, skipping it. (//stw log shows details)'):format(rules.item_name(a.item)))
                journal.write('SKIP', '%s did not move after 3 tries: %s %s[%d] (%s)', rules.item_name(a.item),
                    a.kind, rules.bag_names[a.bag] or a.bag, a.index, a.why or '')
                if a.kind == 'put' and not rules.is_wardrobe[a.bag] then
                    -- The bag itself is refusing (often: really full). Don't pull more items for it.
                    sorter.refuse[a.bag] = os.clock() + 1800
                    sorter.skip[s] = nil          -- the item may go to its next bag instead
                    log(('%s is not taking items; treating it as full for 30 minutes.'):format(
                        rules.pretty_bag[rules.bag_names[a.bag]] or a.bag))
                    journal.write('SKIP', '%s refused a put 3 times: treated as full for 30 min',
                        rules.bag_names[a.bag] or a.bag)
                end
                repeats = 0
                return 'next'
            end
        else
            repeats = 0
        end
        last = s
        if sorter.guard then
            local from, to = (a.kind == 'get') and a.bag or INV, (a.kind == 'get') and INV or a.bag
            if not sorter.guard.note_move(a.item, from, to, rules.item_name(a.item)) then return 'stop' end
        end
        sorter.execute(a)
        sorter.moved = sorter.moved + 1
        if settings.verbose then log(('%s: %s'):format(rules.item_name(a.item), a.why)) end
        return 'next'
    end

    for _ = 1, 300 do
        if sorter.stop_requested then break end
        local ok, res = pcall(step)
        if not ok then
            if sorter.guard then sorter.guard.error('Sort', res) else log('Sort error: ' .. tostring(res)) end
            sorter.status = 'Stopped (error)'
            break
        end
        if res ~= 'next' then break end
        coroutine.sleep(settings.delay)          -- outside pcall
        -- Real logs showed ~15% of moves sent twice: the next plan read the bags before the game had
        -- applied the move. Wait (up to 2.5 s more) until the source slot changes before planning again.
        local waited = 0
        while waited < 2.5 and not sorter.stop_requested do
            local okc, done = pcall(sorter.confirmed)
            if not okc or done then break end
            coroutine.sleep(0.25)
            waited = waited + 0.25
        end
        if waited >= 2.5 then
            journal.write('WAIT', 'move not confirmed after %.1f s; planning again anyway', settings.delay + waited)
            sorter.pending = nil
        end
    end

    sorter.running = false
    journal.write('SORT', 'end: %d move(s), status=%s%s', sorter.moved, sorter.status,
        sorter.stop_requested and ' (stop requested)' or '')
    if sorter.stop_requested then sorter.status = 'Stopped'
    elseif sorter.status == 'Sorting...' then sorter.status = 'Idle' end
    if opts.auto then
        if sorter.guard then sorter.guard.note_auto_run(sorter.moved) end
        sorter.auto_moved = (sorter.auto_moved or 0) + sorter.moved
    else
        log(('Sort finished: %d move%s. (//stw log for each move)'):format(sorter.moved, sorter.moved == 1 and '' or 's'))
    end
    if sorter.on_finish then sorter.on_finish() end
end

function sorter.init(s, logger)
    settings, log = s, logger
    load_transit()
end

-- Item ids currently anywhere in a wardrobe or in transit: these are never offered to a porter.
function sorter.protected_ids(st)
    local ids = {}
    for _, wid in ipairs(rules.wardrobes) do
        for _, it in pairs(st.bags[wid].items) do ids[it.id] = true end
    end
    for _, it in pairs(st.bags[INV].items) do
        if transit[sorter.item_key(it)] then ids[it.id] = true end
    end
    return ids
end

return sorter
