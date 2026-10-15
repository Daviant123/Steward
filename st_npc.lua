--[[
Steward NPC storage: one command per kind of item that an NPC stores for you.

  //stw seals        Shami (Port Jeuno): Beastmen's/Kindred's Seals, all Crests
  //stw crystals     Ephemeral Moogle: crystals and clusters (one element per trade)
  //stw vouchers     Isakoth, Rolandienne, Fhelm Jobeizat or Eternal Flame: Copper Vouchers
  //stw remstales    Monisette (Port Jeuno): Rem's Tale chapters
  //stw beastcoins   Sagheera (Port Jeuno): Ancient Beastcoins
  //stw salvage      Mrohk Sahjuuli (Aht Urhgan Whitegate): Salvage plans        (untested)
  //stw soulplates   Sanraku (Aht Urhgan Whitegate): Soul Plates for Zeni      (untested)
  //stw gobbiekeys   Mystrix or any Gobbie Mystery Box goblin: SP Gobbie Keys, one per trade; each
                     gives a prize, so it stops when fewer than 2 inventory slots are free
  ...and everything else QuickTrade knows (2026-10-13): Moat Carp, Mellidopt Wings, Alexandrite,
  Zinc Ore, Yagudo Necklaces, Mandragora Mad, Only the Best, JSE capes, Reisenjima stones, Befouled
  Water and the three Geas Fete pop-item NPCs (see npc.types).

  //stw trade        like //qtr: trade with whichever of these NPCs you target or stand next to

Next to the NPC: trades everything of that kind, batch after batch (pulls it out of the
Satchel/Sack/Case first). Anywhere else: gathers it into the inventory and holds it there.
Add "prep" or "store" to force one or the other, e.g. //stw seals prep.

Item lists and trade waits come from QuickTrade by Valok@Asura; the trade request
format is TradeNPC by Ivaar; skipping the NPC's dialogue is QuickTrade's method.
Wardrobes are never touched. Keep-list items are never traded.
]]

require('pack')
local bit = require('bit')
local rules = require('st_rules')
local journal = require('st_journal')

local npc = { busy = false, stop = false, skip_text_until = 0 }
local S, log, sorter

local function range(a, b) local t = {} for i = a, b do t[#t + 1] = i end return t end

npc.types = {
    { key = 'seals', label = 'Seals & crests', npcs = { 'Shami' }, where = 'Port Jeuno',
      ids = { 1126, 1127, 2955, 2956, 2957 }, wait = 3 },
    { key = 'crystals', label = 'Crystals & clusters', npcs = { 'Ephemeral Moogle', 'Waypoint' }, where = 'by the crafting guilds',
      ids = range(4096, 4111), wait = 9, one_element = true,
      per_npc = { Waypoint = { one_element = false, wait = 3 } } },     -- Waypoints take every element at once
    { key = 'vouchers', label = 'Copper vouchers', npcs = { 'Isakoth', 'Rolandienne', 'Fhelm Jobeizat', 'Eternal Flame' },
      where = 'Isakoth / Rolandienne / Fhelm Jobeizat / Eternal Flame', ids = { 8711 }, wait = 3 },
    { key = 'remstales', label = "Rem's Tale chapters", npcs = { 'Monisette' }, where = 'Port Jeuno',
      ids = range(4064, 4073), wait = 3 },
    { key = 'beastcoins', label = 'Ancient Beastcoins', npcs = { 'Sagheera' }, where = 'Port Jeuno',
      ids = { 1875 }, wait = 3 },
    { key = 'salvage', label = 'Salvage plans', npcs = { 'Mrohk Sahjuuli' }, where = 'Aht Urhgan Whitegate',
      ids = { 3880, 3881, 3882 }, wait = 5, untested = true },
    { key = 'soulplates', label = 'Soul Plates (Zeni)', npcs = { 'Sanraku' }, where = 'Aht Urhgan Whitegate',
      ids = { 2477 }, wait = 10, per_trade = 1, untested = true },
    -- QuickTrade's 'Special Gobbiedial Keys': same goblins, one key per trade, 14 s apart.
    { key = 'gobbiekeys', label = 'SP Gobbie Keys', npcs = { 'Mystrix', 'Habitox', 'Bountibox', 'Specilox', 'Arbitrix',
      'Funtrox', 'Priztrix', 'Sweepstox', 'Wondrix', 'Rewardox', 'Winrix' }, where = 'a Gobbie Mystery Box goblin',
      ids = { 8973 }, wait = 14, per_trade = 1, prize = true },
    -- The rest of QuickTrade's list (NPCs, items and waits from QuickTrade 1.8.0 by Valok@Asura).
    { key = 'moatcarp', label = 'Moat Carp', npcs = { 'Joulet', 'Gallijaux' }, where = "Port San d'Oria",
      ids = { 4401 }, wait = 4 },
    { key = 'mellidopt', label = 'Mellidopt Wings', npcs = { '???' }, where = 'the ??? that takes them',
      ids = { 9050 }, wait = 5, untested = true },
    { key = 'alexandrite', label = 'Alexandrite', npcs = { 'Paparoon' }, ids = { 2488 }, wait = 5 },
    { key = 'zinc', label = 'Zinc Ore (4 a trade)', npcs = { 'Talib' }, where = 'Port Bastok',
      ids = { 642 }, wait = 3, exact = 4 },
    { key = 'yagudo', label = 'Yagudo Necklaces (4)', npcs = { 'Nanaa Mihgo' }, where = 'Windurst Woods',
      ids = { 498 }, wait = 10, exact = 4 },
    { key = 'mandragora', label = 'Mandragora Mad items', npcs = { 'Yoran-Oran' }, where = 'Windurst Walls',
      ids = { 17344, 4369, 1150, 1154, 934 }, wait = 8, per_trade = 1, no_gather = true },
    { key = 'onlybest', label = 'Only the Best items', npcs = { 'Melyon' },
      options = { { 4366, 5 }, { 629, 3 }, { 919, 1 } }, wait = 10 },          -- 5 cabbage / 3 millioncorn / 1 moss
    { key = 'jsecapes', label = 'JSE capes', npcs = { 'A.M.A.N. Reclaimer' },
      ids = range(28617, 28638), extra_ids = { 27596 }, wait = 4, per_trade = 1, no_gather = true },
    { key = 'jsecapes3', label = 'JSE capes (3 alike)', npcs = { 'Makel-Pakel' },
      ids = range(28617, 28638), extra_ids = { 27596 }, wait = 4, same = 3, max_trades = 1, no_gather = true },
    { key = 'stones', label = 'Reisenjima stones', npcs = { 'Oseem' }, ids = { 9210, 9211, 9212 }, wait = 5 },
    { key = 'befouled', label = 'Befouled Water', npcs = { 'Odyssean Passage' }, ids = { 9008 }, wait = 10,
      per_trade = 1, max_trades = 1 },
    -- Geas Fete: one pop set per trade, skipping pops whose key item you already hold (QuickTrade's rule).
    { key = 'geaszitah', label = "Geas Fete Zi'Tah pops", npcs = { 'Affi' }, where = "Escha - Zi'Tah",
      max_trades = 1, no_gather = true, geas = true, wait = 3, options = {
        { 4061, 5, 2917 }, { 4060, 5, 2918 }, { 4059, 5, 2919 }, { 9060, 5 }, { 9057, 5 }, { 4398, 6 },
        { 16581, 1 }, { 16564, 1 }, { 745, 2 }, { 829, 2 }, { 717, 3 }, { 654, 2 }, { 1629, 2 }, { 13091, 1 } } },
    { key = 'geasruaun', label = "Geas Fete Ru'Aun pops", npcs = { 'Dremi' }, where = "Escha - Ru'Aun",
      max_trades = 1, no_gather = true, geas = true, wait = 3, options = {
        { 9103, 5, 2939 }, { 9059, 5, 2940 }, { 9104, 5, 2941 }, { 9097, 5, 2942 }, { 9051, 5, 2943 },
        { 9031, 5, 2944 }, { 4013, 1, 2945 }, { 4015, 1, 2946 }, { 8754, 1, 2947 }, { 4479, 1 }, { 4563, 1 },
        { 746, 2 }, { 652, 2 }, { 719, 2 }, { 2124, 2 }, { 931, 2 }, { 2288, 2 }, { 13981, 1 } } },
    { key = 'geasreis', label = 'Geas Fete Reisenjima', npcs = { 'Shiftrix' }, where = 'Reisenjima',
      max_trades = 1, no_gather = true, geas = true, wait = 3, options = {
        { 6286, 2, 3003 }, { 6288, 2, 3004 }, { 6290, 2, 3005 }, { 6292, 2, 3006 }, { 6294, 2, 3007 },
        { 6296, 1, 3008 }, { 9151, 1, 3009 }, { 9149, 1, 3010 }, { 9150, 1, 3011 }, { 4471, 1 }, { 12302, 1 },
        { 862, 1 }, { 720, 2 }, { 13206, 1 }, { 13983, 1 }, { 17601, 1 }, { 16502, 1 }, { 4418, 1 } } },
}
npc.by_key = {}
for _, t in ipairs(npc.types) do
    npc.by_key[t.key] = t
    t.ids = t.ids or {}
    for _, id in ipairs(t.extra_ids or {}) do t.ids[#t.ids + 1] = id end
    for _, o in ipairs(t.options or {}) do t.ids[#t.ids + 1] = o[1] end
    t.idset = {}
    for _, id in ipairs(t.ids) do t.idset[id] = true end
    t.where = t.where or ('talk to ' .. t.npcs[1])
end

local function free_slots()
    local b = windower.ffxi.get_bag_info(0)
    return b and (b.max - b.count) or 0
end

-- Which of this type's NPCs is within trading range (6 yalms)?
function npc.find(t)
    for _, name in ipairs(t.npcs) do
        local m = windower.ffxi.get_mob_by_name(name)
        if m and m.distance and math.sqrt(m.distance) < 6 and m.valid_target and m.is_npc
            and bit.band(m.spawn_type, 0xDF) == 2 then
            return m
        end
    end
    return nil
end

-- Counts: in the inventory, in bags you can open here, and in bags you can't.
function npc.count(t)
    local st = sorter.snapshot()
    local keep = rules.name_set(S.lists.keep)
    local c = { inv = 0, reach = 0, far = 0 }
    for bid, bag in pairs(st.bags) do
        if not rules.is_wardrobe[bid] and bid ~= 3 then
            for _, it in pairs(bag.items) do
                if t.idset[it.id] and it.status == 0 and not keep[rules.item_name(it.id):lower()] then
                    local n = it.count or 1
                    if bid == 0 then c.inv = c.inv + n
                    elseif bag.access then c.reach = c.reach + n
                    else c.far = c.far + n end
                end
            end
        end
    end
    return c
end

------------------------------------------------------------------------
-- Gather into the inventory (and hold there)
------------------------------------------------------------------------
local function gather(t)
    if t.no_gather then return 0, 0 end          -- gear / pick-your-own items: only what you put in the inventory
    local st = sorter.snapshot()
    local keep = rules.name_set(S.lists.keep)
    local moved, left = 0, 0
    for bid, bag in pairs(st.bags) do
        if bid ~= 0 and not rules.is_wardrobe[bid] and bag.access then
            for index, it in pairs(bag.items) do
                if t.idset[it.id] and it.status == 0 and not keep[rules.item_name(it.id):lower()] then
                    if npc.stop or free_slots() <= 1 then
                        left = left + 1
                    else
                        journal.write('NPC', '%s: get %s x%d from %s[%d]', t.key, rules.item_name(it.id), it.count or 1,
                            rules.bag_names[bid] or bid, index)
                        windower.ffxi.get_item(bid, index, it.count or 1)
                        moved = moved + 1
                        coroutine.sleep(S.delay)
                    end
                end
            end
        end
    end
    sorter.hold(t.idset, 3600)
    return moved, left
end

------------------------------------------------------------------------
-- Trading (TradeNPC's request format)
------------------------------------------------------------------------
local function send_trade(target, slots)
    local qty, ind = {}, {}
    for x = 1, 9 do qty[x], ind[x] = 0, 0 end
    for x, s in ipairs(slots) do qty[x], ind[x] = s.count, s.index end
    local req = ('C4I11C10HI'):pack(0x36, 0x20, 0x00, 0x00, target.id,
        qty[1], qty[2], qty[3], qty[4], qty[5], qty[6], qty[7], qty[8], qty[9], 0x00,
        ind[1], ind[2], ind[3], ind[4], ind[5], ind[6], ind[7], ind[8], ind[9], 0x00,
        target.index, #slots)
    npc.last_trade = slots
    npc.skip_text_until = os.time() + 10
    windower.packets.inject_outgoing(0x36, req)
end

local function owned_kis()
    local set = {}
    for _, id in ipairs(windower.ffxi.get_key_items and windower.ffxi.get_key_items() or {}) do set[id] = true end
    return set
end

-- Exactly n of one item from the inventory (several stacks if needed), or nil.
local function take(usable, id, n)
    local slots, left = {}, n
    for _, u in ipairs(usable) do
        if u.id == id and left > 0 then
            local c = math.min(u.count, left)
            slots[#slots + 1] = { index = u.index, id = id, count = c }
            left = left - c
        end
    end
    if left > 0 or #slots > 8 then return nil end
    return slots
end

-- The next trade for this type from the inventory (t may carry per-NPC overrides).
local function next_batch(t)
    local keep = rules.name_set(S.lists.keep)
    local inv = windower.ffxi.get_items(0)
    local usable = {}
    for index, it in ipairs(inv or {}) do
        if type(it) == 'table' and t.idset[it.id] and it.status == 0 and not keep[rules.item_name(it.id):lower()]
            and not (sorter.in_transit and sorter.in_transit(it)) then    -- wardrobe gear passing through: never
            usable[#usable + 1] = { index = index, id = it.id, count = it.count or 1 }
        end
    end
    -- recipes: the first option you have enough of (Geas Fete: skip pops whose key item you hold)
    if t.options then
        local kis = t.geas and owned_kis() or {}
        for _, o in ipairs(t.options) do
            if not (o[3] and kis[o[3]]) then
                local s = take(usable, o[1], o[2])
                if s then return s end
            end
        end
        return {}
    end
    if t.exact then                                       -- exactly N of the item (Zinc Ore, Yagudo Necklaces)
        for _, u in ipairs(usable) do local s = take(usable, u.id, t.exact) if s then return s end end
        return {}
    end
    if t.same then                                        -- N of the same kind (JSE capes to Makel-Pakel)
        for _, u in ipairs(usable) do
            local s = {}
            for _, v in ipairs(usable) do if v.id == u.id and #s < t.same then s[#s + 1] = { index = v.index, id = v.id, count = 1 } end end
            if #s == t.same then return s end
        end
        return {}
    end
    local slots, element = {}, nil
    for index, it in ipairs(inv or {}) do
        if #slots >= (t.per_trade or 8) then break end
        if type(it) == 'table' and t.idset[it.id] and it.status == 0 and not keep[rules.item_name(it.id):lower()] then
            local el = t.one_element and ((it.id - 4096) % 8) or 0
            if element == nil then element = el end
            if el == element then
                slots[#slots + 1] = { index = index, id = it.id, count = t.per_trade and 1 or (it.count or 1) }
            end
        end
    end
    return slots
end

function npc.store(t)
    local target = npc.find(t)
    if not target then
        log(('%s: stand next to %s (%s) first%s.'):format(t.label, t.npcs[1], t.where,
            t.no_gather and '' or (', or //stw ' .. t.key .. ' prep to gather them')))
        return
    end
    -- this NPC's own rules (e.g. a Waypoint takes every crystal element at once)
    local base = t
    if t.per_npc and t.per_npc[target.name] then t = setmetatable(t.per_npc[target.name], { __index = base }) end
    if t.untested then log(('%s: this trade is marked untested by QuickTrade; watch the first one.'):format(t.label)) end
    local moved = gather(t)
    if moved > 0 then coroutine.sleep(1) end
    local trades, items = 0, 0
    while not npc.stop and trades < (t.max_trades or 40) do
        local p = windower.ffxi.get_player()
        if not p or p.status ~= 0 then log('Stopped: you need to stand still (idle) to trade.') break end
        if t.prize and free_slots() < 2 then
            log(('Stopped: each %s gives a prize; free up inventory space and run it again.'):format(t.label:gsub('s$', '')))
            journal.write('NPC', '%s: stopped, inventory nearly full', t.key)
            break
        end
        target = npc.find(t)
        if not target then log(('Stopped: %s is out of range.'):format(t.npcs[1])) break end
        local batch = next_batch(t)
        if #batch == 0 then break end
        local before = npc.count(t).inv
        local names = {}
        for _, s in ipairs(batch) do names[#names + 1] = rules.item_name(s.id) .. ' x' .. s.count end
        journal.write('NPC', '%s: trade to %s: %s', t.key, target.name, table.concat(names, ', '))
        send_trade(target, batch)
        trades = trades + 1
        coroutine.sleep(t.wait)
        local after = npc.count(t).inv
        if after >= before then
            log(('%s did not take the items; stopping. (//stw log for details)'):format(target.name))
            journal.write('NPC', '%s: no change after trade (%d before, %d after)', t.key, before, after)
            break
        end
        items = items + (before - after)
    end
    sorter.release(t.idset)
    if t.geas then log("  Don't forget your Tribulens or Radialens.") end
    if trades == 0 and not npc.stop then
        log(('%s: nothing to trade in your inventory%s.'):format(t.label,
            t.no_gather and ' (put the items you want to trade in your inventory first)' or ''))
    end
    log(('%s: %d trade%s with %s, %d item%s %s.'):format(t.label, trades, trades == 1 and '' or 's',
        target and target.name or t.npcs[1], items, items == 1 and '' or 's', t.prize and 'traded for prizes' or 'stored'))
    journal.write('NPC', '%s: done, %d trades, %d items', t.key, trades, items)
end

function npc.prep(t)
    if t.no_gather then
        log(('%s: only what you put in your inventory is traded (gear and pick-your-own items are never gathered).'):format(t.label))
        log(('  Take them to %s (%s) and type //stw %s.'):format(t.npcs[1], t.where, t.key))
        return
    end
    local c = npc.count(t)
    if c.inv + c.reach + c.far == 0 then log(('%s: you have none.'):format(t.label)) return end
    local moved, left = gather(t)
    local c2 = npc.count(t)
    log(('%s: %d in your inventory now%s. Take them to %s (%s) and type //stw %s.'):format(t.label, c2.inv,
        left > 0 and (' (%d more stacks did not fit)'):format(left) or '', t.npcs[1], t.where, t.key))
    if c2.far > 0 then log(('  %d more are in Mog House bags: run //stw %s prep at home to include them.'):format(c2.far, t.key)) end
    log('  Held from auto-sort for 60 min (//stw unhold to release).')
end

-- //stw <type> [prep|store|list]
function npc.command(key, sub)
    local t = npc.by_key[key]
    if not t then return false end
    sub = (sub or ''):lower()
    if sub == 'list' then
        local c = npc.count(t)
        log(('%s: %d in inventory, %d in Satchel/Sack/Case or other open bags, %d in Mog House bags. NPC: %s (%s).'):format(
            t.label, c.inv, c.reach, c.far, table.concat(t.npcs, ' / '), t.where))
        return true
    end
    if npc.busy then log('Already trading. //stw stop stops it.') return true end
    if sorter.running then log('Wait for the sort to finish, or //stw stop.') return true end
    npc.busy, npc.stop = true, false
    coroutine.schedule(function()
        local ok_near = npc.find(t) ~= nil
        if sub == 'store' or (sub == '' and ok_near) then npc.store(t) else npc.prep(t) end
        npc.busy = false
    end, 0)
    return true
end

-- //stw trade: like //qtr. The NPC you're targeting if it's one of these, else any of them in range.
function npc.auto()
    local tgt = windower.ffxi.get_mob_by_target and windower.ffxi.get_mob_by_target('t')
    if tgt then
        for _, t in ipairs(npc.types) do
            for _, name in ipairs(t.npcs) do
                if tgt.name == name and npc.find(t) then return npc.command(t.key, 'store') end
            end
        end
    end
    for _, t in ipairs(npc.types) do
        if t.npcs[1] ~= '???' and npc.find(t) and npc.count(t).inv > 0 then return npc.command(t.key, 'store') end
    end
    log('Trade: no NPC that Steward trades with is in range (or you have nothing for it). //stw npc lists them.')
    return true
end

-- Skip the NPC's "press Enter" prompts for 10 seconds after a trade (QuickTrade's method).
function npc.text(original, modified, mode)
    if os.time() > npc.skip_text_until then return nil end
    if mode == 150 or mode == 151 then
        return (modified:gsub(string.char(0x7F, 0x31), ''))
    end
    return nil
end

function npc.init(settings, logger, sorter_module)
    S, log, sorter = settings, logger, sorter_module
end

return npc
