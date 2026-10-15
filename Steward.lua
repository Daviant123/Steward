_addon.name = 'Steward'
_addon.author = 'Daviant'
_addon.version = '1.1.0'
_addon.commands = { 'steward', 'stw' }

--[[
Steward keeps every character's bags organized automatically.

  * Sorts items into their home bags by category (crystals, food, materials, slips, ...).
  * Sorts the mog wardrobes by gear slot. Wardrobe gear never leaves the wardrobes and is never
    given to a Porter Moogle.
  * Treasury-style Drop / Lot / Pass lists, auto-stack, and a Keep list for the inventory.
  * Stores slip-eligible gear from your other bags with a Porter Moogle.
  * Clickable in-game window: //stw

Settings are saved per character in data/settings.xml.
]]

local config = require('config')
local store = require('st_store')
local rules = require('st_rules')
local sorter = require('st_sorter')
local loot = require('st_loot')
local porter = require('st_porter')
local gui = require('st_gui')
local guard = require('st_guard')
local journal = require('st_journal')
local picker = require('st_picker')
local advice = require('st_advice')
local npc = require('st_npc')
local find = require('st_find')
local audit = require('st_audit')
local sell = require('st_sell')
local prices = require('st_prices')
local znm = require('st_znm')
local update = require('st_update')

------------------------------------------------------------------------
-- Settings
------------------------------------------------------------------------
local default_rules = {}
for _, c in ipairs(rules.categories) do default_rules[c.key] = c.default end
local default_wardrobes = {}
for _, g in ipairs(rules.slot_groups) do default_wardrobes[g.key] = 0 end   -- 0 = automatic layout
local default_overflow = {}
for _, c in ipairs(rules.categories) do default_overflow[c.key] = '' end         -- '' = automatic 2nd/3rd bags

local defaults = {
    auto = { sort = true, wardrobes = true, drop = true, dropbags = true, lotpass = true, stack = true },
    delay = 0.6,
    merge_stacks = true,
    drop_grace = 10,       -- seconds after adding to the Drop list before held copies are dropped (cancel window)   -- merge split stacks of one item across bags during a sort (//stw merge on|off)
    free_goal = 70,        -- keep this many inventory slots free, or as close as possible (0 = off)
    goal70_done = false,   -- one-time switch of saved settings to 70
    verbose = false,
    rules = default_rules,
    overflow = default_overflow,   -- your own 2nd/3rd bag per category ('bag2|bag3'), '' = automatic
    wardrobes = default_wardrobes,
    lists = { keep = rules.default_keep, drop = '', lot = '', pass = '', ignore = '', sell = '' },
    porter = { exclude = '', include_inventory = false, buy_options = '' },
    prices = { server = 'carbuncle', every = 5, min_ah = 2000, max_age_days = 3 },   -- //stw prices (ffxiah.com)
    update = { repo = 'Daviant123/Steward', branch = 'main', check = true },   -- //stw update (GitHub page owner/name)
    znm = { solo = false, cheap = false },   -- Zeni planner: team mode (all characters), fastest path
    gui = { x = 320, y = 180, visible = true, px = 120, py = 90 },
    journal = true,     -- activity log in data/logs (turn off with //stw log off)
    gear_to_safe_done = false,   -- one-time switch: gear outside wardrobes -> Mog Safe bags
    transit = '',
}

local settings = config.load(defaults)

local function log(msg) windower.add_to_chat(207, '[Steward] ' .. msg) end

-- For troubleshooting: //lua e print(steward_settings().rules.crystals)
function steward_settings() return settings end

------------------------------------------------------------------------
-- Actions (used by commands and the window)
------------------------------------------------------------------------
local actions = {}

local function busy() return sorter.running or porter.busy or porter.prepping or porter.buying or npc.busy end

-- Automatic sorting only runs after //stw start (it is off every time Steward loads).
actions.armed = false

function actions.start()
    actions.armed = true
    journal.write('AUTO', 'automatic sorting started by user')
    log('Automatic sorting is ON for this session. //stw stop turns it off.')
    actions.mark_dirty()
end

function actions.sort(opts)
    if busy() then log('Already busy. //stw stop stops it.') return end
    if not sorter.safe() then log('Stand still (idle), then //stw sort.') return end
    coroutine.schedule(function() sorter.run(opts) end, 0)
end

function actions.stop()
    sorter.stop_requested = true
    porter.stop_prep = true
    if porter.buy_stop then porter.buy_stop() end
    npc.stop = true
    prices.stop = true
    if actions.armed then
        actions.armed = false
        journal.write('AUTO', 'automatic sorting stopped by user')
        log('Automatic sorting is OFF. //stw start turns it back on; //stw sort does one pass.')
    end
    if porter.busy then porter.finish('Stopped.') end
end

function actions.stack()
    local was = settings.auto.stack
    settings.auto.stack = true
    loot.stack()
    settings.auto.stack = was
end

function actions.toggle(key)
    settings.auto[key] = not settings.auto[key]
    store.save(settings)
    journal.write('SET', 'auto %s = %s', key, tostring(settings.auto[key]))
    log(('Auto %s: %s  (//stw auto %s on|off)'):format(key, settings.auto[key] and 'on' or 'off', key))
    if settings.auto[key] and (key == 'sort' or key == 'wardrobes') then actions.mark_dirty() end
end

function actions.cycle_rule(cat)
    local cur = settings.rules[cat] or 'stay'
    local list = rules.destinations
    local idx = 1
    for i, d in ipairs(list) do if d == cur then idx = i end end
    local st = sorter.snapshot()
    for step = 1, #list do
        local nxt = list[(idx + step - 1) % #list + 1]
        local bag = st.bags[rules.bag_ids[nxt] or -1]
        if nxt == 'stay' or nxt == 'inventory' or (bag and bag.enabled) then
            settings.rules[cat] = nxt
            journal.write('SET', 'rule %s -> %s', cat, nxt)
            break
        end
    end
    store.save(settings)
    actions.mark_dirty()
end

-- Rules tab: click the 2nd (slot 1) or 3rd (slot 2) bag of a category to step through the bags.
-- The first click turns the automatic choices into your own, so nothing else changes.
function actions.cycle_overflow(cat, slot)
    local home = settings.rules[cat] or 'stay'
    local slots = rules.overflow_slots(cat, home)
    local other = slots[3 - slot]
    local list = {}
    for _, b in ipairs(rules.overflow_choices) do list[#list + 1] = b end
    list[#list + 1] = 'none'
    local idx = #list
    for i, b in ipairs(list) do if b == slots[slot] then idx = i end end
    local st = sorter.snapshot()
    for step = 1, #list do
        local nxt = list[(idx + step - 1) % #list + 1]
        local bag = st.bags[rules.bag_ids[nxt] or -1]
        if nxt == 'none' or (nxt ~= home and nxt ~= other and bag and bag.enabled) then
            slots[slot] = nxt
            break
        end
    end
    settings.overflow[cat] = slots[1] .. '|' .. slots[2]
    journal.write('SET', 'overflow %s -> %s', cat, settings.overflow[cat])
    store.save(settings)
    actions.mark_dirty()
end

function actions.reset_overflow(cat)
    for _, c in ipairs(rules.categories) do
        if not cat or c.key == cat then settings.overflow[c.key] = '' end
    end
    journal.write('SET', 'overflow %s -> automatic', cat or 'all')
    store.save(settings)
    actions.mark_dirty()
end

function actions.cycle_wardrobe(group)
    local st = sorter.snapshot()
    local cur = rules.is_wardrobe[sorter.wardrobe_for_group(st, group)] or 1
    for step = 1, 8 do
        local n = (cur + step - 1) % 8 + 1
        if st.bags[rules.wardrobes[n]].enabled then
            settings.wardrobes[group] = n
            journal.write('SET', 'wardrobe %s -> %d', group, n)
            break
        end
    end
    store.save(settings)
    actions.mark_dirty()
end

function actions.list_edit(list, action, name)
    if list == 'keep' then
        local out, found = {}, false
        for _, n in ipairs(rules.split(settings.lists.keep)) do
            if n:lower() == name:lower() then found = true else out[#out + 1] = n end
        end
        if action == 'add' then out[#out + 1] = loot.canonical(name) or name end
        table.sort(out)
        settings.lists.keep = rules.join(out)
        store.save(settings)
        log(action == 'add' and (name .. ' added to keep list. (//stw keep remove ' .. name .. ' to undo)') or (found and (name .. ' removed from keep list.') or (name .. ' was not on the keep list.')))
        return
    end
    if list == 'sell' and action == 'add' then
        local why = sell.refuse(name)
        if why then log(why) journal.write('SET', 'sell list refused: %s', why) return end
    end
    local msg = loot.edit(list, action, name)
    journal.write('SET', msg)
    log(msg)
    if list == 'sell' and loot.known_name(name) then sell.edited(action, name) end
    loot.force_check()
end

function actions.goal_step(d)
    settings.free_goal = math.max(0, math.min(80, (tonumber(settings.free_goal) or 0) + d))
    store.save(settings)
    journal.write('SET', 'free-slot goal = %d', settings.free_goal)
    actions.mark_dirty()
end

-- //stw prices: AH prices for the items Advice would sell (slow, on purpose: each page hitches the game).
function actions.prices()
    if prices.running then log('Prices: already running. //stw prices stop stops it.') return end
    local ids = advice.ah_ids()
    if #ids == 0 then log('Prices: Advice has nothing to sell that can go on the AH.') return end
    prices.on_finish = function() gui.refresh(true) end
    coroutine.schedule(function() prices.run(ids) end, 0)
end

function actions.gather_sell()
    if busy() then log('Already busy. //stw stop stops it.') return end
    coroutine.schedule(function() advice.gather_sell() end, 0)
end

function actions.porter_prep()
    if busy() then log('Already busy. //stw stop stops it.') return end
    coroutine.schedule(function() porter.prep() end, 0)
end

function actions.unhold()
    sorter.hold_until = nil
    sorter.release()
    log('Auto-sort hold ended. (//stw sellprep to gather sell items again)')
    actions.mark_dirty()
end

function actions.porter_exclude(name)
    local out, found = {}, false
    for _, n in ipairs(rules.split(settings.porter.exclude)) do
        if n:lower() == name:lower() then found = true else out[#out + 1] = n end
    end
    if not found then out[#out + 1] = name end
    settings.porter.exclude = rules.join(out)
    store.save(settings)
end

function actions.toggle_porter_inventory()
    settings.porter.include_inventory = not settings.porter.include_inventory
    store.save(settings)
end

function actions.porter_store()
    coroutine.schedule(function() porter.store() end, 0)
end

------------------------------------------------------------------------
-- Automatic sorting: after bag changes settle and you're idle
------------------------------------------------------------------------
local dirty, last_change = true, 0

function actions.mark_dirty() dirty, last_change = true, os.clock() end

local last_auto_end = -100

local function auto_tick()
    if not actions.armed or not dirty or busy() or not guard.allow_auto() then return end
    if sorter.hold_until and os.clock() < sorter.hold_until then return end   -- holding items to sell
    if not (settings.auto.sort or settings.auto.wardrobes) then dirty = false return end
    if os.clock() - last_change < 4 or os.clock() - last_auto_end < 10 or not sorter.safe() then return end
    dirty = false
    coroutine.schedule(function()
        journal.write('AUTO', 'bags changed and you are idle: starting automatic sort')
        sorter.run({ bags = settings.auto.sort, wardrobes = settings.auto.wardrobes, auto = true })
        last_auto_end = os.clock()
    end, 0)
end

-- One chat line a minute at most for automatic sorting.
local last_summary = 0
local function auto_summary()
    if os.clock() - last_summary < 60 then return end
    last_summary = os.clock()
    if (sorter.auto_moved or 0) > 0 then
        log(('Auto-sort put away %d item%s. (//stw log shows each move, //stw auto sort off turns it off)'):format(sorter.auto_moved, sorter.auto_moved == 1 and '' or 's'))
        sorter.auto_moved = 0
    end
end

sorter.on_finish = function()
    dirty = false
    local o = sorter.last_opts or {}
    if not sorter.stop_requested then
        if o.auto then
            if sorter.moved > 0 then guard.call('Advice', advice.report, true) end
        else
            guard.call('Advice', advice.report, false)
        end
    end
    gui.refresh(true)
end
guard.on_pause = function()
    sorter.stop_requested = true
    dirty = false
    gui.refresh(true)
end

function actions.resume()
    guard.resume()
    actions.mark_dirty()
end
porter.on_finish = function() actions.mark_dirty() gui.refresh(true) end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local started = false
local function start()
    if started or not windower.ffxi.get_info().logged_in then return end
    started = true
    actions.armed = false
    journal.enabled = settings.journal
    if not settings.goal70_done then
        settings.free_goal = 70
        settings.goal70_done = true
        store.save(settings)
    end
    if not settings.gear_to_safe_done then
        -- Gear outside the wardrobes now goes to Safe / Safe 2 / Storage / Locker in the Mog House.
        settings.rules.equipment = 'safe'
        settings.gear_to_safe_done = true
        store.save(settings)
    end
    journal.write('LOAD', 'Steward %s loaded. auto: sort=%s wardrobes=%s drop=%s lotpass=%s stack=%s',
        _addon.version, tostring(settings.auto.sort), tostring(settings.auto.wardrobes), tostring(settings.auto.drop),
        tostring(settings.auto.lotpass), tostring(settings.auto.stack))
    guard.init(log)
    sorter.guard = guard
    rules.overflow_source = function() return settings.overflow end
    sorter.init(settings, log)
    loot.init(settings, log, busy)
    sell.init(settings, log, loot)
    prices.init(settings, log)
    znm.init(settings, log, sorter)
    update.init(settings, log)
    loot.armed = function() return actions.armed end
    loot.allowed = function() return guard.allow_auto() end
    porter.init(settings, log, sorter)
    picker.init(settings, log, actions)
    advice.init(settings, log, sorter)
    npc.init(settings, log, sorter)
    find.init(settings, log, sorter)
    audit.init(settings, log, sorter)
    gui.init(settings, log, { sorter = sorter, loot = loot, porter = porter, actions = actions, guard = guard, picker = picker, advice = advice, npc = npc, sell = sell, prices = prices, znm = znm })
    guard.call('Loot', loot.force_check)
    actions.mark_dirty()
    log('Loaded. Nothing is sorted until you say so: //stw start (automatic) or //stw sort (one pass).')
    log('  //stw opens the window, //stw help lists commands (also on the Help tab).')
    update.on_load()
end

windower.register_event('load', start)
windower.register_event('login', function()
    coroutine.schedule(function()
        settings = config.load(defaults)
        started = false
        start()
    end, 5)
end)
windower.register_event('unload', function()
    if started then pcall(find.save) end
end)
windower.register_event('logout', function()
    if started then pcall(find.save) end
    gui.destroy()
    picker.destroy()
    started = false
end)

windower.register_event('incoming chunk', function(id, data, modified, injected, blocked)
    if not started then return end
    local ok, r = pcall(porter.incoming, id, data)
    if not ok then guard.error('Porter', r) r = nil end
    if r ~= nil then return r end
    if guard.allow_auto() then guard.call('Loot', loot.incoming, id, data) end
    if id == 0x03C then guard.call('Sell', sell.incoming, id) end
    if id == 0x01F or id == 0x020 then
        find.mark()
        -- Our own moves also land here; the sorter re-reads bags after each move anyway.
        if not sorter.running then actions.mark_dirty() end
    end
end)

windower.register_event('incoming text', function(original, modified, mode)
    if not started then return end
    local ok, r = pcall(npc.text, original, modified, mode)
    if ok and r then return r end
end)

windower.register_event('outgoing chunk', function(id, data, modified, injected, blocked)
    if started then guard.call('Porter', porter.outgoing, id, injected, data) end
end)

windower.register_event('zone change', function()
    sorter.pause_until = os.clock() + 8
    sorter.stop_requested = true
    actions.mark_dirty()
end)

local last_tick = 0
windower.register_event('prerender', function()
    if not started then return end
    local t = os.clock()
    if t - last_tick < 1 then return end
    last_tick = t
    guard.call('Porter', porter.watchdog)
    guard.call('Auto-sort', auto_tick)
    guard.call('Window', gui.refresh)
    guard.call('Picker', picker.refresh)
    guard.call('Find', find.tick)
    guard.call('Loot', loot.tick)
    auto_summary()
end)

windower.register_event('mouse', function(mtype, x, y, delta, blocked)
    if not started then return false end
    local pok, pr = pcall(picker.mouse, mtype, x, y, delta, blocked)
    if not pok then guard.error('Picker', pr) elseif pr then return true end
    local ok, r = pcall(gui.mouse, mtype, x, y, delta, blocked)
    if not ok then guard.error('Window', r) return false end
    return r
end)

------------------------------------------------------------------------
-- Commands
------------------------------------------------------------------------
local help = {
    '//stw                     show / hide the window',
    '//stw sort [bags|wardrobes]   sort now (default: everything)',
    '//stw start               start automatic sorting (off every time Steward loads)',
    '//stw stop                stop automatic sorting and anything running',
    '//stw goal <n>            keep n inventory slots free (0 = off, default 70)',
    '//stw picker              big clickable list of your items to add to the Drop list',
    '//stw advice              next steps: what to sell, toss or store',
    '//stw advice ignore add|remove <item>   never suggest this item (ignore alone lists them)',
    '//stw sellprep            gather sell items into the inventory (holds auto-sort 10 min)',
    '//stw unhold              end a sell or porter-prep hold early',
    '//stw resume              resume automation after a safety pause',
    '//stw log [on|off]        activity log file (shows where it is)',
    '//stw keep|drop|lot|pass|sell add|remove <item>',
    '//stw keep|drop|lot|pass|sell list    //stw sell load  (queue the Sell list in SellNPC)',
    '//stw rule <category> <bag>   e.g. rule crystals sack  (stay/inventory/satchel/sack/case/safe/safe2/locker/storage)',
    '//stw wardrobe <group> <1-8>  e.g. wardrobe accessories 7 (0 = automatic)',
    '//stw auto <sort|wardrobes|drop|dropbags|lotpass|stack> [on|off]',
    '//stw porter prep         (at home) gather storable gear + slips into the inventory for a Porter',
    '//stw porter list|store',
    '//stw porter buy [confirm]   buy the slips Advice needs (1,000 gil each), at a Porter Moogle',
    '//stw porter slips        which slips you have / would need to buy (and how many slots each frees)',
    '//stw npc                 NPC storage: what you have of each kind and where it goes',
    '//stw seals | crystals | vouchers | remstales | beastcoins | salvage | soulplates | gobbiekeys [prep|store|list]',
    '//stw moatcarp | mellidopt | alexandrite | zinc | yagudo | mandragora | onlybest | jsecapes | jsecapes3',
    '//stw stones | befouled | geaszitah | geasruaun | geasreis     (//stw npc lists them all)',
    '//stw trade               trade with whichever of these NPCs you target or stand next to (like //qtr)',
    '//stw update [install]    check for / install a newer Steward from its GitHub page',
    '                          at the NPC: trades them all; elsewhere: gathers them into the inventory',
    '//stw audit [job|all]     GearSwap files vs wardrobes: gear missing from wardrobes, wardrobe gear unused',
    '//stw find <text>         search every bag of every character (e.g. find nyame, find *crest)',
    '//stw merge [on|off]      list split stacks (same item in 2+ partial stacks); merged on every sort',
    '//stw stack | verbose | delay <seconds>',
}

windower.register_event('addon command', function(cmd, ...)
    local args = { ... }
    cmd = (cmd or ''):lower()
    if not started then start() end

    if cmd == '' or cmd == 'show' or cmd == 'hide' or cmd == 'gui' then
        if cmd == 'show' then gui.show() elseif cmd == 'hide' then gui.hide() else gui.toggle() end
    elseif cmd == 'sort' then
        local what = (args[1] or 'all'):lower()
        actions.sort({ bags = what ~= 'wardrobes', wardrobes = what ~= 'bags' })
    elseif cmd == 'start' then
        actions.start()
    elseif cmd == 'stop' then
        actions.stop()
    elseif npc.by_key[cmd] then
        npc.command(cmd, args[1])
    elseif cmd == 'trade' or cmd == 'qtr' then
        npc.auto()
    elseif cmd == 'npc' then
        for _, t in ipairs(npc.types) do
            local c = npc.count(t)
            log(('  %-11s %4d in inv, %4d in bags, %4d at home -> %s (%s)%s'):format(t.key, c.inv, c.reach, c.far,
                t.npcs[1], t.where, t.untested and ' [untested]' or ''))
        end
        log('  //stw <kind> at the NPC trades them; elsewhere it gathers them. e.g. //stw seals')
    elseif cmd == 'audit' then
        guard.call('Audit', audit.run, args[1])
    elseif cmd == 'find' or cmd == 'search' then
        guard.call('Find', find.command, args)
    elseif cmd == 'merge' then
        local sub = (args[1] or ''):lower()
        if sub == 'on' or sub == 'off' then
            settings.merge_stacks = (sub == 'on')
            store.save(settings)
            journal.write('SET', 'merge split stacks = %s', sub)
            actions.mark_dirty()
        end
        local splits = sorter.split_stacks(sorter.snapshot())
        local lines, slots = {}, 0
        for id, list in pairs(splits) do
            local where = {}
            for _, x in ipairs(list) do where[#where + 1] = ('%s x%d'):format(rules.pretty_bag[rules.bag_names[x.bag]] or x.bag, x.count) end
            lines[#lines + 1] = ('  %s: %s'):format(rules.item_name(id), table.concat(where, ', '))
            slots = slots + #list - 1
        end
        table.sort(lines)
        log(('Merge split stacks: %s. %d item%s split, up to %d slot%s to gain%s'):format(
            settings.merge_stacks ~= false and 'ON (on every sort)' or 'OFF', #lines, #lines == 1 and '' or 's',
            slots, slots == 1 and '' or 's', #lines > 0 and ':' or '.'))
        for i = 1, math.min(#lines, 12) do log(lines[i]) end
        if #lines > 12 then log(('  ... and %d more'):format(#lines - 12)) end
        if #lines > 0 and settings.merge_stacks ~= false then log('  //stw sort bags merges them now (Mog House bags only while at home).') end
    elseif cmd == 'goal' then
        local n = tonumber(args[1])
        if n and n >= 0 and n <= 80 then
            settings.free_goal = math.floor(n)
            store.save(settings)
            journal.write('SET', 'free-slot goal = %d', settings.free_goal)
            actions.mark_dirty()
        end
        log(('Inventory goal: %s  (//stw goal <n>, 0 = off)'):format(settings.free_goal > 0 and (settings.free_goal .. ' free slots') or 'off'))
    elseif (cmd == 'advice' or cmd == 'next') and (args[1] or ''):lower() == 'ignore' then
        local action = (args[2] or ''):lower()
        guard.call('Advice', advice.ignore, action, table.concat(args, ' ', 3))
        gui.refresh(true)
    elseif cmd == 'advice' or cmd == 'next' then
        guard.call('Advice', advice.report, false)
        gui.tab = 'advice'
        gui.show()
    elseif cmd == 'porterprep' or cmd == 'pprep' then
        actions.porter_prep()
    elseif cmd == 'update' then
        guard.call('Update', update.command, args)
    elseif cmd == 'znm' or cmd == 'zeni' then
        guard.call('Zeni', znm.command, args[1], args[2])
        gui.tab = 'znm'
        gui.show()
    elseif cmd == 'prices' then
        local sub = (args[1] or ''):lower()
        if sub == 'stop' then prices.stop = true log('Prices: stopping.')
        elseif sub == 'server' then
            if prices.set_server(table.concat(args, '', 2)) then
                store.save(settings)
                log(('Prices: server set to %s.'):format(settings.prices.server))
            end
        else actions.prices() end
    elseif cmd == 'sellprep' then
        actions.gather_sell()
    elseif cmd == 'unhold' then
        actions.unhold()
    elseif cmd == 'picker' or cmd == 'biglist' then
        picker.toggle()
    elseif cmd == 'resume' then
        actions.resume()
    elseif cmd == 'log' then
        local v = (args[1] or ''):lower()
        if v == 'on' or v == 'off' then
            settings.journal = (v == 'on')
            journal.enabled = settings.journal
            store.save(settings)
        end
        log(('Activity log is %s: %s'):format(settings.journal and 'ON' or 'OFF', journal.file()))
        log('Each move, skip, error, pause, porter step and drop/lot/pass is written there.')
    elseif cmd == 'keep' or cmd == 'drop' or cmd == 'lot' or cmd == 'pass' or cmd == 'sell' then
        local sub = (table.remove(args, 1) or 'list'):lower()
        local name = table.concat(args, ' ')
        if cmd == 'sell' and sub == 'load' then
            sell.load()
        elseif (sub == 'add' or sub == 'remove') and name ~= '' then
            actions.list_edit(cmd, sub, name)
        else
            log(cmd .. ' list: ' .. (settings.lists[cmd] ~= '' and settings.lists[cmd]:gsub('|', ', ') or '(empty)'))
            log(('Change it: //stw %s add <item>  |  //stw %s remove <item>'):format(cmd, cmd))
        end
    elseif cmd == 'overflow' then
        local cat = (args[1] or ''):lower()
        local b2, b3 = (args[2] or ''):lower(), (args[3] or 'none'):lower()
        local ok = {}
        for _, b in ipairs(rules.overflow_choices) do ok[b] = true end
        ok.none = true
        if rules.category_label[cat] and b2 == 'auto' then
            actions.reset_overflow(cat)
            local s = rules.overflow_slots(cat, settings.rules[cat] or 'stay')
            log(('%s: 2nd/3rd bags automatic again (%s, %s).'):format(rules.category_label[cat], s[1], s[2]))
        elseif rules.category_label[cat] and ok[b2] and ok[b3] and b2 ~= settings.rules[cat] and b3 ~= settings.rules[cat]
            and (b2 ~= b3 or b2 == 'none') then
            settings.overflow[cat] = b2 .. '|' .. b3
            journal.write('SET', 'overflow %s -> %s', cat, settings.overflow[cat])
            store.save(settings)
            actions.mark_dirty()
            log(('%s: when %s is full -> %s, then %s.'):format(rules.category_label[cat],
                rules.pretty_bag[settings.rules[cat]] or settings.rules[cat], b2, b3))
        else
            log('Usage: //stw overflow <category> <2nd bag> [3rd bag]   or   //stw overflow <category> auto')
            log('  e.g. //stw overflow crystals case satchel. Bags: ' .. table.concat(rules.overflow_choices, ', ') .. ', none')
        end
    elseif cmd == 'rule' then
        local cat, bag = (args[1] or ''):lower(), (args[2] or ''):lower()
        local valid = false
        for _, d in ipairs(rules.destinations) do if d == bag then valid = true end end
        if rules.category_label[cat] and valid then
            settings.rules[cat] = bag
            store.save(settings)
            actions.mark_dirty()
            log(('%s -> %s  (//stw sort to apply now)'):format(rules.category_label[cat], rules.pretty_bag[bag]))
        else
            local cats = {}
            for _, c in ipairs(rules.categories) do cats[#cats + 1] = c.key end
            log('Usage: //stw rule <category> <bag>   e.g. //stw rule crystals satchel')
            log('Categories: ' .. table.concat(cats, ', '))
            log('Bags: ' .. table.concat(rules.destinations, ', '))
        end
    elseif cmd == 'wardrobe' then
        local group, n = (args[1] or ''):lower(), tonumber(args[2])
        if settings.wardrobes[group] ~= nil and n and n >= 0 and n <= 8 then
            settings.wardrobes[group] = n
            store.save(settings)
            actions.mark_dirty()
            log(('%s -> %s  (//stw sort wardrobes to apply now)'):format(group, n == 0 and 'automatic' or ('Wardrobe ' .. n)))
        else
            local g = {}
            for _, x in ipairs(rules.slot_groups) do g[#g + 1] = x.key end
            log('Usage: //stw wardrobe <group> <1-8>   e.g. //stw wardrobe accessories 7  (0 = automatic)')
            log('Groups: ' .. table.concat(g, ', '))
        end
    elseif cmd == 'auto' then
        local key = (args[1] or ''):lower()
        if settings.auto[key] ~= nil then
            if args[2] then
                settings.auto[key] = (args[2]:lower() == 'on')
                store.save(settings)
                log(('Auto %s: %s'):format(key, settings.auto[key] and 'on' or 'off'))
            else
                actions.toggle(key)
            end
        else
            log('Usage: //stw auto sort|wardrobes|drop|dropbags|lotpass|stack [on|off]')
        end
    elseif cmd == 'porter' then
        local sub = (args[1] or 'list'):lower()
        if sub == 'store' then
            actions.porter_store()
        elseif sub == 'prep' then
            actions.porter_prep()
        elseif sub == 'buy' then
            guard.call('Porter', porter.buy_command, args)
        elseif sub == 'slips' or sub == 'slip' then
            guard.call('Porter', porter.slips_command)
        else
            local list = porter.candidates()
            if #list == 0 then log('Porter: nothing storable outside your wardrobes.') end
            if #list > 0 then log('Stand next to a Porter Moogle and type //stw porter store.') end
            for _, c in ipairs(list) do
                log(('  %s %s (slip %02d, %s)'):format(c.excluded and '[skip]' or '[store]', c.name, c.slip_no or 0,
                    rules.pretty_bag[rules.bag_names[c.bag]]))
            end
        end
    elseif cmd == 'stack' then
        actions.stack()
    elseif cmd == 'verbose' then
        settings.verbose = not settings.verbose
        store.save(settings)
        log('Verbose: ' .. (settings.verbose and 'on' or 'off') .. '  (//stw verbose toggles)')
    elseif cmd == 'delay' and tonumber(args[1]) then
        settings.delay = math.max(0.3, tonumber(args[1]))
        store.save(settings)
        log('Delay between moves: ' .. settings.delay .. 's')
    else
        for _, h in ipairs(help) do windower.add_to_chat(207, h) end
        windower.add_to_chat(207, 'The same list is on the Help tab of the window (//stw); click a blue command to run it.')
    end
    gui.refresh(true)
end)
