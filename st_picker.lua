--[[
Steward drop picker: a large clickable list of your items, grouped by category and sorted A-Z.
Click an item to add it to the Drop list (green). Click a green item to take it off.

Adding an item drops the copies you're holding right away (like Treasury), so gear, Rare/Ex
items and Keep-list items need a second click within 5 seconds to confirm.

  //stw picker     or the [Big list] button on the Drop tab

One tab per bag (Inventory, Satchel, Sack, Case, Safe, Safe 2, Storage, Locker) plus All. The Mog Wardrobes
are never shown: wardrobe gear is never dropped. Satchel/Sack/Case items are brought into the inventory
and dropped (st_loot.pull); Mog House bag items only drop once they reach the inventory.
]]

local texts = require('texts')
local linelib = require('st_line')
local store = require('st_store')
local res = require('resources')
local rules = require('st_rules')

local picker = { visible = false, page = 1, tab = 'inventory' }
local S, log, actions

local COLS, CW = 3, 34          -- three columns, 34 characters each
local W = COLS * CW
local ROWS = 26                 -- item lines per column
local ROW_H = 17

local C = {
    title = '230,190,110', head = '230,190,110', dim = '130,135,150', btn = '120,180,255',
    on = '120,210,140', item = '225,228,235', warn = '240,180,90', keep = '150,150,165',
}

local boxes, layout = {}, {}
local confirm = { name = nil, t = 0 }

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
local function fit(s, n)
    if #s > n then return s:sub(1, n - 1) .. '~' end
    return s .. string.rep(' ', n - #s)
end

local function line() return linelib.line(W) end
local hover = linelib.tracker()     -- highlights the item under the mouse

local function copy(t)
    if type(t) ~= 'table' then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = copy(v) end
    return out
end

local box_settings = {
    pos = { x = 0, y = 0 },
    bg = { alpha = 230, red = 16, green = 18, blue = 24, visible = true },
    flags = { draggable = false },
    padding = 1,
    text = { font = 'Consolas', size = 10, alpha = 255, red = 225, green = 228, blue = 235, stroke = { width = 0, alpha = 0 } },
}

local function total_lines() return ROWS + 4 end

-- Tabs: every bag except the wardrobes (wardrobe gear is never dropped) and the temporary bag.
local TABS = {
    { key = 'all', label = 'All' }, { key = 'inventory', label = 'Inventory' }, { key = 'satchel', label = 'Satchel' },
    { key = 'sack', label = 'Sack' }, { key = 'case', label = 'Case' }, { key = 'safe', label = 'Safe' },
    { key = 'safe2', label = 'Safe 2' }, { key = 'storage', label = 'Storage' }, { key = 'locker', label = 'Locker' },
}
picker.tabs = TABS

local function in_mog_house()
    local info = windower.ffxi.get_info()
    return info and info.mog_house == true
end

-- Can this bag be read right now? (Mog House bags only at home.)
local function readable(items, bag)
    local id = rules.bag_ids[bag]
    if rules.mog_house_only[id] and not in_mog_house() then return false end
    local b = items[bag]
    return type(b) == 'table' and b.enabled ~= false
end

local function place()
    for i, b in ipairs(boxes) do b:pos(S.gui.px, S.gui.py + (i - 1) * ROW_H) end
end

------------------------------------------------------------------------
-- The item list
------------------------------------------------------------------------
local function is_rare_ex(item)
    local f = item and item.flags
    if type(f) ~= 'table' then return false end
    return f.Rare == true or f.Exclusive == true
        or (type(f.contains) == 'function' and (f:contains('Rare') or f:contains('Exclusive')))
end

-- Worth a second click: currencies/seals/crests, names Advice protects (upgrade materials),
-- things an NPC won't buy (usually Auction House goods), and big stacks.
local function valuable(item, e)
    if e.cat == 'currency' or e.cat == 'quest' then return true end
    if e.count >= 10 then return true end
    local f = item and item.flags
    if type(f) == 'table' and (f['No NPC Sale'] == true or (type(f.contains) == 'function' and f:contains('No NPC Sale'))) then
        return true
    end
    local ok, adv = pcall(require, 'st_advice')
    return ok and type(adv) == 'table' and adv.protected and adv.protected(e.name, item) or false
end

-- Every bag you can read right now, except the wardrobes (the [All] tab; also the window's Drop tab).
function picker.all_bags()
    local items = windower.ffxi.get_items()
    local bags = {}
    if not items then return bags end
    for i = 2, #TABS do if readable(items, TABS[i].key) then bags[#bags + 1] = TABS[i].key end end
    return bags
end

-- The items in these bags, one entry per item { name, count, id, cat, on, keep, careful, nosale },
-- sorted by category, then A-Z. on = already on that list (default the Drop list).
function picker.collect(bags, list)
    local items = windower.ffxi.get_items()
    if not items then return {} end
    local by_id = {}
    for _, bag in ipairs(bags) do
        for _, it in ipairs(items[bag] or {}) do
            if type(it) == 'table' and it.id and it.id ~= 0 and it.id ~= 0xFFFF and (it.status or 0) == 0 then
                local e = by_id[it.id]
                if e then e.count = e.count + (it.count or 1)
                else by_id[it.id] = { id = it.id, count = it.count or 1 } end
            end
        end
    end
    local on = rules.name_set(S.lists[list or 'drop'])
    local keep = rules.name_set(S.lists.keep)
    local order = {}
    for i, c in ipairs(rules.categories) do order[c.key] = i end
    local list = {}
    for id, e in pairs(by_id) do
        local item = res.items[id]
        e.name = rules.item_name(id)
        e.cat = rules.category(id)
        e.on = on[e.name:lower()] == true
        e.keep = keep[e.name:lower()] == true
        e.careful = e.keep or e.cat == 'equipment' or is_rare_ex(item) or valuable(item, e)
        local f = item and item.flags
        e.nosale = type(f) == 'table' and (f['No NPC Sale'] == true or (type(f.contains) == 'function' and f:contains('No NPC Sale'))) or false
        list[#list + 1] = e
    end
    table.sort(list, function(a, b)
        local oa, ob = order[a.cat] or 99, order[b.cat] or 99
        if oa ~= ob then return oa < ob end
        return a.name:lower() < b.name:lower()
    end)
    return list
end

-- Insert category headings ({ header = ... }); never leave a heading alone at the bottom of a
-- column of `rows` lines.
function picker.group(list, rows)
    local out, last = {}, nil
    for _, e in ipairs(list) do
        if e.cat ~= last then
            if #out % rows == rows - 1 then out[#out + 1] = { blank = true } end
            out[#out + 1] = { header = rules.category_label[e.cat] or e.cat }
            last = e.cat
        end
        out[#out + 1] = e
    end
    return out
end

-- Entries: { header = 'Crystals & clusters' } or { name, count, id, cat, on, careful }
-- Also returns the number of different items and a note when the bag can't be read here.
-- Bags behind a tab key ('all', 'inventory', 'satchel', ...), plus a note when it can't be read here.
function picker.bags_for(key)
    local items = windower.ffxi.get_items()
    if not items then return {}, nil end
    if key == 'all' then return picker.all_bags(), nil end
    if readable(items, key) then return { key }, nil end
    local pretty = rules.pretty_bag[key] or key
    return {}, rules.mog_house_only[rules.bag_ids[key]] and not in_mog_house()
        and (' Your %s can only be read in your Mog House.'):format(pretty)
        or (' Your %s is not available on this character.'):format(pretty)
end

function picker.entries()
    local bags, note = picker.bags_for(picker.tab)
    local list = picker.collect(bags)
    return picker.group(list, ROWS), #list, note
end

local function loot_pending(id)
    local ok, l = pcall(require, 'st_loot')
    return ok and type(l) == 'table' and l.pending_left and l.pending_left(id) or nil
end

-- list: 'drop' (default) or 'sell'.
local function click_item(e, list)
    list = list or 'drop'
    if e.on then
        actions.list_edit(list, 'remove', e.name)
        return
    end
    if e.careful and not (confirm.name == e.name and os.clock() - confirm.t < 5) then
        confirm.name, confirm.t = e.name, os.clock()
        local why = e.keep and 'it is on your Keep list' or (e.cat == 'equipment' and 'it is gear')
            or (is_rare_ex(res.items[e.id]) and 'it is Rare/Ex') or (e.count >= 10 and ('you hold ' .. e.count))
            or 'it may be valuable'
        local what = list == 'sell' and 'adding it sells the ones in your inventory at the next NPC shop'
            or 'adding it drops the ones you hold now'
        log(('%s: %s, and %s. Click it again within 5 seconds to confirm (or //stw %s add %s).'):format(e.name, why, what, list, e.name))
        return
    end
    confirm.name = nil
    actions.list_edit(list, 'add', e.name)
end
picker.click_item = click_item      -- the window's Drop and Sell tabs use the same second-click rule

-- Waiting for its second click?
function picker.confirming(name) return confirm.name == name and os.clock() - confirm.t < 5 end

------------------------------------------------------------------------
-- Drawing
------------------------------------------------------------------------
function picker.refresh()
    if not picker.visible or #boxes == 0 then return end
    local entries, n_items, note = picker.entries()
    local per_page = COLS * ROWS
    local pages = math.max(1, math.ceil(#entries / per_page))
    picker.page = math.max(1, math.min(picker.page, pages))
    local first = (picker.page - 1) * per_page

    layout = {}
    layout[1] = line():add(' DROP LIST PICKER', C.title)
        :add('  click an item to add it to the Drop list, click a green one to remove it', C.dim)
        :col(W - 8):add('[Close]', C.btn, function() picker.hide() end)
    layout[2] = line():add(' Bag: ', C.dim)
    for _, tb in ipairs(TABS) do
        local key = tb.key
        layout[2]:add('[' .. tb.label .. ']', picker.tab == key and C.on or C.btn,
            function() picker.tab = key picker.page = 1 end):add(' ')
    end
    layout[3] = line():add(' '):add('green', C.on):add('=on Drop list  ', C.dim):add('orange', C.warn)
        :add('=click twice  [9]=click to cancel', C.dim)
    if picker.tab == 'satchel' or picker.tab == 'sack' or picker.tab == 'case' then
        layout[3]:add('   Brought into inventory, then dropped.', C.warn)
    elseif picker.tab ~= 'inventory' then
        layout[3]:add('   Drops once moved to inventory.', C.warn)
    end

    for r = 1, ROWS do
        local l = line()
        for c = 1, COLS do
            l:col((c - 1) * CW)
            local e = entries[first + (c - 1) * ROWS + r]
            if e and e.header then
                l:add(' ' .. fit(e.header:upper(), CW - 2), C.head)
            elseif e and e.name then
                local label = fit(('%s%s'):format(e.name, e.count > 1 and (' x' .. e.count) or ''), CW - 6)
                local pending = confirm.name == e.name and os.clock() - confirm.t < 5
                local left = e.on and loot_pending(e.id)
                local mark = left and ('[%d] '):format(math.min(left, 9)) or (e.on and '[x] ' or (pending and '[?] ' or '[ ] '))
                local color = e.on and C.on or (e.careful and C.warn or C.item)
                local fn = function() click_item(e) end
                l:add(' '):add(mark, color, fn):add(label, color, fn)
            end
        end
        layout[3 + r] = l
    end
    if note and #entries == 0 then layout[4] = line():add(note, C.warn) end
    layout[ROWS + 4] = line():add(' ')
        :add('[< Prev]', C.btn, function() picker.page = picker.page - 1 end)
        :add(('  page %d/%d  '):format(picker.page, pages), C.dim)
        :add('[Next >]', C.btn, function() picker.page = picker.page + 1 end)
        :add(('    %d different items    Drop list: %d    Auto-drop is %s'):format(n_items,
            #rules.split(S.lists.drop), S.auto.drop and 'ON' or 'OFF'), C.dim)

    for i, b in ipairs(boxes) do
        local l = layout[i]
        if l then l:col(W) end
        b:text(l and l.str or string.rep(' ', W))
        b:show()
    end
    hover:apply(layout, boxes)
end

function picker.show()
    if #boxes == 0 then
        for i = 1, total_lines() do
            boxes[i] = texts.new('', copy(box_settings))
        end
        place()
    end
    picker.visible = true
    picker.refresh()
end

function picker.hide()
    picker.visible = false
    for _, b in ipairs(boxes) do b:hide() end
end

function picker.toggle() if picker.visible then picker.hide() else picker.show() end end

function picker.destroy()
    for _, b in ipairs(boxes) do b:destroy() end
    boxes, picker.visible = {}, false
end

------------------------------------------------------------------------
-- Mouse: click items, drag by the title line, wheel to change page
------------------------------------------------------------------------
local drag

local function hit(x, y)
    for i, b in ipairs(boxes) do
        if b:visible() and b:hover(x, y) then
            local bx = b:pos()
            local w = b:extents()
            local col = (w and w > 0) and math.floor((x - bx) / (w / W)) or -1
            return i, layout[i], col
        end
    end
end

function picker.mouse(mtype, x, y, delta, blocked)
    if blocked or not picker.visible or #boxes == 0 then return false end
    if mtype == 0 then
        if drag then
            S.gui.px, S.gui.py = x - drag.dx, y - drag.dy
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
                if not ok then log('Picker error: ' .. tostring(err)) end
                picker.refresh()
                return true
            end
        end
        if i == 1 then drag = { dx = x - S.gui.px, dy = y - S.gui.py } end
        return true
    elseif mtype == 2 then
        if drag then drag = nil store.save(S) return true end
        return hit(x, y) ~= nil
    elseif mtype == 10 then
        if hit(x, y) then
            picker.page = picker.page + (delta > 0 and -1 or 1)
            picker.refresh()
            return true
        end
    end
    return false
end

function picker.init(settings, logger, acts)
    S, log, actions = settings, logger, acts
end

return picker
