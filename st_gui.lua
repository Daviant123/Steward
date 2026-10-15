--[[
Steward in-game window, drawn with Windower text boxes.

Each line of the window is one text box in a fixed-width font. Clickable words are tracked
by column, so a click is matched to the word under the mouse. Drag the title bar to move it.
Mouse wheel scrolls lists.
]]

local texts = require('texts')
local linelib = require('st_line')
local store = require('st_store')
local rules = require('st_rules')

local gui = { tab = 'home', pages = {} }
local S, log, sorter, loot, porter, actions, guard, picker, advice, npc, sell, prices, znm

local W = 78           -- characters per line
local BODY = 16        -- body lines
local ROW_H = 17       -- pixels per line

local C = {
    title = '230,190,110', tab = '170,175,190', tab_on = '255,255,255', dim = '130,135,150',
    on = '120,210,140', off = '220,120,110', btn = '120,180,255', add = '120,210,140', remove = '230,140,120',
    head = '230,190,110', warn = '240,180,90',
}

------------------------------------------------------------------------
-- Line builder
------------------------------------------------------------------------
local function line() return linelib.line(W) end
local hover = linelib.tracker()     -- highlights the clickable word under the mouse

local function fit(s, n)
    if #s > n then return s:sub(1, n - 1) .. '~' end
    return s .. string.rep(' ', n - #s)
end

local function onoff(v) return v and 'ON ' or 'OFF', v and C.on or C.off end

------------------------------------------------------------------------
-- Text boxes
------------------------------------------------------------------------
local boxes = {}
local layout = {}       -- lines currently shown (same order as boxes)
local total_lines = 2 + BODY + 2

local box_settings = {
    pos = { x = 0, y = 0 },
    bg = { alpha = 215, red = 18, green = 20, blue = 26, visible = true },
    flags = { draggable = false, bold = false },
    padding = 1,
    text = { font = 'Consolas', size = 10, alpha = 255, red = 225, green = 228, blue = 235,
             stroke = { width = 0, alpha = 0 } },
}

local function copy(t)
    if type(t) ~= 'table' then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = copy(v) end
    return out
end

local function make_boxes()
    for i = 1, total_lines do
        boxes[i] = texts.new('', copy(box_settings))
        boxes[i]:pos(S.gui.x, S.gui.y + (i - 1) * ROW_H)
    end
end

local function place()
    for i, b in ipairs(boxes) do b:pos(S.gui.x, S.gui.y + (i - 1) * ROW_H) end
end

------------------------------------------------------------------------
-- Tabs
------------------------------------------------------------------------
local tab_list = {
    { 'home', 'Home' }, { 'rules', 'Rules' }, { 'wardrobes', 'Wardrobes' }, { 'keep', 'Keep' },
    { 'drop', 'Drop' }, { 'sell', 'Sell' }, { 'lot', 'Lot' }, { 'pass', 'Pass' }, { 'porter', 'Porter' }, { 'advice', 'Advice' },
    { 'npc', 'NPC' }, { 'znm', 'Zeni' }, { 'help', 'Help' },
}

local function header()
    local p = windower.ffxi.get_player()
    local l = line():add(' STEWARD', C.title):add('  ' .. (p and p.name or ''), C.dim)
    local state = sorter.running and ('  ' .. sorter.status) or (porter.busy and ('  Porter: ' .. porter.status) or '')
    l:add(state, C.on)
    if guard and guard.paused then
        l:col(W - 26):add('PAUSED ', C.off):add('[Resume]', C.on, function() actions.resume() end)
    end
    l:col(W - 7):add('[Hide]', C.btn, function() gui.hide() end)
    return l:finish()
end

local function tabs()
    -- One space between tabs; the open one in [brackets] (12 tabs fit in 78 columns this way).
    local l = line()
    for _, t in ipairs(tab_list) do
        local on = gui.tab == t[1]
        l:add(' ')
        l:add(on and ('[' .. t[2] .. ']') or t[2], on and C.tab_on or C.tab,
              function() gui.tab = t[1] gui.refresh(true) end)
    end
    return l:finish()
end

local function bag_usage(st, name)
    local b = st.bags[rules.bag_ids[name]]
    if not b or not b.enabled then return 'locked' end
    return ('%d/%d'):format(b.used, b.max)
end

------------------------------------------------------------------------
-- Home
------------------------------------------------------------------------
local function home_tab(st)
    local body, foot = {}, line():add(' ')
    local toggles = {
        { 'sort', 'Auto-sort bags (crystals, food, materials...)' },
        { 'wardrobes', 'Auto-sort wardrobes by gear slot' },
        { 'drop', 'Auto-drop items on the Drop list' },
        { 'dropbags', '...also bring them in from Satchel/Sack/Case to drop' },
        { 'lotpass', 'Auto lot / pass from the Lot and Pass lists' },
        { 'stack', 'Auto-stack split stacks' },
    }
    if guard and guard.paused then
        body[#body + 1] = line():add(' PAUSED: ', C.off):add(guard.reason:sub(1, W - 10), C.off):finish()
    else
        body[#body + 1] = line():add(' Automation (click to switch)', C.head):finish()
    end
    local armed = actions.armed
    body[#body + 1] = line():add('  Automatic sorting this session: ')
        :add(armed and 'ON ' or 'OFF', armed and C.on or C.off)
        :add('  ')
        :add(armed and '[Stop]' or '[Start]', armed and C.off or C.on, function()
            if actions.armed then actions.stop() else actions.start() end end)
        :add(armed and '' or '   (//stw start)', C.dim):finish()
    for _, t in ipairs(toggles) do
        local txt, col = onoff(S.auto[t[1]])
        body[#body + 1] = line():add('  '):add('[' .. txt .. ']', col, function() actions.toggle(t[1]) end)
            :add('  ' .. t[2], nil, function() actions.toggle(t[1]) end):finish()
    end
    local goal = tonumber(S.free_goal) or 0
    local free = st.bags[0].free
    body[#body + 1] = line():add('  Keep free in inventory: ', nil)
        :add('[-]', C.btn, function() actions.goal_step(-5) end)
        :add(goal > 0 and (' ' .. goal .. ' slots ') or ' off ', goal > 0 and C.on or C.off)
        :add('[+]', C.btn, function() actions.goal_step(5) end)
        :add(('   now %d free%s'):format(free, (goal > 0 and free < goal) and ' (putting away)' or ''), C.dim):finish()
    body[#body + 1] = line():add(' Bags', C.head)
        :add(st.mog_house and '   (in Mog House: all bags reachable)' or '   (Mog House bags only sort at home)', C.dim):finish()
    local names = { 'inventory', 'satchel', 'sack', 'case', 'safe', 'safe2', 'locker', 'storage' }
    for i = 1, #names, 2 do
        local l = line()
        for k = i, i + 1 do
            local n = names[k]
            l:col((k - i) * 33):add('  ' .. fit(rules.pretty_bag[n], 14)):add(fit(bag_usage(st, n), 9), C.dim)
        end
        body[#body + 1] = l:finish()
    end
    local w = line():add('  Wardrobes ')
    for n, id in ipairs(rules.wardrobes) do
        local b = st.bags[id]
        w:add(b.enabled and (' ' .. n .. ':' .. b.used) or (' ' .. n .. ':-'), C.dim)
    end
    body[#body + 1] = w:finish()

    foot:add('[Sort everything]', C.btn, function() actions.sort({ bags = true, wardrobes = true }) end):add('  ')
        :add('[Wardrobes only]', C.btn, function() actions.sort({ wardrobes = true }) end):add('  ')
        :add('[Stop]', C.off, function() actions.stop() end):add('  ')
        :add('[Stack now]', C.btn, function() actions.stack() end)
    return body, foot
end

------------------------------------------------------------------------
-- Rules (where each kind of item lives)
------------------------------------------------------------------------
local function rules_tab(st)
    local body = { line():add(' Kind of item', C.dim):col(28):add('Kept in', C.dim):col(48):add('2nd when full', C.dim)
        :col(63):add('3rd', C.dim):finish() }
    local short = { satchel = 'Satchel', sack = 'Sack', case = 'Case', safe = 'Safe', safe2 = 'Safe 2',
        locker = 'Locker', storage = 'Storage', none = '-' }
    for _, c in ipairs(rules.categories) do
        local dest = S.rules[c.key] or 'stay'
        local usage = (dest ~= 'stay' and dest ~= 'inventory') and (' ' .. bag_usage(st, dest)) or ''
        local act = function() actions.cycle_rule(c.key) end
        local l = line():add('  ' .. fit(c.label, 26), nil, act)
            :add(fit(rules.pretty_bag[dest] .. usage, 19), C.on, act)
        if dest ~= 'stay' and dest ~= 'inventory' then
            local slots, own = rules.overflow_slots(c.key, dest)
            for n = 1, 2 do
                local b = slots[n]
                l:col(n == 1 and 47 or 62):add('[' .. (short[b] or b) .. ']', own and C.on or C.dim,
                    function() actions.cycle_overflow(c.key, n) end)
            end
            if not own and #rules.auto_overflow(c.key, dest) > 2 then l:add(' +more', C.dim) end
        end
        body[#body + 1] = l:finish()
    end
    body[#body + 1] = line():finish()
    body[#body + 1] = line():add(' Click a bag to change it. Grey 2nd/3rd = automatic. Items already in', C.dim):finish()
    body[#body + 1] = line():add(' one of their bags stay put. Keep-list items stay in your inventory;', C.dim):finish()
    body[#body + 1] = line():add(' wardrobe gear never leaves the wardrobes.', C.dim):finish()
    return body, line():add(' '):add('[Sort bags now]', C.btn, function() actions.sort({ bags = true }) end)
        :add('   '):add('[2nd/3rd back to automatic]', C.btn, function() actions.reset_overflow() end)
end

------------------------------------------------------------------------
-- Wardrobes (by gear slot)
------------------------------------------------------------------------
local function wardrobes_tab(st)
    local body = { line():add(' Each kind of gear has its own wardrobe. Click to change.', C.dim):finish() }
    for _, g in ipairs(rules.slot_groups) do
        local wid = sorter.wardrobe_for_group(st, g.key)
        local n = rules.is_wardrobe[wid]
        local auto = tonumber(S.wardrobes[g.key]) or 0
        local act = function() actions.cycle_wardrobe(g.key) end
        body[#body + 1] = line():add('  ' .. fit(g.label, 31), nil, act):add('-> ', C.dim)
            :add(fit(('Wardrobe %d (%s)%s'):format(n, bag_usage(st, rules.bag_names[wid]), auto == 0 and '*' or ''), 22), C.on, act)
            :add('[change]', C.btn, act):finish()
    end
    body[#body + 1] = line():finish()
    body[#body + 1] = line():add(' * = automatic layout.', C.dim):finish()
    body[#body + 1] = line():add(' Gear only moves between wardrobes and is never given to a', C.dim):finish()
    body[#body + 1] = line():add(' porter. A full wardrobe leaves gear where it is.', C.dim):finish()
    return body, line():add(' '):add('[Sort wardrobes now]', C.btn, function() actions.sort({ wardrobes = true }) end)
end

------------------------------------------------------------------------
-- Keep / Drop / Lot / Pass lists
------------------------------------------------------------------------
local list_help = {
    keep = 'Never moved out of your inventory.',
    drop = 'Dropped when they reach your inventory.',
    sell = 'Sold by SellNPC at the next NPC shop you open.',
    lot = 'Lotted automatically in the treasure pool.',
    pass = 'Passed automatically in the treasure pool.',
}

local function candidates(st, list)
    local on = rules.name_set(S.lists[list])
    local seen, out = {}, {}
    local function add(id)
        local n = rules.item_name(id)
        if not on[n:lower()] and not seen[n] then seen[n] = true out[#out + 1] = n end
    end
    for _, it in pairs(st.bags[0].items) do if it.status == 0 then add(it.id) end end
    if list == 'keep' then
        for _, b in ipairs({ 5, 6, 7 }) do for _, it in pairs(st.bags[b].items) do add(it.id) end end
    end
    if list == 'lot' or list == 'pass' or list == 'drop' then
        local items = windower.ffxi.get_items()
        for _, t in pairs(items and items.treasure or {}) do
            if type(t) == 'table' and t.item_id and t.item_id ~= 0 then add(t.item_id) end
        end
    end
    table.sort(out)
    return out
end

-- Drop and Sell tabs: both columns grouped by category. Right column: the chosen bag, never the
-- wardrobes (wardrobe gear is never dropped or sold), via the Big list's code so valuable items need a
-- second click. The Sell tab leaves out Keep-list items and items NPCs won't buy.
gui.bags = { drop = 'all', sell = 'all' }
local function bag_columns(list, per)
    local order = {}
    for i, c in ipairs(rules.categories) do order[c.key] = i end
    local left = {}
    for _, n in ipairs(rules.split(S.lists[list])) do
        local id = loot.id_of and loot.id_of(n)
        left[#left + 1] = { name = n, cat = rules.category(id or 0), on = true }
    end
    table.sort(left, function(a, b)
        local oa, ob = order[a.cat] or 99, order[b.cat] or 99
        if oa ~= ob then return oa < ob end
        return a.name:lower() < b.name:lower()
    end)
    local bags, note = picker.bags_for(gui.bags[list])
    local right = {}
    local in_wardrobe = (list == 'sell' and sell) and sell.wardrobe_ids() or {}
    for _, e in ipairs(picker.collect(bags, list)) do
        if not e.on and not (list == 'sell' and (e.nosale or e.keep or in_wardrobe[e.id])) then right[#right + 1] = e end
    end
    if note and #right == 0 then
        local pretty = rules.pretty_bag[gui.bags[list]] or gui.bags[list]
        right[1] = { note = note:find('Mog House') and (pretty .. ' - in Mog House only') or (pretty .. ' - not available') }
    end
    return picker.group(left, per), picker.group(right, per)
end

-- Drop/Sell tab bag buttons (the same bags as the Big list's tabs; never the wardrobes).
local function bag_line(list)
    local l = line():add(' ')
    for _, tb in ipairs(picker.tabs) do
        local key = tb.key
        l:add('[' .. tb.label .. ']', gui.bags[list] == key and C.on or C.btn, function()
            gui.bags[list] = key gui.pages[list] = 1 gui.refresh(true) end)
        if key ~= 'locker' then l:add(' ') end
    end
    return l:finish()
end

local function list_tab(st, list)
    local per = BODY - 2
    local entries, cands
    local by_bag = (list == 'drop' or list == 'sell') and picker and picker.collect
    if by_bag then
        entries, cands = bag_columns(list, per)
    else
        entries = rules.split(S.lists[list])
        table.sort(entries)
        cands = candidates(st, list)
    end
    local pages = math.max(1, math.ceil(math.max(#entries, #cands) / per))
    local page = math.min(gui.pages[list] or 1, pages)
    gui.pages[list] = page
    local right_title = 'Your items (click to add)'
    if by_bag then
        for _, tb in ipairs(picker.tabs) do
            if tb.key == gui.bags[list] then
                right_title = (tb.key == 'all' and 'All bags but wardrobes' or tb.label) .. ' (click to add)'
            end
        end
    end
    local body = {
        by_bag and bag_line(list)
            or line():add(' ' .. list:upper() .. ' list: ', C.head):add(list_help[list], C.dim):finish(),
        line():add('  On the list (click to remove)', C.dim):col(34):add(right_title, C.dim):finish(),
    }
    for i = 1, per do
        local k = (page - 1) * per + i
        local l = line():add(' ')
        local e, c = entries[k], cands[k]
        if type(e) == 'table' then
            if e.header then l:add(' ' .. fit(e.header:upper(), 30), C.head)
            elseif e.name then
                local n = e.name
                l:add('- ' .. fit(n, 29), C.remove, function() actions.list_edit(list, 'remove', n) end)
            end
        elseif e then
            l:add('- ' .. fit(e, 29), C.remove, function() actions.list_edit(list, 'remove', e) end)
        end
        l:col(33)
        if type(c) == 'table' then
            if c.note then l:add(' ' .. fit(c.note, 31), C.dim)
            elseif c.header then l:add(' ' .. fit(c.header:upper(), 30), C.head)
            elseif c.name then
                local label = c.name .. (c.count > 1 and (' x' .. c.count) or '')
                local mark = picker.confirming(c.name) and '? ' or '+ '
                l:add(mark .. fit(label, 29), c.careful and C.warn or C.add, function() picker.click_item(c, list) end)
            end
        elseif c then
            l:add('+ ' .. fit(c, 29), C.add, function() actions.list_edit(list, 'add', c) end)
        end
        body[#body + 1] = l:finish()
    end
    local foot = line():add(' ')
        :add('[< Prev]', C.btn, function() gui.pages[list] = math.max(1, page - 1) gui.refresh(true) end)
        :add(('  page %d/%d  '):format(page, pages), C.dim)
        :add('[Next >]', C.btn, function() gui.pages[list] = math.min(pages, page + 1) gui.refresh(true) end)
    if list == 'drop' and picker then
        foot:add('   '):add('[Big list: pick items to drop]', C.on, function() picker.toggle() end)
    elseif list == 'sell' and sell then
        foot:add('   '):add('[Load into SellNPC]', C.on, function() sell.load() end)
    else
        foot:add('   type: //stw ' .. list .. ' add <name>', C.dim)
    end
    gui.scroll = function(dir) gui.pages[list] = math.max(1, math.min(pages, page + dir)) gui.refresh(true) end
    return body, foot
end

------------------------------------------------------------------------
-- Porter
------------------------------------------------------------------------
local porter_cache = { t = -10, list = {} }

local function porter_tab(st)
    if os.clock() - porter_cache.t > 3 then
        porter_cache.list, porter_cache.t = porter.candidates(), os.clock()
    end
    local list = porter_cache.list
    local per = BODY - 3
    local pages = math.max(1, math.ceil(#list / per))
    local page = math.min(gui.pages.porter or 1, pages)
    gui.pages.porter = page
    local inc_txt, inc_col = onoff(S.porter.include_inventory)
    local body = {
        line():add(' Storable gear outside wardrobes. Click to skip/include. Prep at home.', C.dim):finish(),
        line():add('  Porter Moogle nearby: ', C.dim):add(porter.near() and 'yes' or 'no', porter.near() and C.on or C.off)
            :add('    Include inventory gear: ', C.dim):add('[' .. inc_txt .. ']', inc_col, function() actions.toggle_porter_inventory() end):finish(),
        line():finish(),
    }
    if #list == 0 then body[#body + 1] = line():add('  Nothing storable found.', C.dim):finish() end
    for i = 1, per do
        local c = list[(page - 1) * per + i]
        if c then
            local act = function() actions.porter_exclude(c.name) porter_cache.t = -10 end
            local mark = c.excluded and '[ skip ]' or '[store]'
            local where = rules.pretty_bag[rules.bag_names[c.bag]] .. (c.reachable and '' or ' - go home')
            body[#body + 1] = line():add('  '):add(mark, c.excluded and C.dim or C.on, act)
                :add(' ' .. fit(c.name, 30), c.excluded and C.dim or nil, act)
                :add(fit(('slip %02d  %s'):format(c.slip_no or 0, where), 24), C.dim):finish()
        end
    end
    local foot = line():add(' ')
        :add('[Prep inventory]', C.btn, function() actions.porter_prep() end):add(' ')
        :add('[Store now]', C.btn, function() actions.porter_store() end):add('  ')
        :add('[< Prev]', C.btn, function() gui.pages.porter = math.max(1, page - 1) gui.refresh(true) end)
        :add((' %d/%d '):format(page, pages), C.dim)
        :add('[Next >]', C.btn, function() gui.pages.porter = math.min(pages, page + 1) gui.refresh(true) end)
        :add('  ')
        :add('[Refresh]', C.btn, function() porter_cache.t = -10 gui.refresh(true) end)
    gui.scroll = function(dir) gui.pages.porter = math.max(1, math.min(pages, page + dir)) gui.refresh(true) end
    return body, foot
end

------------------------------------------------------------------------
-- Drawing
------------------------------------------------------------------------
------------------------------------------------------------------------
-- Advice: next steps after sorting
------------------------------------------------------------------------
local advice_cache = { t = -10 }
local toss_confirm = { name = nil, t = 0 }

local function advice_tab(st)
    if os.clock() - advice_cache.t > 3 then
        advice_cache.data, advice_cache.t = advice.compute(), os.clock()
    end
    local a = advice_cache.data
    local rows = {}
    local function section(title, list, color, act)
        if #list == 0 then return end
        rows[#rows + 1] = { head = ('%s (%d)'):format(title, #list) }
        for _, e in ipairs(list) do rows[#rows + 1] = { e = e, color = color, act = act } end
    end
    local ah, npc_sell = {}, {}
    for _, e in ipairs(a.sell) do if e.ah then ah[#ah + 1] = e else npc_sell[#npc_sell + 1] = e end end
    section('SELL on the Auction House (ffxiah.com, your server)', ah, C.warn)
    section(#ah > 0 and 'SELL to an NPC (or AH if it says so)' or 'SELL', npc_sell, C.on)
    section('TOSS? Ex, no NPC value - click twice: add to Drop list', a.toss, C.remove, 'toss')
    section('STORE at a Porter Moogle', a.store, C.btn)
    section('DUPLICATES of wardrobe gear (sell or store the extra)', a.dupes, C.dim)
    local per = BODY - 1
    local pages = math.max(1, math.ceil(#rows / per))
    local page = math.min(gui.pages.advice or 1, pages)
    gui.pages.advice = page
    local body = { line():add(' Next steps. Suggestions only: nothing happens until you click.', C.dim):finish() }
    if #rows == 0 then body[#body + 1] = line():add('  All tidy: nothing to sell, toss or store.', C.on):finish() end
    for i = 1, per do
        local r = rows[(page - 1) * per + i]
        if r and r.head then
            body[#body + 1] = line():add(' ' .. r.head, C.head):finish()
        elseif r then
            local e = r.e
            local fn
            if r.act == 'toss' then
                fn = function()
                    if toss_confirm.name == e.name and os.clock() - toss_confirm.t < 5 then
                        toss_confirm.name = nil
                        actions.list_edit('drop', 'add', e.name)
                        advice_cache.t = -10
                    else
                        toss_confirm.name, toss_confirm.t = e.name, os.clock()
                        log(('Click %s again within 5 seconds to add it to the Drop list.'):format(e.name))
                    end
                end
            end
            local label = ('%s%s'):format(e.name, e.count > 1 and (' x' .. e.count) or '')
            body[#body + 1] = line():add('   ' .. fit(label, 26), r.color, fn)
                :add(fit(e.where, 12), C.dim):add(fit(e.why or '', 36), C.dim):finish()
        end
    end
    local held = sorter.hold_until and os.clock() < sorter.hold_until
    local foot = line():add(' ')
        :add('[Gather sell items]', C.btn, function() actions.gather_sell() end):add(' ')
        :add('[Store at Porter]', C.btn, function() actions.porter_store() end):add(' ')
        :add(prices and prices.running and '[Stop prices]' or '[AH prices]', prices and prices.running and C.off or C.btn,
            function() if prices.running then prices.stop = true else actions.prices() end end):add(' ')
        :add('[<]', C.btn, function() gui.pages.advice = math.max(1, page - 1) end)
        :add((' %d/%d '):format(page, pages), C.dim)
        :add('[>]', C.btn, function() gui.pages.advice = math.min(pages, page + 1) end)
    if held then foot:add(' '):add('[Unhold]', C.off, function() actions.unhold() end) end
    gui.scroll = function(dir) gui.pages.advice = math.max(1, math.min(pages, page + dir)) gui.refresh(true) end
    return body, foot
end

------------------------------------------------------------------------
-- Help: every command (click the ones that need nothing typed after them)
------------------------------------------------------------------------
local commands = {
    { 'stw', 'show / hide this window' },
    { 'stw start', 'start automatic sorting (off at load)', true },
    { 'stw sort', 'sort everything now (one pass)', true },
    { 'stw sort bags', 'sort bags only', true },
    { 'stw sort wardrobes', 'sort wardrobes only', true },
    { 'stw stop', 'stop auto-sorting and anything running', true },
    { 'stw resume', 'resume after a safety pause', true },
    { 'stw advice', 'next steps: sell / toss / store', true },
    { 'stw advice ignore add <item>', 'never suggest this item' },
    { 'stw sellprep', 'gather sell items; holds sort 10 min', true },
    { 'stw unhold', 'end a sell / porter-prep hold', true },
    { 'stw picker', 'big clickable list for the Drop list', true },
    { 'stw porter prep', '(at home) gather gear + slips for Porter', true },
    { 'stw porter store', 'store gear at a nearby Porter Moogle', true },
    { 'stw porter list', 'list what the Porter would take', true },
    { 'stw porter slips', 'slips you have / need to buy', true },
    { 'stw porter buy', 'list slips to buy (1,000 gil each)', true },
    { 'stw porter buy confirm', 'buy them at a Porter Moogle' },
    { 'stw npc', 'NPC storage: counts and where each goes', true },
    { 'stw seals', 'Shami: store seals/crests (gathers if away)', true },
    { 'stw crystals', 'Ephemeral Moogle: crystals/clusters', true },
    { 'stw vouchers', 'Copper vouchers (Isakoth etc.)', true },
    { 'stw remstales', "Monisette: Rem's Tale chapters", true },
    { 'stw beastcoins', 'Sagheera: Ancient Beastcoins', true },
    { 'stw salvage', 'Mrohk Sahjuuli: Salvage plans (untested)', true },
    { 'stw soulplates', 'Sanraku: Soul Plates (untested)', true },
    { 'stw gobbiekeys', 'Mystrix & co.: SP Gobbie Keys, 1 per trade', true },
    { 'stw trade', 'trade with the NPC in range (all QuickTrade NPCs)', true },
    { 'stw update', 'check for a newer Steward', true },
    { 'stw update install', 'install the newer Steward', true },
    { 'stw <kind> prep|store', 'force gather / trade for one kind' },
    { 'stw stack', 'stack split items now', true },
    { 'stw audit', 'GearSwap files vs wardrobes (missing/unused)', true },
    { 'stw audit <job>|all', 'audit one job, or every GearSwap file' },
    { 'stw find', 'saved characters (for //stw find <text>)', true },
    { 'stw find <text>', 'search all bags of all your characters' },
    { 'stw merge', 'split stacks across bags (merged on sort)', true },
    { 'stw merge on|off', 'merge split stacks during sorts' },
    { 'stw log', 'where the activity log is', true },
    { 'stw log on|off', 'turn the activity log on/off' },
    { 'stw goal <n>', 'keep n inventory slots free (70)' },
    { 'stw keep add|remove <item>', 'Keep list (stays in inventory)' },
    { 'stw drop add|remove <item>', 'Drop list' },
    { 'stw sell add|remove <item>', 'Sell list (sold by SellNPC at shops)' },
    { 'stw sell load', 'queue the Sell list in SellNPC again' },
    { 'stw prices', 'AH prices from ffxiah.com for Advice', true },
    { 'stw prices server <name>', 'your server for prices (carbuncle)' },
    { 'stw znm [tinnin|sarameya|tyger]', 'Zeni NM pop plan (Zeni tab)' },
    { 'stw lot add|remove <item>', 'Lot list' },
    { 'stw pass add|remove <item>', 'Pass list' },
    { 'stw keep|drop|lot|pass list', 'show a list in chat' },
    { 'stw overflow <cat> <2nd> [3rd]', '2nd/3rd bag when full (auto = default)' },
    { 'stw rule <category> <bag>', 'where a kind of item goes' },
    { 'stw wardrobe <group> <1-8>', 'which wardrobe a gear slot uses' },
    { 'stw auto <part> on|off', 'sort wardrobes drop dropbags lotpass stack' },
    { 'stw verbose', 'show every move in chat', true },
    { 'stw delay <seconds>', 'time between moves (0.6)' },
    { 'stw help', 'print this list in chat', true },
}

local function help_tab(st)
    local per = BODY - 1
    local pages = math.max(1, math.ceil(#commands / per))
    local page = math.min(gui.pages.help or 1, pages)
    gui.pages.help = page
    local body = { line():add(' Commands. Blue ones run when clicked; type the others in chat.', C.dim):finish() }
    for i = 1, per do
        local c = commands[(page - 1) * per + i]
        if c then
            local fn = c[3] and function() windower.send_command(c[1]) end or nil
            body[#body + 1] = line():add('  ' .. fit('//' .. c[1], 32), c[3] and C.btn or C.on, fn)
                :add(fit(c[2], W - 35), C.dim, fn):finish()
        end
    end
    local foot = line():add(' ')
        :add('[< Prev]', C.btn, function() gui.pages.help = math.max(1, page - 1) end)
        :add(('  page %d/%d  '):format(page, pages), C.dim)
        :add('[Next >]', C.btn, function() gui.pages.help = math.min(pages, page + 1) end)
    gui.scroll = function(dir) gui.pages.help = math.max(1, math.min(pages, page + dir)) gui.refresh(true) end
    return body, foot
end

-- The commands for each tab, shown on the line above its buttons.
local tab_hint = {
    home = '//stw start  //stw stop  //stw sort  //stw goal <n>  //stw resume  //stw help',
    npc = '//stw seals  //stw crystals  //stw vouchers ... [prep|store]   //stw npc',
    rules = '//stw rule crystals sack    //stw overflow crystals case satchel',
    wardrobes = '//stw wardrobe <group> <1-8>   //stw sort wardrobes',
    keep = '//stw keep add <item>   //stw keep remove <item>',
    drop = '//stw drop add <item>   //stw drop remove <item>   //stw picker',
    sell = 'Needs SellNPC (//lua load sellnpc). Sells from inventory at any NPC shop.',
    znm = 'Reads your seals, pop items and trophies. Plans only: buys/trades nothing.',
    lot = '//stw lot add <item>   //stw lot remove <item>',
    pass = '//stw pass add <item>   //stw pass remove <item>',
    porter = '//stw porter prep (at home)   //stw porter store   //stw porter list',
    advice = '//stw advice  //stw sellprep  //stw porter prep  //stw porter store',
    help = '//stw help prints this list in chat',
}

------------------------------------------------------------------------
-- NPC storage: one row per kind of item an NPC stores
------------------------------------------------------------------------
local npc_cache = { t = -10 }

local function npc_tab(st)
    if os.clock() - npc_cache.t > 3 then
        npc_cache.counts = {}
        for _, t in ipairs(npc.types) do npc_cache.counts[t.key] = npc.count(t) end
        npc_cache.t = os.clock()
    end
    local body = {
        line():add(' Items NPCs take from you. Away: [Prep] gathers them. At the NPC: [Store].', C.dim):finish(),
        line():add('  ' .. fit('Kind', 22) .. fit('inv/bags/home', 15) .. 'NPC', C.dim):finish(),
    }
    local per = BODY - 4
    local pages = math.max(1, math.ceil(#npc.types / per))
    local page = math.min(gui.pages.npc or 1, pages)
    gui.pages.npc = page
    for i = (page - 1) * per + 1, math.min(#npc.types, page * per) do
        local t = npc.types[i]
        local c = npc_cache.counts[t.key] or { inv = 0, reach = 0, far = 0 }
        local found = npc.find(t)
        local near = found ~= nil
        local any = c.inv + c.reach + c.far > 0
        body[#body + 1] = line():add('  ' .. fit(t.label, 22), any and nil or C.dim)
            :add(fit(('%d/%d/%d'):format(c.inv, c.reach, c.far), 15), C.dim)
            :add(fit((found and found.name or t.npcs[1]) .. (t.untested and '*' or ''), 18), near and C.on or C.dim)
            :add('[Prep]', C.btn, function() npc.command(t.key, 'prep') npc_cache.t = -10 end):add(' ')
            :add('[Store]', near and C.on or C.dim, function() npc.command(t.key, 'store') npc_cache.t = -10 end):finish()
    end
    body[#body + 1] = line():finish()
    body[#body + 1] = line():add(' Green = NPC in range now. * = untested. //stw trade trades with it.', C.dim):finish()
    local foot = line():add(' ')
        :add('[<]', C.btn, function() gui.pages.npc = math.max(1, page - 1) end)
        :add((' %d/%d '):format(page, pages), C.dim)
        :add('[>]', C.btn, function() gui.pages.npc = math.min(pages, page + 1) end)
        :add('  '):add('[Trade with NPC here]', C.on, function() npc.auto() npc_cache.t = -10 end)
        :add('  '):add('[Refresh]', C.btn, function() npc_cache.t = -10 end)
        :add('  '):add('[Stop]', C.off, function() actions.stop() end)
    gui.scroll = function(dir) gui.pages.npc = math.max(1, math.min(pages, page + dir)) gui.refresh(true) end
    return body, foot
end

------------------------------------------------------------------------
-- Zeni NMs: what's left for Tinnin / Sarameya / Tyger and the shortest way there (st_znm)
------------------------------------------------------------------------
local znm_view = { target = 'all', t = -10, lines = {} }

local function znm_tab(st)
    if os.clock() - znm_view.t > 3 then
        local team = znm.team_mode()
        local lines = znm.lines(znm.parse_targets(znm_view.target), team)
        if not team then for _, l in ipairs(znm.others()) do lines[#lines + 1] = l end end
        znm_view.lines, znm_view.t = lines, os.clock()
    end
    local head = line():add(' ')
    for _, k in ipairs({ 'tinnin', 'sarameya', 'tyger', 'all' }) do
        local label = k == 'all' and 'All three' or znm.targets[k].name
        head:add('[' .. label .. ']', znm_view.target == k and C.on or C.btn, function()
            znm_view.target, gui.pages.znm, znm_view.t = k, 1, -10 end):add(' ')
    end
    local team = znm.team_mode()
    head:add(' '):add(team and '[Team]' or '[Solo]', C.on, function()
        znm.command(team and 'solo' or 'team', znm_view.target) znm_view.t = -10 end)
    local cheap = S.znm and S.znm.cheap
    head:add(' '):add(cheap and '[Cheap]' or '[Fast]', C.on, function()
        znm.command(cheap and 'fast' or 'cheap', znm_view.target) znm_view.t = -10 end)
    local lines = znm_view.lines
    local per = BODY - 1
    local pages = math.max(1, math.ceil(#lines / per))
    local page = math.min(gui.pages.znm or 1, pages)
    gui.pages.znm = page
    local body = { head:finish() }
    local in_plan = false
    for i = 1, per do
        local s = lines[(page - 1) * per + i]
        if s then
            if s:match('^Plan:') then in_plan = true end
            local color = s:match('^%d+%. ') and C.head or ((s:match(' has: ') or s:match(' pops it')) and C.dim)
                or (not in_plan and C.on) or nil
            body[#body + 1] = line():add(' ' .. fit(s, W - 2), color):finish()
        end
    end
    local foot = line():add(' ')
        :add('[<]', C.btn, function() gui.pages.znm = math.max(1, page - 1) end)
        :add((' %d/%d '):format(page, pages), C.dim)
        :add('[>]', C.btn, function() gui.pages.znm = math.min(pages, page + 1) end)
        :add('  '):add('[Refresh]', C.btn, function() znm_view.t = -10 end)
        :add('  '):add('[Print to chat]', C.btn, function() znm.command(znm_view.target) end)
    gui.scroll = function(dir) gui.pages.znm = math.max(1, math.min(pages, page + dir)) gui.refresh(true) end
    return body, foot
end

local builders = { znm = znm_tab, home = home_tab, rules = rules_tab, wardrobes = wardrobes_tab, porter = porter_tab, advice = advice_tab, help = help_tab, npc = npc_tab }

local last_draw = 0
function gui.refresh(force)
    if not S.gui.visible or #boxes == 0 then return end
    if not force and os.clock() - last_draw < 1 then return end
    last_draw = os.clock()
    local st = sorter.snapshot()
    gui.scroll = nil
    local body, foot
    if builders[gui.tab] then body, foot = builders[gui.tab](st)
    else body, foot = list_tab(st, gui.tab) end

    layout = { header(), tabs() }
    for i = 1, BODY do layout[#layout + 1] = body[i] or line():finish() end
    layout[#layout + 1] = line():add(' ' .. (tab_hint[gui.tab] or ''), C.dim):finish()
    layout[#layout + 1] = foot:finish()
    for i, b in ipairs(boxes) do
        local l = layout[i]
        b:text(l and l.str or string.rep(' ', W))
        b:show()
    end
    hover:apply(layout, boxes)
end

function gui.show()
    S.gui.visible = true
    store.save(S)
    if #boxes == 0 then make_boxes() end
    gui.refresh(true)
end

function gui.hide()
    S.gui.visible = false
    store.save(S)
    for _, b in ipairs(boxes) do b:hide() end
end

function gui.toggle() if S.gui.visible then gui.hide() else gui.show() end end

function gui.destroy()
    for _, b in ipairs(boxes) do b:destroy() end
    boxes = {}
end

------------------------------------------------------------------------
-- Mouse
------------------------------------------------------------------------
local drag

local function hit(x, y)
    for i, b in ipairs(boxes) do
        if b:visible() and b:hover(x, y) then
            local bx = select(1, b:pos())
            local w = select(1, b:extents())
            local l = layout[i]
            local col = (w and w > 0) and math.floor((x - bx) / (w / W)) or -1
            return i, l, col
        end
    end
    return nil
end

function gui.mouse(mtype, x, y, delta, blocked)
    if blocked or not S.gui.visible or #boxes == 0 then return false end
    if mtype == 0 then
        if drag then
            S.gui.x, S.gui.y = x - drag.dx, y - drag.dy
            place()
            return true
        end
        local i, _, col = hit(x, y)
        hover:move(i, col, layout, boxes)
        return false
    elseif mtype == 1 then
        local i, l, col = hit(x, y)
        if not i then return false end
        for _, seg in ipairs(l and l.segs or {}) do
            if col >= seg[1] and col <= seg[2] then
                local ok, err = pcall(seg[3])
                if not ok then log('GUI error: ' .. tostring(err)) end
                gui.refresh(true)
                return true
            end
        end
        if i == 1 then drag = { dx = x - S.gui.x, dy = y - S.gui.y } end
        return true
    elseif mtype == 2 then
        if drag then drag = nil store.save(S) return true end
        return hit(x, y) ~= nil
    elseif mtype == 10 then
        if hit(x, y) and gui.scroll then gui.scroll(delta > 0 and -1 or 1) return true end
    end
    return false
end

function gui.init(settings, logger, mods)
    S, log = settings, logger
    sorter, loot, porter, actions, guard, picker = mods.sorter, mods.loot, mods.porter, mods.actions, mods.guard, mods.picker
    advice = mods.advice
    npc = mods.npc
    sell = mods.sell
    prices = mods.prices
    znm = mods.znm
    if S.gui.visible then gui.show() end
end

return gui
