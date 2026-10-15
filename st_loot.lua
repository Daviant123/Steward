--[[
Steward loot: Treasury-style drop / lot / pass lists and auto-stacking.
Uses the same Windower functions Treasury uses (lot_item, pass_item, drop_item).
]]

local res = require('resources')
local store = require('st_store')
local packets = require('packets')
local rules = require('st_rules')
local journal = require('st_journal')

local loot = {}
local settings, log, is_busy

-- Items just added to the Drop list wait a few seconds before the ones you hold are dropped, so a
-- mis-click can be undone (real logs: Riftborn Boulder x62 and S. Kindred Crest x75 were dropped the
-- moment they were clicked, then taken off the list seconds later). id -> time the drop may happen.
loot.pending = {}
loot.now = function() return os.clock() end
local function grace() return tonumber(settings.drop_grace) or 10 end

-- Name (english or log name, lowercase) -> list of item ids. Built on first use, rebuilt once if a
-- name isn't found (so items added to the game data later are still recognised).
local ids_by_name_t, built_at = nil, -100
local function build()
    ids_by_name_t = {}
    for id, item in pairs(res.items) do
        for _, n in ipairs({ item.english or item.name, item.english_log or item.name_log }) do
            if n then
                n = n:lower()
                ids_by_name_t[n] = ids_by_name_t[n] or {}
                table.insert(ids_by_name_t[n], id)
            end
        end
    end
    built_at = os.clock()
end
local ids_by_name = setmetatable({}, { __index = function(_, k)
    if not ids_by_name_t then build() end
    local v = ids_by_name_t[k]
    if v == nil and os.clock() - built_at > 5 then build() v = ids_by_name_t[k] end
    return v
end })

function loot.known_name(name) return ids_by_name[(name or ''):lower()] ~= nil end

-- First item id for a name (nil if unknown).
function loot.id_of(name)
    local ids = ids_by_name[(name or ''):lower()]
    return ids and ids[1] or nil
end

-- Proper display name for whatever the user typed.
function loot.canonical(name)
    local ids = ids_by_name[(name or ''):lower()]
    return ids and rules.item_name(ids[1]) or nil
end

local function id_set(list_string)
    local set = {}
    for _, n in ipairs(rules.split(list_string)) do
        for _, id in ipairs(ids_by_name[n:lower()] or {}) do set[id] = true end
    end
    return set
end

local cache = {}
function loot.refresh()
    cache.drop = id_set(settings.lists.drop)
    cache.lot = id_set(settings.lists.lot)
    cache.pass = id_set(settings.lists.pass)
end

local function inventory_free()
    local info = windower.ffxi.get_bag_info(0)
    return info and (info.max - info.count) or 0
end

-- Treasure pool item: lot or pass it.
function loot.check_pool(index, item_id)
    if not settings.auto.lotpass then return end
    if cache.lot[item_id] then
        if inventory_free() > 1 then
            windower.ffxi.lot_item(index)
            journal.write('LOT', '%s (pool slot %d)', rules.item_name(item_id), index)
            if settings.verbose then log('Lotting ' .. rules.item_name(item_id)) end
        end
    elseif cache.pass[item_id] or cache.drop[item_id] then
        windower.ffxi.pass_item(index)
        journal.write('PASS', '%s (pool slot %d)', rules.item_name(item_id), index)
        if settings.verbose then log('Passing ' .. rules.item_name(item_id)) end
    end
end

function loot.check_inventory_item(index, item_id, count, status)
    if settings.auto.drop and cache.drop[item_id] and (status or 0) == 0 then
        local t = loot.pending[item_id]
        if t and loot.now() < t then return false end      -- still in its cancel window
        windower.ffxi.drop_item(index, count)
        journal.write('DROP', '%s x%d (inventory slot %d)', rules.item_name(item_id), count or 1, index)
        log(('Dropped %s x%d  (//stw drop remove %s to stop)'):format(rules.item_name(item_id), count or 1, rules.item_name(item_id)))
        return true
    end
    return false
end

------------------------------------------------------------------------
-- Drop-list items in the Satchel, Sack or Case are brought into the inventory one at a time, where
-- they drop like any other. Never the wardrobes or Mog House bags, never Keep-list items, never during
-- a cancel window. It happens when an item's cancel window ends (just that item), or every 30 s while
-- automatic sorting is on (//stw start). Not on load. //stw auto dropbags off turns it off.
------------------------------------------------------------------------
loot.pull_bags = { 'satchel', 'sack', 'case' }
loot.pulling = false
loot.armed = function() return false end        -- set by Steward.lua: automatic sorting on?
loot.allowed = function() return true end       -- set by Steward.lua: not paused by the safety guard
local last_pull, last_full = 0, -1000

-- Next Drop-list item to bring in: bag name, slot, item. only = set of ids, or nil for any.
local function next_pull(only)
    local items = windower.ffxi.get_items()
    if not items then return nil end
    local keep = rules.name_set(settings.lists.keep)
    for _, bag in ipairs(loot.pull_bags) do
        local b = items[bag]
        if type(b) == 'table' and b.enabled ~= false then
            for index, it in ipairs(b) do
                if type(it) == 'table' and it.id and it.id ~= 0 and (it.status or 0) == 0 and cache.drop[it.id]
                    and (not only or only[it.id]) and not loot.pending_left(it.id)
                    and not keep[rules.item_name(it.id):lower()] then
                    return bag, index, it
                end
            end
        end
    end
end

function loot.pull(only)
    if loot.pulling or not settings.auto.drop or not settings.auto.dropbags or not loot.allowed() then return end
    if is_busy and is_busy() then return end
    if not next_pull(only) then return end
    loot.pulling = true
    coroutine.schedule(function()
        for _ = 1, 80 do
            if not settings.auto.drop or not settings.auto.dropbags or not loot.allowed() or (is_busy and is_busy()) then break end
            if inventory_free() < 2 then
                if loot.now() - last_full > 300 then
                    last_full = loot.now()
                    journal.write('DROP', 'not bringing Drop-list items in from other bags: inventory full')
                end
                break
            end
            local bag, index, it = next_pull(only)
            if not bag then break end
            journal.write('DROP', 'bring in %s x%d from %s[%d] to drop it', rules.item_name(it.id), it.count or 1, bag, index)
            windower.ffxi.get_item(rules.bag_ids[bag], index, it.count or 1)
            coroutine.sleep(math.max(1, tonumber(settings.delay) or 0.6))
        end
        loot.pulling = false
        loot.force_check()       -- in case an inventory update was missed
    end, 0)
end

-- Called every second: when a cancel window ends, drop what's still on the list.
function loot.tick()
    local due = {}
    for id, t in pairs(loot.pending) do
        if loot.now() >= t then loot.pending[id] = nil due[id] = true end
    end
    if next(due) then
        loot.force_check()
        loot.pull(due)
    elseif loot.armed() and loot.now() - last_pull >= 30 then
        last_pull = loot.now()
        loot.pull()
    end
end

-- Seconds left before an item's held copies drop (nil if none pending).
function loot.pending_left(item_id)
    local t = loot.pending[item_id]
    if t and loot.now() < t then return math.ceil(t - loot.now()) end
    return nil
end

-- Look over the pool and inventory now (on load and after list changes).
function loot.force_check()
    local items = windower.ffxi.get_items()
    if not items then return end
    for index, item in pairs(items.treasure or {}) do
        if type(item) == 'table' and item.item_id then loot.check_pool(index, item.item_id) end
    end
    for index, item in ipairs(items.inventory or {}) do
        if type(item) == 'table' and item.id and item.id ~= 0 then
            loot.check_inventory_item(index, item.id, item.count, item.status)
        end
    end
end

-- Merge split stacks in the inventory (the game's own "sort" request, as Treasury does).
local last_stack = 0
function loot.stack()
    if not settings.auto.stack or (is_busy and is_busy()) then return end
    if os.clock() - last_stack < 2 then return end
    last_stack = os.clock()
    packets.inject(packets.new('outgoing', 0x03A))
    journal.write('STACK', 'inventory stack request')
end

-- Add/remove a name on a list. Returns a message.
function loot.edit(list, action, name)
    local canonical = loot.canonical(name)
    if action == 'add' and not canonical then return ('No item called "%s". Check the spelling: //stw %s add <exact item name>'):format(name, list) end
    canonical = canonical or name
    local entries = rules.split(settings.lists[list])
    local out, found = {}, false
    for _, n in ipairs(entries) do
        if n:lower() == canonical:lower() then found = true else out[#out + 1] = n end
    end
    if list == 'drop' then
        for _, id in ipairs(ids_by_name[canonical:lower()] or {}) do
            loot.pending[id] = (action == 'add') and (loot.now() + grace()) or nil
        end
    end
    if action == 'add' then
        out[#out + 1] = canonical
        -- An item can't be on both the lot and pass/drop lists.
        if list == 'lot' then
            for _, other in ipairs({ 'pass', 'drop' }) do loot.edit_quiet(other, 'remove', canonical) end
        elseif list == 'pass' or list == 'drop' then
            loot.edit_quiet('lot', 'remove', canonical)
        end
    end
    table.sort(out)
    settings.lists[list] = rules.join(out)
    store.save(settings)
    loot.refresh()
    if action == 'add' and list == 'drop' and grace() > 0 then
        return ('%s added to the Drop list: the ones you hold now drop in %d seconds. Click it again (or //stw drop remove %s) to cancel.'):format(
            canonical, grace(), canonical)
    end
    if action == 'add' then return ('%s added to %s list. (//stw %s remove %s to undo)'):format(canonical, list, list, canonical) end
    return found and ('%s removed from %s list.'):format(canonical, list) or ('%s was not on the %s list.'):format(canonical, list)
end

function loot.edit_quiet(list, action, name)
    local out = {}
    for _, n in ipairs(rules.split(settings.lists[list])) do
        if n:lower() ~= name:lower() then out[#out + 1] = n end
    end
    if action == 'add' then out[#out + 1] = name end
    settings.lists[list] = rules.join(out)
end

function loot.init(s, logger, busy_fn)
    settings, log, is_busy = s, logger, busy_fn
    loot.refresh()
end

-- Incoming packets: treasure pool (0x0D2) and inventory updates (0x020).
function loot.incoming(id, data)
    if id == 0x0D2 then
        local p = packets.parse('incoming', data)
        if p and p.Item and p.Item ~= 0 then loot.check_pool(p.Index, p.Item) end
    elseif id == 0x020 then
        local p = packets.parse('incoming', data)
        if p and p.Bag == 0 and p.Item and p.Item ~= 0 then
            -- Items passing through the inventory during a sort or porter run are never dropped.
            if is_busy and is_busy() then return end
            if not loot.check_inventory_item(p.Index, p.Item, p.Count, p.Status) then loot.stack() end
        end
    end
end

return loot
