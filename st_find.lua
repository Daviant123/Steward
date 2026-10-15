--[[
Steward find: search every bag of every character you've loaded Steward on.

  //stw find <text>          e.g. //stw find nyame   //stw find *crest   //stw find 1126
  //stw find                 which characters are saved, and when
  //stw find forget <Name>   remove a character's saved list

Each character's bags (inventory, Mog House bags, Satchel/Sack/Case, all wardrobes and
what's stored on Porter slips) are saved to data/chars/<Name>.lua whenever they change
(at most every 30 s) and when you log out or unload. Read only: nothing is moved.

Ideas from findAll (Windower; Ashita port by Thorny) and Syndicator / BagSync for WoW.
]]

local res = require('resources')
local rules = require('st_rules')
local journal = require('st_journal')
local slips_ok, slips = pcall(require, 'slips')

local find = { dirty = true, last_save = -1000, interval = 30 }
local S, log, sorter

local BAG_ORDER = { 'inventory', 'satchel', 'sack', 'case', 'safe', 'safe2', 'storage', 'locker',
    'wardrobe', 'wardrobe2', 'wardrobe3', 'wardrobe4', 'wardrobe5', 'wardrobe6', 'wardrobe7', 'wardrobe8' }

local function dir()
    local base = windower.addon_path:gsub('[/\\]$', '') .. '/'
    if windower.dir_exists and not windower.dir_exists(base .. 'data') then windower.create_dir(base .. 'data') end
    if windower.dir_exists and not windower.dir_exists(base .. 'data/chars') then windower.create_dir(base .. 'data/chars') end
    return base .. 'data/chars/'
end

local function load_char(file)
    local fn = loadfile(file)
    if not fn then return nil end
    local ok, t = pcall(fn)
    if ok and type(t) == 'table' and type(t.bags) == 'table' then return t end
    return nil
end

local function serialize(t)
    local out = { 'return {', ('  name = %q,'):format(t.name), ('  time = %d,'):format(t.time), '  bags = {' }
    for _, b in ipairs(BAG_ORDER) do
        local items = t.bags[b]
        if items then
            local ids = {}
            for id in pairs(items) do ids[#ids + 1] = id end
            table.sort(ids)
            local parts = {}
            for _, id in ipairs(ids) do parts[#parts + 1] = ('[%d]=%d'):format(id, items[id]) end
            out[#out + 1] = ('    %s = {%s},'):format(b, table.concat(parts, ','))
        end
    end
    if t.slips then
        local sids = {}
        for sid in pairs(t.slips) do sids[#sids + 1] = sid end
        table.sort(sids)
        local parts = {}
        for _, sid in ipairs(sids) do parts[#parts + 1] = ('[%d]={%s}'):format(sid, table.concat(t.slips[sid], ',')) end
        out[#out + 1] = ('  }, slips = {%s},'):format(table.concat(parts, ','))
    else
        out[#out + 1] = '  },'
    end
    if t.key_items and #t.key_items > 0 then
        out[#out + 1] = ('  key_items = {%s},'):format(table.concat(t.key_items, ','))
    end
    out[#out + 1] = '}'
    return table.concat(out, '\n') .. '\n'
end

-- Save the current character. Returns true when written.
function find.save(force)
    local p = windower.ffxi.get_player()
    if not p or not p.name then return false end
    local st = sorter.snapshot()
    local inv = st.bags[0]
    if not inv or not inv.enabled or inv.max == 0 then return false end   -- bags not loaded yet
    local file = dir() .. p.name .. '.lua'
    local old = load_char(file) or { bags = {} }
    local t = { name = p.name, time = os.time(), bags = {} }
    local total = 0
    for _, b in ipairs(BAG_ORDER) do
        local bag = st.bags[rules.bag_ids[b]]
        if bag and bag.enabled then
            local items = {}
            for _, it in pairs(bag.items) do
                items[it.id] = (items[it.id] or 0) + (it.count or 1)
                total = total + 1
            end
            t.bags[b] = items
        elseif old.bags[b] then
            t.bags[b] = old.bags[b]          -- not readable right now: keep what we knew
        end
    end
    if total == 0 and not force then return false end   -- right after login the bags can read empty
    if slips_ok and type(slips.get_player_items) == 'function' then
        local ok, list = pcall(slips.get_player_items)
        if ok and type(list) == 'table' then
            t.slips = {}
            for sid, ids in pairs(list) do
                if type(ids) == 'table' and #ids > 0 then
                    local copy = {}
                    for _, id in ipairs(ids) do copy[#copy + 1] = id end
                    t.slips[sid] = copy
                end
            end
        end
    end
    t.slips = t.slips or old.slips
    -- Zeni NM seals and salts (key items), for the Zeni planner on your other characters
    t.key_items = {}
    for _, id in ipairs(windower.ffxi.get_key_items and windower.ffxi.get_key_items() or {}) do
        if id >= 998 and id <= 1018 then t.key_items[#t.key_items + 1] = id end
    end
    table.sort(t.key_items)
    local ok = pcall(function()
        local f = io.open(file, 'w')
        if not f then error('cannot write ' .. file) end
        f:write(serialize(t))
        f:close()
    end)
    if ok then find.dirty, find.last_save = false, os.clock() end
    return ok
end

-- This character's saved bag list (what //stw find knows), or nil.
-- Used by the Porter when Mog House bags can't be read (away from home).
function find.saved_me()
    local p = windower.ffxi.get_player()
    if not p or not p.name then return nil end
    return load_char(dir() .. p.name .. '.lua')
end

function find.mark() find.dirty = true end

-- Called every frame: saves when the bags changed, at most every find.interval seconds.
function find.tick()
    if find.dirty and os.clock() - find.last_save >= find.interval then
        find.last_save = os.clock()      -- also throttles retries when the bags aren't loaded yet
        find.save()
    end
end

local function all_chars()
    local d = dir()
    local list = {}
    local files = windower.get_dir and windower.get_dir(d) or {}
    for _, f in ipairs(files) do
        if f:match('%.lua$') then
            local t = load_char(d .. f)
            if t then list[#list + 1] = t end
        end
    end
    local me = windower.ffxi.get_player()
    me = me and me.name
    table.sort(list, function(a, b)
        if (a.name == me) ~= (b.name == me) then return a.name == me end
        return a.name < b.name
    end)
    return list, me
end

find.all_chars = all_chars

local function ago(t)
    local s = os.time() - (t or 0)
    if s < 120 then return 'just now' end
    if s < 7200 then return ('%d min ago'):format(math.floor(s / 60)) end
    if s < 172800 then return ('%d h ago'):format(math.floor(s / 3600)) end
    return ('%d days ago'):format(math.floor(s / 86400))
end

local function matcher(q)
    q = q:lower()
    local id = tonumber(q)
    if id then return function(item_id) return item_id == id end end
    local pat
    if q:find('*', 1, true) then
        pat = '^' .. q:gsub('[%^%$%(%)%%%.%[%]%+%-%?]', '%%%0'):gsub('%*', '.*') .. '$'
    end
    return function(item_id)
        local item = res.items[item_id]
        if not item then return false end
        for _, n in ipairs({ (item.english or item.en or ''):lower(), (item.english_log or item.enl or ''):lower() }) do
            if n ~= '' then
                if pat then if n:match(pat) then return true end
                elseif n:find(q, 1, true) then return true end
            end
        end
        return false
    end
end

function find.search(q)
    find.save()                                -- current character up to date first
    local chars, me = all_chars()
    if #chars == 0 then log('Nothing saved yet. Bags are saved a few seconds after they change.') return end
    local match = matcher(q)
    local hits, order = {}, {}
    local function add(id, who, where, n)
        if not hits[id] then hits[id] = {} order[#order + 1] = id end
        local h = hits[id]
        h[#h + 1] = ('%s %s x%d'):format(who, where, n)
        h.total = (h.total or 0) + n
    end
    for _, c in ipairs(chars) do
        local who = c.name == me and c.name or (c.name .. '(' .. ago(c.time) .. ')')
        for _, b in ipairs(BAG_ORDER) do
            for id, n in pairs(c.bags[b] or {}) do
                if match(id) then add(id, who, rules.pretty_bag[b] or b, n) end
            end
        end
        for sid, ids in pairs(c.slips or {}) do
            for _, id in ipairs(ids) do
                if match(id) then
                    local num = slips_ok and slips.get_slip_number_by_id and slips.get_slip_number_by_id(sid) or sid
                    add(id, who, ('Slip %02d'):format(tonumber(num) or 0), 1)
                end
            end
        end
    end
    if #order == 0 then log(('Find "%s": not found on %d character%s.'):format(q, #chars, #chars == 1 and '' or 's')) return end
    table.sort(order, function(a, b) return rules.item_name(a) < rules.item_name(b) end)
    log(('Find "%s": %d item%s on %d character%s:'):format(q, #order, #order == 1 and '' or 's', #chars, #chars == 1 and '' or 's'))
    for i = 1, math.min(#order, 15) do
        local id = order[i]
        log(('  %s (%d): %s'):format(rules.item_name(id), hits[id].total, table.concat(hits[id], ', ')))
    end
    if #order > 15 then log(('  ... and %d more; narrow the search.'):format(#order - 15)) end
    journal.write('FIND', '"%s": %d items', q, #order)
end

function find.command(args)
    local sub = (args[1] or ''):lower()
    if sub == '' then
        find.save()
        local chars = all_chars()
        if #chars == 0 then log('No characters saved yet.') return end
        local t = {}
        for _, c in ipairs(chars) do t[#t + 1] = ('%s (%s)'):format(c.name, ago(c.time)) end
        log('Saved characters: ' .. table.concat(t, ', '))
        log('  //stw find <text> searches all of them, e.g. //stw find nyame  or  //stw find *crest')
        return
    end
    if sub == 'forget' and args[2] then
        local name = args[2]:sub(1, 1):upper() .. args[2]:sub(2):lower()
        local file = dir() .. name .. '.lua'
        if load_char(file) and os.remove(file) then log('Forgot ' .. name .. '.') else log('No saved list for ' .. name .. '.') end
        return
    end
    find.search(table.concat(args, ' '))
end

function find.init(settings, logger, sorter_module)
    S, log, sorter = settings, logger, sorter_module
end

return find
