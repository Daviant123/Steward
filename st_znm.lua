--[[
Steward Zeni NM planner (user request 2026-10-13): what you still need for Tinnin, Sarameya and
Tyger, and the shortest way to get it.

  //stw znm [tinnin | sarameya | tyger | all]     (also //stw zeni ...; or the Zeni tab)

How the chain works (BG-wiki, Category:Zeni NM System):
  Tier 1 NMs pop with an item bought from Sanraku (Whitegate E-8) for zeni.
  Every NM drops a trophy; trading the trophy to Sanraku gives a seal (a key item).
  Tier 2 and 3 pop items cost zeni plus the seal of the tier below; Tinnin / Sarameya / Tyger's pop
  item costs zeni plus three tier 3 seals, and their islet needs a salt key item (talk to Ryo first).

The plan reads what this character holds right now: seals and salts (key items) and pop items /
trophies in every bag (Mog House bags from the saved list when away). It assumes a seal is used up
when it buys a pop item (they are "temporary" key items), that you can only hold one of each seal at
a time, and one kill per NM. Then it groups the work into as few Sanraku visits and hunting trips as
possible, hunting zone by zone. Other characters' Zeni items are listed for reference (pop items and
trophies can't be traded between characters). Read only: it never buys, trades or moves anything.
]]

local res = require('resources')
local rules = require('st_rules')

local znm = {}
local S, log, sorter

------------------------------------------------------------------------
-- The NMs (ids checked against Windower's resources)
------------------------------------------------------------------------
local SEAL = {
    maroon = 998, apple = 999, charcoal = 1000, purple = 1001, chestnut = 1002, lilac = 1003, cerise = 1004,
    salmon = 1005, pgrey = 1006, gold = 1007, copper = 1008, blue = 1009, pine = 1010, amber = 1011,
    fallow = 1012, taupe = 1013, sienna = 1014, lavender = 1015,
}
local SALT = { sicklemoon = 1016, silversea = 1017, cyandeep = 1018 }

-- key = { name, tier, zone, ??? grid, pop item, trophy item, seal it gives, seal needed to buy its pop }
znm.nms = {
    vulpangue   = { 'Vulpangue', 1, 'Wajaom Woodlands', 'D-10', 2580, 2616, SEAL.maroon },
    chamrosh    = { 'Chamrosh', 1, 'Mamook', 'J-9', 2581, 2617, SEAL.maroon },
    gigiroon    = { 'Cheese Hoarder Gigiroon', 1, 'Alzadaal Undersea Ruins', 'F-9', 2582, 2618, SEAL.maroon },
    brass_borer = { 'Brass Borer', 1, 'Mount Zhayolm', 'I-7', 2590, 2626, SEAL.cerise },
    claret      = { 'Claret', 1, 'Mount Zhayolm', 'J-8', 2591, 2627, SEAL.cerise },
    ob          = { 'Ob', 1, 'Alzadaal Undersea Ruins', 'G-7', 2592, 2628, SEAL.cerise },
    velionis    = { 'Velionis', 1, 'Arrapago Reef', 'F-11', 2600, 2636, SEAL.pine },
    lil_apkallu = { "Lil' Apkallu", 1, 'Arrapago Reef', 'I-9', 2601, 2637, SEAL.pine },
    chigre      = { 'Chigre', 1, 'Aydeewa Subterrane', 'E-8', 2602, 2638, SEAL.pine },
    iriz_ima    = { 'Iriz Ima', 2, 'Wajaom Woodlands', 'J-8', 2577, 2613, SEAL.apple, SEAL.maroon },
    iriri       = { 'Iriri Samariri', 2, 'Mamook', 'F-7', 2579, 2615, SEAL.apple, SEAL.maroon },
    amooshah    = { 'Lividroot Amooshah', 2, 'Bhaflau Thickets', 'H-9', 2578, 2614, SEAL.apple, SEAL.maroon },
    anantaboga  = { 'Anantaboga', 2, 'Mount Zhayolm', 'E-6', 2587, 2623, SEAL.salmon, SEAL.cerise },
    reacton     = { 'Reacton', 2, 'Halvung', 'H-5', 2588, 2624, SEAL.salmon, SEAL.cerise },
    dextrose    = { 'Dextrose', 2, 'Halvung', 'J-6', 2589, 2625, SEAL.salmon, SEAL.cerise },
    zareehkl    = { 'Zareehkl the Jubilant', 2, 'Arrapago Reef', 'I-10', 2598, 2634, SEAL.amber, SEAL.pine },
    verdelet    = { 'Verdelet', 2, 'Caedarva Mire', 'J-6', 2599, 2635, SEAL.amber, SEAL.pine },
    wulgaru     = { 'Wulgaru', 2, 'Alzadaal Undersea Ruins', 'G-6', 2597, 2633, SEAL.amber, SEAL.pine },
    armed_gears = { 'Armed Gears', 3, 'Alzadaal Undersea Ruins', 'G-11', 2574, 2610, SEAL.charcoal, SEAL.apple },
    gotoh_zha   = { 'Gotoh Zha the Redolent', 3, 'Wajaom Woodlands', 'F-5', 2575, 2611, SEAL.purple, SEAL.apple },
    dea         = { 'Dea', 3, 'Bhaflau Thickets', 'F-7', 2576, 2612, SEAL.chestnut, SEAL.apple },
    nosferatu   = { 'Nosferatu', 3, 'Aydeewa Subterrane', 'E-9', 2584, 2620, SEAL.pgrey, SEAL.salmon },
    bhurborlor  = { 'Khromasoul Bhurborlor', 3, 'Mount Zhayolm', 'H-8', 2585, 2621, SEAL.gold, SEAL.salmon },
    achamoth    = { 'Achamoth', 3, 'Halvung', 'H-4', 2586, 2622, SEAL.copper, SEAL.salmon },
    mahjlaef    = { 'Mahjlaef the Paintorn', 3, 'Caedarva Mire', 'H-7', 2594, 2630, SEAL.fallow, SEAL.amber },
    lamia       = { 'Experimental Lamia', 3, 'Caedarva Mire', 'F-7', 2595, 2631, SEAL.taupe, SEAL.amber },
    nuhn        = { 'Nuhn', 3, 'Arrapago Reef', 'G-6', 2596, 2632, SEAL.sienna, SEAL.amber },
}
for key, t in pairs(znm.nms) do
    t.key, t.name, t.tier, t.zone, t.grid, t.pop, t.trophy, t.gives, t.needs =
        key, t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8]
end

znm.targets = {
    tinnin = { key = 'tinnin', name = 'Tinnin', zone = 'Wajaom Woodlands', where = 'islet: Engraved Tablet H-13, ??? J-13',
        pop = 2573, seals = { SEAL.charcoal, SEAL.purple, SEAL.chestnut }, salt = SALT.sicklemoon, trophy = 2609 },
    sarameya = { key = 'sarameya', name = 'Sarameya', zone = 'Mount Zhayolm', where = 'islet: Engraved Tablet I-10, ??? I-12',
        pop = 2583, seals = { SEAL.pgrey, SEAL.gold, SEAL.copper }, salt = SALT.silversea, trophy = 2619 },
    tyger = { key = 'tyger', name = 'Tyger', zone = 'Caedarva Mire', where = 'islet: Engraved Tablet I-6, ??? H-8',
        pop = 2593, seals = { SEAL.fallow, SEAL.taupe, SEAL.sienna }, salt = SALT.cyandeep, trophy = 2629 },
}
znm.order = { 'tinnin', 'sarameya', 'tyger' }

-- Zeni prices from Sanraku. Tier 1 starts at 1,000 and goes up 100 with each pop item he hands out
-- (horizonffxi.wiki/Sanraku: it drops back over time, max 2,500); Tier 2 starts at 2,000 (BG-wiki,
-- Senorita Pamama); Tier 3 at 3,000 by the same pattern; Tier 4 (Monkey Wine / Buffalo Corpse / Singed
-- Buffalo) isn't listed anywhere: 5,000 is an estimate. Salts 500, or 50 with \"Rhapsody in Azure\".
znm.prices = { { base = 1000, step = 100 }, { base = 2000, step = 200 }, { base = 3000, step = 300 },
               { base = 5000, step = 500, estimate = true } }
znm.salt_price, znm.salt_price_rhapsody, znm.rhapsody = 500, 50, 2886

-- Hunting order (roughly outward from Whitegate), so a trip visits each zone once.
local ZONES = { 'Wajaom Woodlands', 'Bhaflau Thickets', 'Mamook', 'Mount Zhayolm', 'Halvung', 'Caedarva Mire',
    'Aydeewa Subterrane', 'Arrapago Reef', 'Alzadaal Undersea Ruins' }
local zone_rank = {}
for i, z in ipairs(ZONES) do zone_rank[z] = i end

-- NMs that give each seal.
local GIVES = {}
for key, t in pairs(znm.nms) do
    GIVES[t.gives] = GIVES[t.gives] or {}
    table.insert(GIVES[t.gives], key)
end
for _, list in pairs(GIVES) do table.sort(list) end

-- Every item / key item this planner cares about (for the saved lists of other characters).
znm.item_ids, znm.ki_ids = {}, {}
for _, t in pairs(znm.nms) do znm.item_ids[t.pop], znm.item_ids[t.trophy] = true, true end
for _, t in pairs(znm.targets) do znm.item_ids[t.pop], znm.item_ids[t.trophy] = true, true end
for id = 998, 1018 do znm.ki_ids[id] = true end
znm.ki_ids[znm.rhapsody] = true

local function item_name(id) return rules.item_name(id) end
local function ki_name(id)
    local k = res.key_items and res.key_items[id]
    return k and (k.english or k.en) or ('key item ' .. id)
end
znm.ki_name = ki_name

------------------------------------------------------------------------
-- What this character holds
------------------------------------------------------------------------
-- { items = { id = count }, ki = { id = true } }
function znm.holdings()
    local h = { items = {}, ki = {} }
    local st = sorter.snapshot()
    for _, bag in pairs(st.bags) do
        if bag.enabled then
            for _, it in pairs(bag.items) do
                if znm.item_ids[it.id] then h.items[it.id] = (h.items[it.id] or 0) + (it.count or 1) end
            end
        end
    end
    local okp, porter = pcall(require, 'st_porter')
    if okp and type(porter) == 'table' and porter.saved_home_items then
        for _, c in ipairs((porter.saved_home_items(st))) do
            if znm.item_ids[c.id] then h.items[c.id] = (h.items[c.id] or 0) + (c.count or 1) end
        end
    end
    for _, id in ipairs(windower.ffxi.get_key_items and windower.ffxi.get_key_items() or {}) do
        if znm.ki_ids[id] then h.ki[id] = true end
    end
    return h
end

------------------------------------------------------------------------
-- Team mode: all your characters' Zeni items and seals (from their saved lists, this one live)
------------------------------------------------------------------------
-- What a saved character holds: { name, items = { id = n }, ki = { id = true }, time }
local function char_holdings(c)
    local h = { name = c.name, items = {}, ki = {}, time = c.time }
    for _, bag in pairs(c.bags or {}) do
        for id, n in pairs(bag) do if znm.item_ids[id] then h.items[id] = (h.items[id] or 0) + n end end
    end
    for _, id in ipairs(c.key_items or {}) do if znm.ki_ids[id] then h.ki[id] = true end end
    return h
end

-- Everyone: this character live, the others from data/chars. Returns list (this character first), my name.
function znm.team()
    local me = windower.ffxi.get_player()
    me = me and me.name or 'You'
    local live = znm.holdings()
    live.name = me
    local list = { live }
    local okf, find = pcall(require, 'st_find')
    if okf and type(find) == 'table' and find.all_chars then
        for _, c in ipairs((find.all_chars())) do
            if c.name ~= me then list[#list + 1] = char_holdings(c) end
        end
    end
    return list, me
end

local SEAL_TARGET = {}            -- tier 3 seal / trophy / final pop / salt id -> target key
for tk, t in pairs(znm.targets) do
    for _, s in ipairs(t.seals) do SEAL_TARGET[s] = tk end
    SEAL_TARGET[t.pop], SEAL_TARGET[t.salt] = tk, tk
end
for _, nm in pairs(znm.nms) do if nm.tier == 3 then SEAL_TARGET[nm.trophy] = SEAL_TARGET[nm.gives] end end

-- Who should pop the final NM: whoever is closest (pop + salt, then tier 3 seals, then trophies).
local function final_popper(tk, chars, me)
    local t, best, best_score = znm.targets[tk], nil, -1
    for _, c in ipairs(chars) do
        local score = (c.name == me) and 0.5 or 0
        if (c.items[t.pop] or 0) > 0 then score = score + (c.ki[t.salt] and 100 or 50) end
        for _, s in ipairs(t.seals) do if c.ki[s] then score = score + 10 end end
        for _, nm in pairs(znm.nms) do
            if nm.tier == 3 and SEAL_TARGET[nm.gives] == tk and (c.items[nm.trophy] or 0) > 0 then score = score + 3 end
        end
        if score > best_score then best, best_score = c.name, score end
    end
    return best
end

------------------------------------------------------------------------
-- Time model (rough minutes; it only has to rank plans, not be a stopwatch)
------------------------------------------------------------------------
-- One way from Whitegate: Wajaom is next door; most others are a Runic Portal away; Mamook,
-- Halvung and Aydeewa are a walk further.
znm.zone_minutes = {
    ['Wajaom Woodlands'] = 3, ['Bhaflau Thickets'] = 5, ['Mount Zhayolm'] = 5, ['Caedarva Mire'] = 5,
    ['Arrapago Reef'] = 6, ['Alzadaal Undersea Ruins'] = 6, ['Mamook'] = 8, ['Halvung'] = 8, ['Aydeewa Subterrane'] = 8,
}
znm.visit_minutes = 4          -- back to Whitegate and to Sanraku
znm.fight_minutes = 4          -- pop + kill + lot

-- Holdings for the planner: { chars = { {name, items, ki}, ... }, me, fp = { target = name }, team = bool }
function znm.team_holdings(targets, chars, me)
    if not chars then chars, me = znm.team() end
    local fp = {}
    for _, tk in ipairs(targets) do fp[tk] = final_popper(tk, chars, me) end
    local names = {}
    for _, c in ipairs(chars) do names[#names + 1] = c.name end
    return { chars = chars, me = me, fp = fp, team = true, names = names }
end

local function solo_holdings(h)
    if h.chars then return h end
    local fp = {}
    for tk in pairs(znm.targets) do fp[tk] = 'you' end
    return { chars = { { name = 'you', items = h.items or {}, ki = h.ki or {} } }, me = 'you', fp = fp, team = false }
end

-- All ways to pick n NMs (repeats allowed) from a list.
local function multisets(list, n)
    local out = {}
    local function rec(start, acc)
        if #acc == n then local c = {} for i, v in ipairs(acc) do c[i] = v end out[#out + 1] = c return end
        for i = start, #list do acc[#acc + 1] = list[i] rec(i, acc) acc[#acc] = nil end
    end
    rec(1, {})
    return out
end

------------------------------------------------------------------------
-- Simulation: Sanraku visit -> hunting trip -> Sanraku visit ... for one choice of NMs.
-- Every pop item and trophy is Rare/Ex: a character holds at most one of each, and one of each seal.
------------------------------------------------------------------------
local function simulate(targets, H, alloc)
    local team = H.team
    local inv, kis, order = {}, {}, {}
    for _, c in ipairs(H.chars) do
        inv[c.name], kis[c.name] = {}, {}
        for id, n in pairs(c.items) do inv[c.name][id] = n end
        for id in pairs(c.ki) do kis[c.name][id] = true end
        order[#order + 1] = c.name
    end
    local fp = H.fp
    local function holds(who, id) return (inv[who][id] or 0) > 0 end
    local function tag(who, text) return team and (who .. ': ' .. text) or text end
    local zeni = {}                          -- who -> list of { tier, id }
    local function pay(who, tier, id) zeni[who] = zeni[who] or {} table.insert(zeni[who], { tier, id }) end

    -- instances of each NM fight we need, matched to what people already hold
    local inst, claimed = {}, {}
    local function add(key, tk)
        local nm = znm.nms[key]
        local i = { key = key, nm = nm, state = 'none', tk = tk }
        for _, who in ipairs(order) do           -- someone's trophy (tier 3: only the final popper's counts)
            if i.state == 'none' and holds(who, nm.trophy) and not claimed[who .. nm.trophy]
                and (nm.tier < 3 or who == fp[tk]) then
                i.state, i.holder = 'trophy', who claimed[who .. nm.trophy] = true
            end
        end
        for _, who in ipairs(order) do           -- someone's pop item
            if i.state == 'none' and holds(who, nm.pop) and not claimed[who .. nm.pop] then
                i.state, i.holder = 'pop', who claimed[who .. nm.pop] = true
            end
        end
        inst[#inst + 1] = i
        return i
    end
    local want, done = {}, {}
    for _, tk in ipairs(targets) do
        local t = znm.targets[tk]
        if not holds(fp[tk], t.pop) then
            want[tk] = true
            for _, s in ipairs(t.seals) do
                if not kis[fp[tk]][s] then add(GIVES[s][1], tk) end
            end
        end
    end
    for _, k in ipairs(alloc) do add(k) end

    -- walk it through
    local steps, kills, visits, minutes = {}, 0, 0, 0
    local function sorted(f)
        local list = {}
        for _, i in ipairs(inst) do if f(i) then list[#list + 1] = i end end
        table.sort(list, function(a, b)
            if a.nm.tier ~= b.nm.tier then return a.nm.tier > b.nm.tier end
            return a.nm.name < b.nm.name
        end)
        return list
    end
    for round = 1, 30 do
        local acts = {}
        local changed = true
        while changed do
            changed = false
            -- tier 3 trophies -> the final popper's seals
            for _, i in ipairs(sorted(function(i) return i.nm.tier == 3 and i.state == 'trophy' end)) do
                local who = i.holder
                if not kis[who][i.nm.gives] then
                    acts[#acts + 1] = tag(who, ('Trade %s (%s) -> %s'):format(item_name(i.nm.trophy), i.nm.name, ki_name(i.nm.gives)))
                    inv[who][i.nm.trophy] = inv[who][i.nm.trophy] - 1
                    kis[who][i.nm.gives], i.state, changed = true, 'done', true
                end
            end
            -- tier 2/1 seals: trade a trophy for the seal, buy the next pop with it
            for _, tier in ipairs({ 2, 1 }) do
                for _, i in ipairs(sorted(function(i) return i.nm.tier == tier + 1 and i.state == 'none' end)) do
                    local s = i.nm.needs
                    local function can_buy(who) return kis[who][s] and not holds(who, i.nm.pop) and not holds(who, i.nm.trophy) end
                    local buyer
                    for _, who in ipairs(order) do if not buyer and can_buy(who) then buyer = who end end
                    if not buyer then
                        for _, g in ipairs(inst) do
                            if not buyer and g.state == 'trophy' and g.nm.gives == s and not kis[g.holder][s] then
                                local who = g.holder
                                acts[#acts + 1] = tag(who, ('Trade %s (%s) -> %s'):format(item_name(g.nm.trophy), g.nm.name, ki_name(s)))
                                inv[who][g.nm.trophy] = inv[who][g.nm.trophy] - 1
                                kis[who][s], g.state = true, 'done'
                                if can_buy(who) then buyer = who end
                            end
                        end
                    end
                    if buyer then
                        acts[#acts + 1] = tag(buyer, ('Buy %s for %s (zeni + %s)'):format(item_name(i.nm.pop), i.nm.name, ki_name(s)))
                        kis[buyer][s] = nil
                        inv[buyer][i.nm.pop] = (inv[buyer][i.nm.pop] or 0) + 1
                        pay(buyer, i.nm.tier, i.nm.pop)
                        i.state, i.holder, changed = 'pop', buyer, true
                    end
                end
            end
        end
        -- tier 1 pops: zeni only (each person can hold one of each)
        for _, i in ipairs(sorted(function(i) return i.nm.tier == 1 and i.state == 'none' end)) do
            for _, who in ipairs(order) do
                if i.state == 'none' and not holds(who, i.nm.pop) and not holds(who, i.nm.trophy) then
                    acts[#acts + 1] = tag(who, ('Buy %s for %s (zeni)'):format(item_name(i.nm.pop), i.nm.name))
                    inv[who][i.nm.pop] = (inv[who][i.nm.pop] or 0) + 1
                    pay(who, 1, i.nm.pop)
                    i.state, i.holder = 'pop', who
                end
            end
        end
        -- the final pops and salts
        for _, tk in ipairs(targets) do
            local t, who = znm.targets[tk], fp[tk]
            if want[tk] then
                local all = true
                for _, s in ipairs(t.seals) do if not kis[who][s] then all = false end end
                if all then
                    acts[#acts + 1] = tag(who, ('Buy %s for %s (zeni + 3 seals)'):format(item_name(t.pop), t.name))
                    for _, s in ipairs(t.seals) do kis[who][s] = nil end
                    inv[who][t.pop], want[tk] = 1, nil
                    pay(who, 4, t.pop)
                end
            end
            if not done[tk] and not kis[who][t.salt] then
                acts[#acts + 1] = tag(who, ("Buy %s for %s's islet (zeni; ask Ryo first)"):format(ki_name(t.salt), t.name))
                kis[who][t.salt] = true
                pay(who, 'salt', t.salt)
            end
        end
        if #acts > 0 then
            steps[#steps + 1] = { title = 'Sanraku (Aht Urhgan Whitegate E-8)', lines = acts }
            visits, minutes = visits + 1, minutes + znm.visit_minutes
        end

        -- hunting trip: every pop someone holds, zone by zone; then the big ones
        local hunt = {}
        for _, i in ipairs(inst) do if i.state == 'pop' then hunt[#hunt + 1] = i end end
        table.sort(hunt, function(a, b)
            local za, zb = zone_rank[a.nm.zone] or 99, zone_rank[b.nm.zone] or 99
            if za ~= zb then return za < zb end
            if a.nm.tier ~= b.nm.tier then return a.nm.tier > b.nm.tier end
            return a.nm.name < b.nm.name
        end)
        local lines, zones = {}, {}
        for _, i in ipairs(hunt) do
            -- who gets the trophy: tier 3 -> the final popper; lower -> whoever popped it (if they have room)
            local to = (i.nm.tier == 3) and fp[i.tk or SEAL_TARGET[i.nm.gives]] or i.holder
            if holds(to, i.nm.trophy) then
                to = nil
                for _, who in ipairs(order) do if not to and not holds(who, i.nm.trophy) then to = who end end
            end
            if to then
                lines[#lines + 1] = ('%s: %s (T%d) at ??? %s'):format(i.nm.zone, i.nm.name, i.nm.tier, i.nm.grid)
                if team then lines[#lines + 1] = ('   %s pops it, trophy to %s'):format(i.holder, to) end
                inv[i.holder][i.nm.pop] = inv[i.holder][i.nm.pop] - 1
                inv[to][i.nm.trophy] = (inv[to][i.nm.trophy] or 0) + 1
                i.state, i.holder = 'trophy', to
                kills, minutes = kills + 1, minutes + znm.fight_minutes
                if not zones[i.nm.zone] then zones[i.nm.zone] = true minutes = minutes + (znm.zone_minutes[i.nm.zone] or 6) end
            end
        end
        for _, tk in ipairs(targets) do
            local t, who = znm.targets[tk], fp[tk]
            if not done[tk] and holds(who, t.pop) and kis[who][t.salt] then
                lines[#lines + 1] = ('%s: %s (%s)'):format(t.zone, t.name, t.where)
                if team then lines[#lines + 1] = ('   %s pops it'):format(who) end
                done[tk], kills, minutes = true, kills + 1, minutes + znm.fight_minutes + (znm.zone_minutes[t.zone] or 6) + 2
            end
        end
        if #lines > 0 then steps[#steps + 1] = { title = 'Hunt', lines = lines } end
        if #acts == 0 and #lines == 0 then break end
    end
    local finished = true
    for _, tk in ipairs(targets) do if not done[tk] then finished = false end end
    return { steps = steps, kills = kills, visits = visits, minutes = minutes, zeni = zeni, finished = finished }
end

-- Zeni: base prices with each repeat of the same pop item one step dearer (low), and every
-- purchase of a tier in a row one step dearer (high).
local function zeni_cost(list, rhapsody)
    local low, high, same, tier_n = 0, 0, {}, { 0, 0, 0, 0 }
    for _, p in ipairs(list) do
        local tier, id = p[1], p[2]
        if tier == 'salt' then
            local s = rhapsody and znm.salt_price_rhapsody or znm.salt_price
            low, high = low + s, high + s
        else
            local pr = znm.prices[tier]
            same[id] = (same[id] or 0) + 1
            low = low + pr.base + (same[id] - 1) * pr.step
            high = high + pr.base + tier_n[tier] * pr.step
            tier_n[tier] = tier_n[tier] + 1
        end
    end
    return low, math.max(low, high)
end

------------------------------------------------------------------------
-- The plan: try the ways of picking NMs and keep the fastest (or the cheapest)
------------------------------------------------------------------------
-- Which tier 2 / tier 1 NMs to fight for one target: every combination, repeats allowed.
local function choices(tk, H)
    local t = znm.targets[tk]
    local fpn = H.fp[tk]
    local fpc
    for _, c in ipairs(H.chars) do if c.name == fpn then fpc = c end end
    local s3 = {}
    for _, s in ipairs(t.seals) do if not (fpc and fpc.ki[s]) then s3[#s3 + 1] = s end end
    local nm3 = znm.nms[GIVES[t.seals[1]][1]]
    local s2 = nm3.needs                                     -- apple green / salmon / amber
    local s1 = znm.nms[GIVES[s2][1]].needs                   -- maroon / cerise / pine
    local function held_seal(s) local n = 0 for _, c in ipairs(H.chars) do if c.ki[s] then n = n + 1 end end return n end
    local function held_item(id) local n = 0 for _, c in ipairs(H.chars) do n = n + (c.items[id] or 0) end return n end
    -- tier 3 fights still needing a pop
    local n3 = 0
    for _, s in ipairs(s3) do
        local nm = znm.nms[GIVES[s][1]]
        local has_trophy = fpc and (fpc.items[nm.trophy] or 0) > 0
        if not has_trophy and held_item(nm.pop) == 0 then n3 = n3 + 1 end
    end
    if fpc and (fpc.items[t.pop] or 0) > 0 then return { {} } end
    local out = {}
    local n2 = math.max(0, n3 - held_seal(s2))
    for _, m2 in ipairs(multisets(GIVES[s2], n2)) do
        -- tier 2 fights that still need a pop -> tier 1 seals needed
        local left, pool = 0, {}
        for _, k in ipairs(m2) do
            local nm = znm.nms[k]
            pool[nm.trophy] = (pool[nm.trophy] or held_item(nm.trophy))
            pool[nm.pop] = (pool[nm.pop] or held_item(nm.pop))
            if pool[nm.trophy] > 0 then pool[nm.trophy] = pool[nm.trophy] - 1
            elseif pool[nm.pop] > 0 then pool[nm.pop] = pool[nm.pop] - 1
            else left = left + 1 end
        end
        local n1 = math.max(0, left - held_seal(s1))
        for _, m1 in ipairs(multisets(GIVES[s1], n1)) do
            local alloc = {}
            for _, k in ipairs(m2) do alloc[#alloc + 1] = k end
            for _, k in ipairs(m1) do alloc[#alloc + 1] = k end
            out[#out + 1] = alloc
        end
    end
    return out
end

local function better(a, b, cheap)
    if not b then return true end
    if a.finished ~= b.finished then return a.finished end
    if cheap then
        if a.zeni_low ~= b.zeni_low then return a.zeni_low < b.zeni_low end
        return a.minutes < b.minutes
    end
    if a.minutes ~= b.minutes then return a.minutes < b.minutes end
    return a.zeni_low < b.zeni_low
end

local function finish_result(r, H)
    local rh = false
    for _, c in ipairs(H.chars) do if c.name == H.me and c.ki[znm.rhapsody] then rh = true end end
    local all, by = {}, {}
    for who, list in pairs(r.zeni) do
        for _, p in ipairs(list) do all[#all + 1] = p end
        by[who] = { zeni_cost(list, rh) }
    end
    r.zeni_low, r.zeni_high = zeni_cost(all, rh)
    r.zeni_by = by
    local buys = { 0, 0, 0, 0 }
    for _, p in ipairs(all) do if p[1] ~= 'salt' then buys[p[1]] = buys[p[1]] + 1 end end
    r.buys = buys
    return r
end

-- targets: list of target keys. h: znm.holdings() (this character) or znm.team_holdings().
-- Returns { status, steps, kills, visits, minutes, buys, zeni_low, zeni_high, zeni_by }
function znm.plan(targets, h)
    local H = solo_holdings(h)
    local cheap = S and S.znm and S.znm.cheap
    -- pick the NMs for each target on its own, then plan them together
    local alloc = {}
    for _, tk in ipairs(targets) do
        local best, best_alloc
        for _, a in ipairs(choices(tk, H)) do
            local r = finish_result(simulate({ tk }, H, a), H)
            if better(r, best, cheap) then best, best_alloc = r, a end
        end
        for _, k in ipairs(best_alloc or {}) do alloc[#alloc + 1] = k end
    end
    local r = finish_result(simulate(targets, H, alloc), H)

    -- status at the top (the final popper's view)
    local status = {}
    for _, tk in ipairs(targets) do
        local t = znm.targets[tk]
        local c = H.chars[1]
        for _, x in ipairs(H.chars) do if x.name == H.fp[tk] then c = x end end
        status[#status + 1] = ('%s%s: %s %s | %s %s'):format(t.name, H.team and (' (' .. H.fp[tk] .. ')') or '',
            item_name(t.pop), (c.items[t.pop] or 0) > 0 and 'yes' or 'no', ki_name(t.salt), c.ki[t.salt] and 'yes' or 'no')
        for _, s in ipairs(t.seals) do
            status[#status + 1] = ('  %s %s (%s)'):format(c.ki[s] and '+' or '-', ki_name(s), znm.nms[GIVES[s][1]].name)
        end
    end
    r.status = status
    r.cheap = cheap
    return r
end

local function gil(n) return (tostring(n):reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')) end
znm.fmt = gil

local function holdings_for(targets, team_mode, chars, me)
    if team_mode then return znm.team_holdings(targets, chars, me) end
    return znm.holdings()
end

-- Zeni still needed for one target (or a list), as the low/high pair.
function znm.zeni_for(targets, h)
    local p = znm.plan(targets, h or znm.holdings())
    return p.zeni_low, p.zeni_high, p
end

-- 'Zeni needed' lines: one per target, plus the total when there are several (and who pays, in team mode).
function znm.zeni_lines(targets, team_mode, chars, me)
    local out = {}
    local range = function(lo, hi) return lo == hi and gil(lo) or (gil(lo) .. '-' .. gil(hi)) end
    for _, tk in ipairs(targets) do
        local lo, hi, p = znm.zeni_for({ tk }, holdings_for({ tk }, team_mode, chars, me))
        out[#out + 1] = ('Zeni for %s: %s%s'):format(znm.targets[tk].name, range(lo, hi),
            p.buys[4] > 0 and ' (incl. ~5,000 est. for the last pop)' or '')
    end
    local lo, hi, p = znm.zeni_for(targets, holdings_for(targets, team_mode, chars, me))
    if #targets > 1 then
        out[#out + 1] = ('Zeni for all three: %s (low: base prices, high: bought in a row)'):format(range(lo, hi))
    end
    if team_mode then
        local parts, names = {}, {}
        for who in pairs(p.zeni_by) do names[#names + 1] = who end
        table.sort(names)
        for _, who in ipairs(names) do parts[#parts + 1] = ('%s %s'):format(who, gil(p.zeni_by[who][1])) end
        if #parts > 0 then out[#out + 1] = 'Zeni each (base prices): ' .. table.concat(parts, ', ') end
    end
    return out
end

-- The plan as plain lines (chat and the Zeni tab). team_mode: pool all your characters.
function znm.lines(targets, team_mode)
    local chars, me
    if team_mode then chars, me = znm.team() end
    local h = holdings_for(targets, team_mode, chars, me)
    local p = znm.plan(targets, h)
    local out = {}
    if team_mode then
        out[#out + 1] = ('Team: %s. (name) = who pops the final NM.'):format(table.concat(h.names, ', '))
    end
    for _, s in ipairs(p.status) do out[#out + 1] = s end
    if #p.steps == 0 then
        out[#out + 1] = 'Nothing left to do: you have everything for this.'
        return out, p
    end
    out[#out + 1] = ('Plan (%s): %d step(s), %d fight(s), %d Sanraku visit(s), about %d min.'):format(
        p.cheap and 'cheapest' or 'fastest', #p.steps, p.kills, p.visits, p.minutes)
    for _, l in ipairs(znm.zeni_lines(targets, team_mode, chars, me)) do out[#out + 1] = l end
    for i, s in ipairs(p.steps) do
        out[#out + 1] = ('%d. %s'):format(i, s.title)
        for _, l in ipairs(s.lines) do
            -- long lines: break before the last ' (' so they fit the window
            local cut = #l > 73 and l:find(' %([^(]*$') or nil
            if cut then
                out[#out + 1] = '   ' .. l:sub(1, cut - 1)
                out[#out + 1] = '        ' .. l:sub(cut + 1)
            else
                out[#out + 1] = '   ' .. l
            end
        end
    end
    return out, p
end

-- What your other characters hold (from their saved bag lists).
function znm.others()
    local okf, find = pcall(require, 'st_find')
    if not okf or type(find) ~= 'table' or not find.all_chars then return {} end
    local list, me = find.all_chars()
    local out = {}
    for _, c in ipairs(list) do
        if c.name ~= me then
            local names = {}
            for _, bag in pairs(c.bags or {}) do
                for id in pairs(bag) do if znm.item_ids[id] then names[item_name(id)] = true end end
            end
            for _, id in ipairs(c.key_items or {}) do if znm.ki_ids[id] then names[ki_name(id)] = true end end
            local t = {}
            for n in pairs(names) do t[#t + 1] = n end
            table.sort(t)
            if #t > 0 then out[#out + 1] = ('%s has: %s'):format(c.name, table.concat(t, ', ')) end
        end
    end
    return out
end

-- Team mode on unless switched off (//stw znm solo, or the Zeni tab button).
function znm.team_mode() return not (S and S.znm and S.znm.solo) end

function znm.parse_targets(arg)
    arg = (arg or ''):lower()
    if znm.targets[arg] then return { arg } end
    return { 'tinnin', 'sarameya', 'tyger' }
end

-- //stw znm [tinnin|sarameya|tyger|all] [team|solo|fast|cheap]
function znm.command(arg, arg2)
    local a1, a2 = (arg or ''):lower(), (arg2 or ''):lower()
    local target = a1
    for _, a in ipairs({ a1, a2 }) do
        if a == 'team' or a == 'solo' or a == 'fast' or a == 'cheap' then
            S.znm = S.znm or {}
            if a == 'team' or a == 'solo' then S.znm.solo = (a == 'solo') else S.znm.cheap = (a == 'cheap') end
            local okst, store = pcall(require, 'st_store')
            if okst then store.save(S) end
            log(({ team = 'Zeni planner: team mode (all your characters).', solo = 'Zeni planner: this character only.',
                   fast = 'Zeni planner: fastest path (may cost more zeni).', cheap = 'Zeni planner: cheapest path (may take longer).' })[a])
            if a == a1 then target = a2 end
        end
    end
    local team_mode = znm.team_mode()
    local lines = znm.lines(znm.parse_targets(target), team_mode)
    for _, l in ipairs(lines) do log(l) end
    if not team_mode then for _, l in ipairs(znm.others()) do log('  ' .. l) end end
end

function znm.init(settings, logger, sorter_module)
    S, log, sorter = settings, logger, sorter_module
end

return znm
