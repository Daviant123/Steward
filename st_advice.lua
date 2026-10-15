--[[
Steward advice: after sorting, suggest what to sell, toss or store.

Only looks outside the wardrobes, and never suggests Keep-list, equipped, quest, currency,
slip, linkshell, crystal or automaton items. These are suggestions only; nothing is sold or
dropped unless you act on them.

  SELL   materials / furniture that can be sold (NPC, or check the Auction House first)
  TOSS   Ex items an NPC won't buy, except names that are usually upgrade materials or
         currencies (vouchers, abjurations, seals, cards, keys, shards...): those are never suggested
  //stw advice ignore add <item> hides any item from all suggestions
  STORE  gear a Porter Moogle can hold (slip-storable)
  DUPES  extra copies of gear you already keep in a wardrobe
]]

local res = require('resources')
local store = require('st_store')
local rules = require('st_rules')
local journal = require('st_journal')
local slips_ok, slips = pcall(require, 'slips')

local advice = { last = nil }
local S, log, sorter

-- Never suggested as TOSS: names that are usually progression materials or currencies even
-- though they're Ex and worth nothing to an NPC. Seen in real advice output: Ambuscade vouchers,
-- Abjurations, Abdhaljs materials, Dynamis crest cards, Dial Keys, Copper Vouchers, souls, shards...
-- (Exclusions-first, as WoW's Dejunk does.)
advice.protect = { 'voucher', 'vou.', 'abjur', 'abjuration', 'abdhaljs', 'seal', 'crest', 'card', 'key', 'soul', 'shard',
    'orb', 'coin', 'bill', 'bronzepiece', 'whiteshell', 'silverpiece', 'jadeshell', 'plan', 'plate',
    'memento', 'token', 'fragment', 'petrifact', 'cermet', 'stone', 'sphere', 'eikondrite', 'gallimaufry',
    'matter', 'ichor', 'beitetsu', 'riftcinder', 'riftborn', 'pluton', 'boulder', 'ticket', 'chip', 'page',
    'tale', 'remnant', 'tome', 'gem', 'mark', 'feather', 'horn', 'scale', 'fang', 'wing', 'hide', 'pelt',
    'medal', 'chit', 'cipher', 'scroll', 'invitation', 'permit', 'statue', 'flag', 'coffer', 'box', 'chest',
    'pouch', 'sack', 'case', 'bag', 'parcel' }
-- Sell items that can go on the AH (not Ex / No Auction): what //stw prices looks up.
function advice.ah_ids()
    local a = advice.compute()
    local seen, ids = {}, {}
    for _, e in ipairs(a.sell) do
        if not e.no_ah and not seen[e.id] then seen[e.id] = true ids[#ids + 1] = e.id end
    end
    return ids
end

-- Never suggested as SELL: money you spend, not sell.
advice.currency_words = { 'byne bill', 'bronzepiece', 'whiteshell', 'silverpiece', 'jadeshell',
    'montiont', 'ordelle', 'lungo-nango', 'tukuku', 'coin of ' }

local function has_word(name, words)
    local n = name:lower()
    for _, w in ipairs(words) do
        if n:find(w, 1, true) then return true end
    end
    return false
end
-- Checks the short name and the long (log) name, e.g. "A. Vou.: Body +1" / "ambuscade voucher: body +1".
function advice.protected(name, item)
    if has_word(name, advice.protect) then return true end
    local long = item and (item.english_log or item.enl)
    return type(long) == 'string' and has_word(long, advice.protect)
end

local skip_cats = { quest = true, currency = true, slips = true, linkshells = true, crystals = true,
                    automaton = true, consumables = true }

local function has_flag(item, flag)
    local f = item and item.flags
    if type(f) ~= 'table' then return false end
    if f[flag] == true then return true end
    return type(f.contains) == 'function' and f:contains(flag) or false
end

local OUTSIDE = { 0, 5, 6, 7, 1, 9, 2, 4 }   -- inventory, satchel, sack, case, safe, safe2, storage, locker

function advice.compute()
    local st = sorter.snapshot()
    local keep = rules.name_set(S.lists.keep)
    local drop = rules.name_set(S.lists.drop)
    local ignore = rules.name_set(S.lists.ignore or '')
    local npc_ids = {}
    local okn, npcmod = pcall(require, 'st_npc')
    if okn and type(npcmod) == 'table' and npcmod.types then
        for _, t in ipairs(npcmod.types) do for _, id in ipairs(t.ids) do npc_ids[id] = true end end
    end
    local protected = sorter.protected_ids(st)
    local out = { sell = {}, toss = {}, store = {}, dupes = {} }
    local owned_slip = {}
    if slips_ok and type(slips.items) == 'table' then
        for _, bag in pairs(st.bags) do
            for _, it in pairs(bag.items) do if slips.items[it.id] then owned_slip[it.id] = true end end
        end
        -- slips kept in Mog House bags while you're away (saved list)
        local okp, porter = pcall(require, 'st_porter')
        if okp and type(porter) == 'table' and porter.saved_home_items then
            for _, c in ipairs((porter.saved_home_items(st))) do
                if slips.items[c.id] then owned_slip[c.id] = true end
            end
        end
    end
    local seen = {}

    for _, bid in ipairs(OUTSIDE) do
        local bag = st.bags[bid]
        for _, it in pairs(bag.items) do
            local item = res.items[it.id]
            local name = rules.item_name(it.id)
            local cat = rules.category(it.id)
            local key = it.id .. '@' .. bid
            local ok = item and it.status == 0 and not keep[name:lower()] and not drop[name:lower()]
                and not ignore[name:lower()] and not npc_ids[it.id]
                and not (bid == 0 and sorter.in_transit(it))
            if ok then
                local e = seen[key]
                if e then
                    e.count = e.count + (it.count or 1)
                else
                    e = { id = it.id, name = name, count = it.count or 1, bag = bid,
                          where = rules.pretty_bag[bag.name] }
                    seen[key] = e
                    if cat == 'equipment' then
                        if protected[it.id] then
                            e.why = 'also in a wardrobe'
                            out.dupes[#out.dupes + 1] = e
                        elseif slips_ok and slips.get_slip_id_by_item_id(it.id) then
                            local sid = slips.get_slip_id_by_item_id(it.id)
                            local no = slips.get_slip_number_by_id(sid) or 0
                            e.why = owned_slip[sid] and ('Porter slip %02d'):format(no) or ('buy Slip %02d first'):format(no)
                            out.store[#out.store + 1] = e
                        end
                    elseif not skip_cats[cat] then
                        local no_npc = has_flag(item, 'No NPC Sale')
                        local ex = has_flag(item, 'Exclusive') or has_flag(item, 'No PC Trade')
                        local no_ah = ex or has_flag(item, 'No Auction')
                        if no_npc and ex then
                            if not advice.protected(name, item) then
                                e.why = "Ex, no NPC value"
                                out.toss[#out.toss + 1] = e
                            end
                        elseif has_word(name, advice.currency_words) then
                            -- currency: neither sell nor toss
                        elseif not no_npc then
                            e.why = no_ah and 'sell to an NPC' or 'check AH, else NPC'
                            e.no_ah = no_ah
                            out.sell[#out.sell + 1] = e
                        else
                            e.why = 'AH or bazaar (no NPC)'
                            e.no_ah = no_ah
                            out.sell[#out.sell + 1] = e
                        end
                    end
                end
            end
        end
    end
    -- ffxiah.com prices (//stw prices): the Advice text, and which ones are worth the Auction House.
    local okp, prices = pcall(require, 'st_prices')
    if okp and type(prices) == 'table' and prices.verdict then
        for _, e in ipairs(out.sell) do
            if not e.no_ah then
                local txt, worth = prices.verdict(e.id)
                if txt then e.why, e.ah = txt, worth end
            end
        end
    end
    for _, list in pairs(out) do table.sort(list, function(a, b) return a.name < b.name end) end
    advice.last = out
    return out
end

-- Distinct item names (an item kept in two bags is one suggestion, not two).
local function distinct(list)
    local seen, t = {}, {}
    for _, e in ipairs(list) do
        if not seen[e.name] then seen[e.name] = true t[#t + 1] = e.name end
    end
    return t
end

local function names(list, n)
    local d = distinct(list)
    local t = {}
    for i = 1, math.min(n, #d) do t[#t + 1] = d[i] end
    if #d > n then t[#t + 1] = '...' end
    return table.concat(t, ', ')
end
local function count(list) return #distinct(list) end

-- One short chat summary (after a sort). quiet = only if something changed since last time.
local last_sig
function advice.report(quiet)
    local a = advice.compute()
    local sig = ('%d/%d/%d/%d'):format(#a.sell, #a.toss, #a.store, #a.dupes)
    if quiet and sig == last_sig then return end
    last_sig = sig
    if #a.sell + #a.toss + #a.store + #a.dupes == 0 then
        if not quiet then log('Next steps: nothing to sell, toss or store. All tidy.') end
        return
    end
    local parts = {}
    if #a.sell > 0 then parts[#parts + 1] = ('Sell %d (%s)'):format(count(a.sell), names(a.sell, 3)) end
    local ah = {}
    for _, e in ipairs(a.sell) do if e.ah then ah[#ah + 1] = e end end
    if #ah > 0 then parts[#parts + 1] = ('%d worth the AH (%s)'):format(count(ah), names(ah, 3)) end
    if #a.toss > 0 then parts[#parts + 1] = ('Toss %d (%s)'):format(count(a.toss), names(a.toss, 3)) end
    if #a.store > 0 then parts[#parts + 1] = ('Store %d at a Porter'):format(count(a.store)) end
    if #a.dupes > 0 then parts[#parts + 1] = ('%d duplicate gear'):format(count(a.dupes)) end
    log('Next steps: ' .. table.concat(parts, ' | ') .. '.')
    local cmds = { '//stw advice (details)' }
    if #a.sell > 0 then cmds[#cmds + 1] = '//stw sellprep (gather to sell)' end
    if #a.store > 0 then cmds[#cmds + 1] = '//stw porter prep (at home), then //stw porter store' end
    if #a.toss > 0 then cmds[#cmds + 1] = '//stw drop add <item> (toss)' end
    log('  ' .. table.concat(cmds, '  |  '))
    journal.write('ADVICE', 'sell=%d [%s] toss=%d [%s] store=%d [%s] dupes=%d [%s]',
        count(a.sell), names(a.sell, 50), count(a.toss), names(a.toss, 50), count(a.store), names(a.store, 50),
        count(a.dupes), names(a.dupes, 50))
end

-- Pull the sell items into the inventory and hold auto-sort for 10 minutes so you can sell them.
function advice.gather_sell()
    local a = advice.compute()
    if #a.sell == 0 then log('Nothing to sell. (//stw advice shows suggestions)') return end
    sorter.hold_until = os.clock() + 600
    log('Gathering sell items into your inventory. Auto-sort is held for 10 minutes while you sell.')
    journal.write('ADVICE', 'gather sell items; auto-sort held 10 min')
    local st = sorter.snapshot()
    local moved = 0
    for _, e in ipairs(a.sell) do
        if e.bag ~= 0 and st.bags[e.bag].access then
            for index, it in pairs(st.bags[e.bag].items) do
                local info = windower.ffxi.get_bag_info(0)
                if it.id == e.id and it.status == 0 and info and info.max - info.count > 1 then
                    journal.write('MOVE', '%s x%d  %s[%d] -> inventory  (gather to sell)', e.name, it.count or 1,
                        rules.bag_names[e.bag] or e.bag, index)
                    windower.ffxi.get_item(e.bag, index, it.count or 1)
                    moved = moved + 1
                    coroutine.sleep(S.delay)
                end
            end
        end
    end
    log(('Gathered %d stack%s. Sell them at any NPC shop; //stw unhold ends the hold early.'):format(moved, moved == 1 and '' or 's'))
end

-- //stw advice ignore [add|remove] <item>: never suggest this item (like Dejunk's exclusions).
function advice.ignore(action, name)
    local list = rules.split(S.lists.ignore or '')
    if action ~= 'add' and action ~= 'remove' or not name or name == '' then
        log('Advice ignore list: ' .. (#list > 0 and table.concat(list, ', ') or '(empty)'))
        log('  //stw advice ignore add <item>  |  //stw advice ignore remove <item>')
        return
    end
    local out, found = {}, false
    for _, n in ipairs(list) do
        if n:lower() == name:lower() then found = true else out[#out + 1] = n end
    end
    if action == 'add' then
        local canon = name
        for id, item in pairs(res.items) do
            if type(item) == 'table' and (item.english or ''):lower() == name:lower() then canon = item.english break end
        end
        out[#out + 1] = canon
    end
    table.sort(out)
    S.lists.ignore = rules.join(out)
    store.save(S)
    journal.write('SET', 'advice ignore %s %s', action, name)
    if action == 'add' then log(name .. ' will not be suggested any more. (//stw advice ignore remove ' .. name .. ' to undo)')
    else log(found and (name .. ' can be suggested again.') or (name .. ' was not on the ignore list.')) end
    advice.last = nil
end

function advice.init(settings, logger, sorter_module)
    S, log, sorter = settings, logger, sorter_module
end

return advice
