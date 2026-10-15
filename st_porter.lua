--[[
Steward porter: store slip-eligible gear with a Porter Moogle.

The trade and menu handling is ported from PorterPacker by Ivaar
(https://github.com/Ivaar/Windower-addons), store mode only.

Protection, on top of PorterPacker's own checks:
  * Never touches anything in a mog wardrobe, or wardrobe gear passing through the inventory.
  * Never offers an item id that also exists in any wardrobe.
  * Skips equipped items, keep-list items and anything on the porter exclude list.
  * Inventory gear is only included if you turn that on (it might be gear you're using).
]]

require('pack')
local bit = require('bit')
local res = require('resources')
local slips = require('slips')
local rules = require('st_rules')
local journal = require('st_journal')
local store = require('st_store')
local packets = require('packets')

local porter = { busy = false, status = '' }
local settings, log, sorter

-- Porter Moogle event menu ids per zone (from PorterPacker).
local zones = {
    [26] = 621, [50] = 959, [53] = 330, [80] = 661, [87] = 603, [94] = 525, [231] = 874,
    [235] = 547, [240] = 870, [245] = 10106, [247] = 138, [248] = 1139, [249] = 338,
    [250] = 309, [252] = 246, [256] = 43, [280] = 802,
}

local state = 0          -- 0 idle, 1 traded, 2 in menu, 3 menu closing
local store_filter = {}  -- item ids allowed to be stored this run
local hold = {}          -- inventory slots that held gear before the run (not ours to store)
local last_update

local function space_available(bag_id)
    local bag = windower.ffxi.get_bag_info(bag_id)
    return bag and bag.enabled ~= false and (bag.max - bag.count) or 0
end

local function find_porter()
    local npc = windower.ffxi.get_mob_by_name('Porter Moogle')
    if npc and math.sqrt(npc.distance) < 6 and npc.valid_target and npc.is_npc
        and bit.band(npc.spawn_type, 0xDF) == 2 then
        return npc
    end
    return nil
end

function porter.near() return find_porter() ~= nil end

------------------------------------------------------------------------
-- What can be stored
------------------------------------------------------------------------
local function storable(item, slip_id)
    -- PorterPacker's checks: not already on the slip, and the special rules for slip 13.
    return not slips.player_has_item(item.id)
        and (slip_id ~= slips.storages[13] and item.extdata:byte(1) ~= 2
             or item.extdata:byte(2) % 0x80 >= 0x40 and item.extdata:byte(12) >= 0x80)
end

-- Candidates outside the wardrobes: { {bag, index, id, name, slip, excluded} ... }
function porter.candidates(all_inventory)
    local st = sorter.snapshot()
    local protected = sorter.protected_ids(st)
    local keep = rules.name_set(settings.lists.keep)
    local exclude = rules.name_set(settings.porter.exclude)
    local out = {}
    for id, bag in pairs(st.bags) do
        local allowed = not rules.is_wardrobe[id] and id ~= 3
        if allowed then
            for index, it in pairs(bag.items) do
                local slip_id = slips.get_slip_id_by_item_id(it.id)
                -- Inventory gear counts only if prepped for the porter or you included inventory gear.
                local inv_ok = id ~= 0 or all_inventory or settings.porter.include_inventory or sorter.held(it.id)
                if slip_id and it.status == 0 and not protected[it.id] and inv_ok then
                    local name = rules.item_name(it.id)
                    local raw = { id = it.id, extdata = it.extdata or string.rep('\0', 24) }
                    if storable(raw, slip_id) and not keep[name:lower()] then
                        out[#out + 1] = { bag = id, index = index, id = it.id, name = name, slip = slip_id,
                                          slip_no = slips.get_slip_number_by_id(slip_id),
                                          excluded = exclude[name:lower()] == true, reachable = bag.access }
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

------------------------------------------------------------------------
-- Slips: which ones you own, and which you'd need to buy (1,000 gil each from any Porter Moogle)
------------------------------------------------------------------------
-- Returns a list sorted by most items first:
--   { slip = id, no = n, owned = 'inventory'|'Mog Safe'|...|nil, reach = bool, items = {names}, count = n }
-- Mog House bags can't be read away from home. Use the last list Steward saved for them
-- (st_find keeps it up to date whenever you're home). Returns { {bag=id, name=, id=, count=}, ... },
-- plus how many home bags were unreadable and had no saved list.
local HOME_BAGS = { 'safe', 'safe2', 'storage', 'locker' }
function porter.saved_home_items(st)
    local out, unknown = {}, 0
    local ok, find = pcall(require, 'st_find')
    local saved = ok and type(find) == 'table' and find.saved_me and find.saved_me() or nil
    for _, name in ipairs(HOME_BAGS) do
        local bid = rules.bag_ids[name]
        local live = st.bags[bid]
        if not (live and live.enabled) then
            local list = saved and saved.bags and saved.bags[name]
            if list then
                for id, count in pairs(list) do out[#out + 1] = { bag = bid, name = name, id = id, count = count } end
            else
                unknown = unknown + 1
            end
        end
    end
    return out, unknown
end

function porter.slip_report()
    local st = sorter.snapshot()
    local cached, unknown = porter.saved_home_items(st)
    local where = {}
    for _, c in ipairs(cached) do
        if slips.items[c.id] and not where[c.id] then
            where[c.id] = { name = (rules.pretty_bag[c.name] or c.name), reach = false }
        end
    end
    for bid, bag in pairs(st.bags) do
        if bid ~= 3 then
            for _, it in pairs(bag.items) do
                if slips.items[it.id] and (not where[it.id] or bid == 0) then
                    where[it.id] = { name = rules.pretty_bag[bag.name] or bag.name, reach = bid == 0 or bag.access }
                end
            end
        end
    end
    local list = porter.candidates(true)
    -- Gear in Mog House bags we can't read right now (from the saved list).
    local protected = sorter.protected_ids(st)
    local keep = rules.name_set(settings.lists.keep)
    local exclude = rules.name_set(settings.porter.exclude)
    for _, c in ipairs(cached) do
        local slip_id = slips.get_slip_id_by_item_id(c.id)
        if slip_id and not protected[c.id] and not slips.player_has_item(c.id) then
            local name = rules.item_name(c.id)
            if not keep[name:lower()] then
                for _ = 1, c.count do
                    list[#list + 1] = { bag = c.bag, id = c.id, name = name, slip = slip_id,
                                        slip_no = slips.get_slip_number_by_id(slip_id),
                                        excluded = exclude[name:lower()] == true, reachable = false, saved = true }
                end
            end
        end
    end
    local by = {}
    for _, c in ipairs(list) do
        if not c.excluded then
            local g = by[c.slip]
            if not g then
                g = { slip = c.slip, no = c.slip_no or 0, items = {}, count = 0,
                      owned = where[c.slip] and where[c.slip].name, reach = where[c.slip] and where[c.slip].reach }
                by[c.slip] = g
            end
            g.count = g.count + 1
            g.items[#g.items + 1] = c.name
        end
    end
    local out = {}
    for _, g in pairs(by) do out[#out + 1] = g end
    table.sort(out, function(a, b) if a.count ~= b.count then return a.count > b.count end return a.no < b.no end)
    porter.home_unknown = unknown
    return out, unknown
end

local function home_note()
    if (porter.home_unknown or 0) > 0 then
        log('  Your Mog House bags aren\'t known yet: go home once with Steward loaded, then this list includes them.')
    end
end

-- //stw porter slips: chat summary of the report.
function porter.slips_command()
    local rep = porter.slip_report()
    if #rep == 0 then log('Porter slips: no slip-storable gear outside your wardrobes.') home_note() return end
    local buy, buy_items, have_items = {}, 0, 0
    log('Porter slips (gear outside your wardrobes that a Porter Moogle can hold):')
    for _, g in ipairs(rep) do
        local names = table.concat(g.items, ', ', 1, math.min(3, #g.items)) .. (#g.items > 3 and ', ...' or '')
        if g.owned then
            have_items = have_items + g.count
            log(('  Slip %02d: %d item%s (%s) - slip in %s%s'):format(g.no, g.count, g.count == 1 and '' or 's', names,
                g.owned, g.reach and '' or ' (go home for it)'))
        else
            buy_items = buy_items + g.count
            buy[#buy + 1] = ('%02d'):format(g.no)
            log(('  Slip %02d: %d item%s (%s) - you don\'t have this slip'):format(g.no, g.count, g.count == 1 and '' or 's', names))
        end
    end
    log(('  Storable now: %d item%s.'):format(have_items, have_items == 1 and '' or 's'))
    if #buy > 0 then
        log(('  Buying slip%s %s (1,000 gil each at any Porter Moogle) would free %d more bag slot%s.'):format(
            #buy == 1 and '' or 's', table.concat(buy, ', '), buy_items, buy_items == 1 and '' or 's'))
    end
    journal.write('PORTER', 'slips: %d storable with owned slips, %d need slips %s', have_items, buy_items, table.concat(buy, ','))
    home_note()
end

------------------------------------------------------------------------
-- Trading (PorterPacker)
------------------------------------------------------------------------
local function trade_npc(npc, items)
    local str = ('I2'):pack(0, npc.id)
    for x = 1, 8 do str = str .. ('I'):pack(items[x] and items[x].count or 0) end
    str = str .. ('I2'):pack(0, 0)
    for x = 1, 8 do str = str .. ('C'):pack(items[x] and items[x].slot or 0) end
    str = str .. ('C2HI'):pack(0, 0, npc.index, #items > 8 and 8 or #items)
    local names = {}
    for x = 1, math.min(8, #items) do names[#names + 1] = rules.item_name(items[x].id) .. '@' .. tostring(items[x].slot) end
    journal.write('PORTER', 'trade to Porter Moogle: %s', table.concat(names, ', '))
    windower.packets.inject_outgoing(0x36, str)
    state = 1
    porter.deadline = os.clock() + 20
end

-- Slip plus up to 7 storable items, all from the inventory.
local function trade_groups()
    local groups = {}
    for index, item in ipairs(windower.ffxi.get_items(0)) do
        if item.id ~= 0 and item.status == 0 then
            item.slot = item.slot or index
            local slip_id = slips.get_slip_id_by_item_id(item.id)
            if slip_id and store_filter[item.id] and not hold[index] and storable(item, slip_id) then
                groups[slip_id] = groups[slip_id] or {}
                if #groups[slip_id] < 8 then groups[slip_id][#groups[slip_id] + 1] = item end
            elseif slips.items[item.id] then
                groups[item.id] = groups[item.id] or {}
                table.insert(groups[item.id], 1, item)
            end
        end
    end
    return groups
end

local function next_trade()
    local npc = find_porter()
    if not npc then porter.finish('Porter Moogle out of range.') return end
    for slip_id, items in pairs(trade_groups()) do
        if #items > 1 and items[1].id == slip_id then
            while #items > 8 do table.remove(items) end
            return trade_npc(npc, items)
        end
    end
    porter.finish()
end

local function inject_option(npc_id, npc_index, zone_id, menu_id, option_index, flag)
    windower.packets.inject_outgoing(0x5B, ('I3H4'):pack(0, npc_id, option_index, npc_index, flag, zone_id, menu_id))
    return true
end

local function porter_store(data)
    if data:byte(0x0C + 1) == 0 then
        return data:sub(0x00 + 1, 0x07 + 1) .. string.char(1, 0, 0, 0, 1) .. data:sub(0x0D + 1)
    end
    return false
end

-- The retrieve menu can open after a trade; we never retrieve, so just close it.
local function porter_close(data, update, zone_id, menu_id)
    state = 3
    return inject_option(data:unpack('I', 0x04 + 1), data:unpack('H', 0x28 + 1), zone_id, menu_id, 0x40000000, 0)
end

local events = {}
for zone, v in pairs(zones) do events[zone] = { [v - 1] = porter_store, [v] = porter_close } end

local function check_event(data, update)
    local zone_id, menu_id = data:unpack('H2', 0x2A + 1)
    if events[zone_id] and events[zone_id][menu_id] then
        if update and update == last_update then return true end
        state = 2
        last_update = update
        return events[zone_id][menu_id](data, update, zone_id, menu_id)
    end
    return false
end

local function release_event(data, release)
    local zone_id, menu_id = data:unpack('H2', 0x2A + 1)
    if menu_id == release:unpack('H', 0x05 + 1) then
        inject_option(data:unpack('I', 0x04 + 1), data:unpack('H', 0x28 + 1), zone_id, menu_id, 0x40000000, 0)
        state = 0
        last_update = nil
        porter.finish()
    end
end

function porter.incoming(id, data)
    if id == 0x034 and porter.buy_incoming then
        local r = porter.buy_incoming(data)
        if r ~= nil then return r end
    end
    if not porter.busy then return nil end
    if id == 0x034 and state == 1 then
        return check_event(data)
    elseif id == 0x05C and state == 2 then
        check_event(windower.packets.last_incoming(0x34), data)
    elseif id == 0x052 and state ~= 0 then
        if state == 3 then
            state = 0
            last_update = nil
            coroutine.schedule(next_trade, 0.5)
        elseif state == 2 and data:byte(0x04 + 1) == 2 then
            release_event(windower.packets.last_incoming(0x34), data)
        end
    end
    return nil
end

-- Called every second: give up if the Porter never answers.
function porter.watchdog()
    if porter.busy and porter.deadline and os.clock() > porter.deadline then
        porter.finish('No answer from the Porter Moogle; stopped.')
    end
end

function porter.outgoing(id, injected, data)
    if id == 0x05B and state ~= 0 and not injected then state = 3 end
    if id == 0x05B and not injected and data and porter.buy_learn then porter.buy_learn(data) end
end

------------------------------------------------------------------------
-- Store run: gather items and slips into the inventory, then trade slip by slip.
------------------------------------------------------------------------
function porter.finish(msg)
    if not porter.busy then return end
    porter.busy, state, store_filter, hold = false, 0, {}, {}
    sorter.release(porter.prepped)          -- anything not stored goes back on the next sort
    porter.prepped = nil
    porter.status = msg or 'Stored.'
    journal.write('PORTER', 'finished: %s', porter.status)
    log('Porter: ' .. porter.status .. ' Slips go back on the next sort (//stw sort).')
    if porter.on_finish then porter.on_finish() end
end

function porter.store()
    if porter.busy then log('Porter: already working. //stw stop stops it.') return end
    if sorter.running then log('Porter: wait for the sort to finish, or //stw stop.') return end
    local p = windower.ffxi.get_player()
    if not p or p.status ~= 0 then log('Porter: stand still (idle), then //stw porter store.') return end
    if not find_porter() then log('Porter: stand next to a Porter Moogle (within 6 yalms), then //stw porter store.') return end

    local list = {}
    for _, c in ipairs(porter.candidates()) do
        if not c.excluded and c.reachable then list[#list + 1] = c end
    end
    if #list == 0 then log('Porter: nothing to store. (//stw porter list shows candidates)') return end

    porter.busy = true
    porter.deadline = os.clock() + 120
    porter.status = 'Gathering items...'
    local names = {}
    for _, c in ipairs(list) do names[#names + 1] = c.name .. '(' .. (rules.bag_names[c.bag] or c.bag) .. ')' end
    journal.write('PORTER', 'store run: %s', table.concat(names, ', '))
    store_filter = {}
    for _, c in ipairs(list) do store_filter[c.id] = true end

    -- Pull the needed slips and items into the inventory (wardrobes are never touched).
    local needed_slips = {}
    for _, c in ipairs(list) do needed_slips[c.slip] = true end
    local st = sorter.snapshot()
    local in_inv = {}
    hold = {}
    for index, it in pairs(st.bags[0].items) do
        in_inv[it.id] = true
        -- Gear already in the inventory is only stored if you included inventory gear.
        if not settings.porter.include_inventory and not sorter.held(it.id) then hold[index] = true end
    end
    for slip_id in pairs(needed_slips) do
        if not in_inv[slip_id] then
            for bid, bag in pairs(st.bags) do
                if not rules.is_wardrobe[bid] and bid ~= 0 and bag.access then
                    for index, it in pairs(bag.items) do
                        if it.id == slip_id and space_available(0) > 0 then
                            journal.write('PORTER', 'get slip %s from %s[%d]', rules.item_name(slip_id), rules.bag_names[bid] or bid, index)
                            windower.ffxi.get_item(bid, index, 1)
                            coroutine.sleep(settings.delay)
                        end
                    end
                end
            end
        end
    end
    for _, c in ipairs(list) do
        if c.bag ~= 0 then
            if space_available(0) <= 1 then break end
            journal.write('PORTER', 'get %s from %s[%d]', c.name, rules.bag_names[c.bag] or c.bag, c.index)
            windower.ffxi.get_item(c.bag, c.index, 1)
            coroutine.sleep(settings.delay)
        end
    end
    coroutine.sleep(1)
    porter.status = 'Trading...'
    next_trade()
end

porter._trade_groups = function() return trade_groups() end   -- for testing

------------------------------------------------------------------------
-- Prep: in the Mog House, pull storable gear and its slips into the inventory, ready for a Porter.
------------------------------------------------------------------------
function porter.prep()
    if porter.busy or porter.prepping then log('Porter: already working. //stw stop stops it.') return end
    if sorter.running then log('Porter: wait for the sort to finish, or //stw stop.') return end
    local p = windower.ffxi.get_player()
    if not p or p.status ~= 0 then log('Porter prep: stand still (idle), then //stw porter prep.') return end

    local st = sorter.snapshot()
    local cands = porter.candidates()
    local by_slip, unreachable = {}, 0
    for _, c in ipairs(cands) do
        if not c.excluded then
            if c.bag == 0 or c.reachable then
                by_slip[c.slip] = by_slip[c.slip] or { items = {}, ready = {} }
                table.insert(c.bag == 0 and by_slip[c.slip].ready or by_slip[c.slip].items, c)
            else
                unreachable = unreachable + 1
            end
        end
    end

    -- Where is each slip? (inventory, or a bag we can open here; never a wardrobe)
    local slip_at = {}
    for bid, bag in pairs(st.bags) do
        if not rules.is_wardrobe[bid] and (bid == 0 or bag.access) then
            for index, it in pairs(bag.items) do
                if by_slip[it.id] and (not slip_at[it.id] or bid == 0) then slip_at[it.id] = { bag = bid, index = index } end
            end
        end
    end

    -- Fill whole slips first, biggest first; keep one slot free for wardrobe moves.
    local order = {}
    for slip_id, g in pairs(by_slip) do order[#order + 1] = { id = slip_id, g = g } end
    table.sort(order, function(a, b) return #a.g.items + #a.g.ready > #b.g.items + #b.g.ready end)
    local room = st.bags[0].free - 1
    local plan, held, left, no_slip = {}, {}, 0, 0
    for _, o in ipairs(order) do
        local where = slip_at[o.id]
        if not where then
            no_slip = no_slip + #o.g.items + #o.g.ready
        else
            local need_slip = where.bag ~= 0 and 1 or 0
            if room >= need_slip + math.min(1, #o.g.items) then
                if need_slip == 1 then
                    plan[#plan + 1] = { bag = where.bag, index = where.index, name = rules.item_name(o.id), slip = true }
                    room = room - 1
                end
                held[o.id] = true
                for _, c in ipairs(o.g.ready) do held[c.id] = true end
                for _, c in ipairs(o.g.items) do
                    if room > 0 then
                        plan[#plan + 1] = { bag = c.bag, index = c.index, name = c.name }
                        held[c.id] = true
                        room = room - 1
                    else
                        left = left + 1
                    end
                end
            else
                left = left + #o.g.items
            end
        end
    end

    if #plan == 0 and next(held) == nil then
        log(('Porter prep: nothing to gather%s. (//stw porter list shows candidates)'):format(
            unreachable > 0 and (' here; %d item(s) are in Mog House bags, run it at home'):format(unreachable) or ''))
        return
    end

    porter.prepping, porter.stop_prep = true, false
    sorter.hold(held, 3600)
    porter.prepped = held
    journal.write('PORTER', 'prep: %d move(s) planned, %d left for another trip, %d unreachable, %d without a slip',
        #plan, left, unreachable, no_slip)
    local items, slips_n = 0, 0
    for _, m in ipairs(plan) do
        if porter.stop_prep then left = left + 1
        elseif space_available(0) <= 1 then
            left = left + 1
        else
            journal.write('PORTER', 'prep: get %s from %s[%d]', m.name, rules.bag_names[m.bag] or m.bag, m.index)
            windower.ffxi.get_item(m.bag, m.index, 1)
            if m.slip then slips_n = slips_n + 1 else items = items + 1 end
            coroutine.sleep(settings.delay)
        end
    end
    porter.prepping = false
    log(('Porter prep: %d item(s) and %d slip(s) moved into your inventory%s.'):format(items, slips_n,
        left > 0 and ('; %d more for another trip'):format(left) or ''))
    if unreachable > 0 then log(('  %d item(s) are in Mog House bags: run //stw porter prep at home to include them.'):format(unreachable)) end
    if no_slip > 0 then
        log(('  %d item(s) skipped: no storage slip for them within reach. //stw porter slips shows which slips to get.'):format(no_slip))
    end
    log('  Held from auto-sort for 60 min. Go to a Porter Moogle and //stw porter store (or //stw unhold to cancel).')
end

------------------------------------------------------------------------
-- Buying slips (1,000 gil each) at a Porter Moogle: //stw porter buy [confirm | <nn> confirm]
--
-- How the menu works (from LandSandBoat's Porter Moogle scripts, which mirror the real server):
--   * talking to a Porter opens the "talk" event, whose id is the store/retrieve id - 2 in every zone;
--   * finishing that event with option = (scroll offset * 16) + cursor row buys slip (offset + row),
--     for 1,000 gil, unless you already have that slip or your inventory is full.
--   * the real server only takes it with the slip scrolled to the top row: CharC's game sent
--     33 (offset 2, row 1) for Slip 03 when bought by hand, and plain 3 / 6 bought nothing
--     (log 2026-10-12 08:27). So slip n is (n - 1) * 16 + 1.
-- Steward buys one slip at a time, checks that exactly that slip arrived, and stops at the first
-- surprise. A slip you buy by hand is watched too: the option your game sent is remembered and used
-- for that slip from then on.
------------------------------------------------------------------------
local buy = { queue = nil, stage = nil }
porter.buying = false

local function slip_item(n) return slips.storages[n] end

local function learned()
    local t = {}
    for n, opt in (settings.porter.buy_options or ''):gmatch('(%d+):(%d+)') do t[tonumber(n)] = tonumber(opt) end
    return t
end

function porter.buy_option(n)
    local l = learned()[n]
    if l then return l end
    return (n - 1) * 16 + 1            -- scrolled down (n - 1) rows, cursor on the top row
end

local function gil()
    local items = windower.ffxi.get_items()
    return items and tonumber(items.gil) or 0
end

local function slips_held()
    local st = sorter.snapshot()
    local have = {}
    for _, bag in pairs(st.bags) do
        for _, it in pairs(bag.items) do
            local n = slips.items[it.id] and slips.get_slip_number_by_id(it.id)
            if n then have[n] = true end
        end
    end
    -- Slips kept in Mog House bags while you're away (saved list): never buy one you already own.
    for _, c in ipairs((porter.saved_home_items(st))) do
        local n = slips.items[c.id] and slips.get_slip_number_by_id(c.id)
        if n then have[n] = true end
    end
    return have
end

-- Slips Advice wants that you don't have, most useful first.
function porter.slips_to_buy()
    local out = {}
    for _, g in ipairs(porter.slip_report()) do
        if not g.owned and g.no and g.no > 0 then out[#out + 1] = { no = g.no, count = g.count, items = g.items } end
    end
    return out
end

-- Incoming 0x034: our talk event is open -> finish it with the buy option, and hide the menu.
function porter.buy_incoming(data)
    if buy.stage ~= 'talk' then
        -- remember the last talk menu, for learning from a purchase made by hand
        local zone_id, menu_id = data:unpack('H2', 0x2A + 1)
        if zones[zone_id] and menu_id == zones[zone_id] - 2 then buy.manual_menu = os.clock() end
        return nil
    end
    local zone_id, menu_id = data:unpack('H2', 0x2A + 1)
    local npc_id = data:unpack('I', 0x04 + 1)
    if not zones[zone_id] or menu_id ~= zones[zone_id] - 2 or npc_id ~= buy.npc.id then return nil end
    buy.stage = 'sent'
    journal.write('PORTER', 'buy: Slip %02d, option %d (menu %d, zone %d)', buy.cur, buy.opt, menu_id, zone_id)
    inject_option(npc_id, data:unpack('H', 0x28 + 1), zone_id, menu_id, buy.opt, 0)
    return true
end

-- Outgoing 0x05B from the game itself while the talk menu is open: maybe a purchase by hand.
function porter.buy_learn(data)
    if buy.stage or not buy.manual_menu or os.clock() - buy.manual_menu > 120 then return end
    local option = data:unpack('I', 0x08 + 1)
    if not option or option == 0 or option >= 0x40000000 then return end
    local before = slips_held()
    coroutine.schedule(function()
        local after = slips_held()
        for n in pairs(after) do
            if not before[n] then
                local l = learned()
                l[n] = option
                local parts = {}
                for k, v in pairs(l) do parts[#parts + 1] = k .. ':' .. v end
                table.sort(parts)
                settings.porter.buy_options = table.concat(parts, ',')
                store.save(settings)
                journal.write('PORTER', 'learned: Slip %02d is option %d', n, option)
            end
        end
    end, 3)
end

local function buy_list_message(list, total)
    local t = {}
    for _, b in ipairs(list) do t[#t + 1] = ('%02d (%d)'):format(b.no, b.count) end
    log(('Porter: slips to buy for your storable gear: %s.'):format(table.concat(t, ', ')))
    log(('  Cost %s gil; you have %s gil. Stand next to a Porter Moogle and type //stw porter buy confirm.'):format(
        tostring(total), tostring(gil())))
    log('  (One slip at a time; it stops if anything unexpected happens. //stw porter buy <nn> confirm buys one.)')
end

function porter.buy_command(args)
    local a1, a2 = (args[2] or ''):lower(), (args[3] or ''):lower()
    local only = tonumber(a1)
    local confirm = (a1 == 'confirm') or (only and a2 == 'confirm')
    local list = porter.slips_to_buy()
    if only then
        list = {}
        for _, b in ipairs(porter.slips_to_buy()) do if b.no == only then list[1] = b end end
        if #list == 0 then
            if only >= 1 and only <= 28 and slip_item(only) and not slips_held()[only] then
                list[1] = { no = only, count = 0, items = {} }
            else
                log(('Porter: Slip %02d is not one you need to buy (you may already have it).'):format(only)) return
            end
        end
    end
    if #list == 0 then log('Porter: you already have every slip your storable gear needs.') home_note() return end
    if not confirm then buy_list_message(list, #list * 1000) home_note() return end

    if porter.buying or porter.busy or porter.prepping then log('Porter: already working. //stw stop stops it.') return end
    if sorter.running then log('Porter: wait for the sort to finish, or //stw stop.') return end
    local p = windower.ffxi.get_player()
    if not p or p.status ~= 0 then log('Porter: stand still (idle), then try again.') return end
    local npc = find_porter()
    if not npc then log('Porter: stand next to a Porter Moogle (within 6 yalms) first.') return end
    local info = windower.ffxi.get_info()
    if not info or not zones[info.zone] then log('Porter: this Porter Moogle is not in a zone Steward knows; buy by hand.') return end

    porter.buying, buy.stop = true, false
    coroutine.schedule(function()
        local bought, why = {}, nil
        for _, b in ipairs(list) do
            if buy.stop then why = 'stopped' break end
            if gil() < 1000 then why = 'not enough gil' break end
            if space_available(0) < 1 then why = 'inventory full' break end
            if slips_held()[b.no] then
                journal.write('PORTER', 'buy: Slip %02d already owned, skipped', b.no)
            else
                npc = find_porter()
                if not npc then why = 'Porter Moogle out of range' break end
                local have_before, gil_before = slips_held(), gil()
                buy.cur, buy.opt, buy.npc, buy.stage = b.no, porter.buy_option(b.no), npc, 'talk'
                local pk = packets.new('outgoing', 0x01A, { ['Target'] = npc.id, ['Target Index'] = npc.index,
                    ['Category'] = 0, ['Param'] = 0 })
                packets.inject(pk)
                local waited, got = 0, nil
                while waited < 8 do
                    coroutine.sleep(0.5)
                    waited = waited + 0.5
                    local now = slips_held()
                    for n in pairs(now) do if not have_before[n] then got = n end end
                    if got then break end
                end
                buy.stage = nil
                if got == b.no then
                    bought[#bought + 1] = ('%02d'):format(b.no)
                    journal.write('PORTER', 'buy: got Slip %02d (gil %d -> %d)', b.no, gil_before, gil())
                    coroutine.sleep(1.5)
                elseif got then
                    journal.write('PORTER', 'buy: wanted Slip %02d but got Slip %02d (option %d); stopped', b.no, got, buy.opt)
                    why = ('the Porter gave Slip %02d instead of %02d - stopped so nothing else is bought'):format(got, b.no)
                    break
                else
                    journal.write('PORTER', 'buy: Slip %02d did not arrive (option %d); stopped', b.no, buy.opt)
                    why = ('Slip %02d did not arrive - stopped. Buying it by hand once teaches Steward the right menu option'):format(b.no)
                    break
                end
            end
        end
        porter.buying, buy.stage = false, nil
        log(('Porter: bought %d slip%s%s%s.'):format(#bought, #bought == 1 and '' or 's',
            #bought > 0 and (' (' .. table.concat(bought, ', ') .. ')') or '', why and ('; ' .. why) or ''))
        if #bought > 0 then log('  Next: //stw porter prep (at home) and //stw porter store, or //stw porter slips.') end
        if porter.on_finish then porter.on_finish() end
    end, 0)
end

function porter.buy_stop() buy.stop = true end

function porter.init(s, logger, sorter_module)
    settings, log, sorter = s, logger, sorter_module
end

return porter
