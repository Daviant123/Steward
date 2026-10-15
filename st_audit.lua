--[[
Steward wardrobe audit: compare your GearSwap files with your wardrobes. Read only.

  //stw audit          files for this character (GearSwap/data/<Name>_*.lua and data/<Name>/*.lua)
  //stw audit all      every .lua in GearSwap/data
  //stw audit <JOB>    only <Name>_<JOB>*.lua (e.g. //stw audit blu)

Reports:
  MISSING   gear your GearSwap files name that isn't in any wardrobe (and where it is instead:
            a bag, a Porter slip, or not on this character)
  UNUSED    gear in your wardrobes that none of those files name (room you could free up)
The full list is written to data/audit_<Name>.txt. Nothing is moved: wardrobes stay isolated.

Idea from Wardrobe9 (VAL:MISS / VAL:UNUSED) on FFXIAH.
]]

local res = require('resources')
local rules = require('st_rules')
local journal = require('st_journal')
local slips_ok, slips = pcall(require, 'slips')

local audit = {}
local S, log, sorter

local name_index        -- lower-case english / english_log name -> item id (gear only)
local function index()
    if name_index then return name_index end
    name_index = {}
    for id, item in pairs(res.items) do
        if type(item) == 'table' and (item.type == 4 or item.type == 5) then
            for _, n in ipairs({ item.english or item.en, item.english_log or item.enl }) do
                if type(n) == 'string' and n ~= '' then
                    local k = n:lower()
                    if not name_index[k] then name_index[k] = id end
                end
            end
        end
    end
    return name_index
end

-- Every string literal in Lua source, skipping comments (so commented-out gear doesn't count).
function audit.strings(src)
    local out, i, n = {}, 1, #src
    while i <= n do
        local c = src:sub(i, i)
        if c == '-' and src:sub(i + 1, i + 1) == '-' then
            local eq = src:match('^%[(=*)%[', i + 2)
            if eq then
                local close = src:find(']' .. eq .. ']', i + 4 + #eq, true)
                i = close and (close + #eq + 2) or (n + 1)
            else
                local nl = src:find('\n', i, true)
                i = nl and (nl + 1) or (n + 1)
            end
        elseif c == '"' or c == "'" then
            local j, buf = i + 1, {}
            while j <= n do
                local d = src:sub(j, j)
                if d == '\\' then buf[#buf + 1] = src:sub(j + 1, j + 1) j = j + 2
                elseif d == c or d == '\n' then break
                else buf[#buf + 1] = d j = j + 1 end
            end
            out[#out + 1] = table.concat(buf)
            i = j + 1
        elseif c == '[' and src:match('^%[=*%[', i) then
            local eq = src:match('^%[(=*)%[', i)
            local close = src:find(']' .. eq .. ']', i + 2 + #eq, true)
            out[#out + 1] = src:sub(i + 2 + #eq, (close or n + 1) - 1)
            i = close and (close + #eq + 2) or (n + 1)
        else
            i = src:find('[%-"\'%[]', i + 1) or (n + 1)      -- jump to the next quote, dash or bracket
        end
    end
    return out
end

-- Gear ids named in one file's source: id -> true
function audit.parse(src)
    local idx = index()
    local found = {}
    for _, s in ipairs(audit.strings(src)) do
        local id = #s < 40 and idx[s:lower()]
        if id then found[id] = true end
    end
    return found
end

local function gs_dir()
    return windower.addon_path:gsub('[/\\]$', ''):gsub('[^/\\]+$', '') .. 'GearSwap/data/'
end

-- Which GearSwap files to read.
function audit.files(mode)
    local p = windower.ffxi.get_player()
    local me = (p and p.name or ''):lower()
    local base = gs_dir()
    local out = {}
    local function add_dir(d, prefix_ok)
        for _, f in ipairs(windower.get_dir and windower.get_dir(d) or {}) do
            local lf = f:lower()
            if lf:match('%.lua$') and prefix_ok(lf) then out[#out + 1] = d .. f end
        end
    end
    mode = (mode or ''):lower()
    if mode == 'all' then
        add_dir(base, function() return true end)
    elseif mode ~= '' then
        add_dir(base, function(lf) return lf:sub(1, #me + #mode + 1) == me .. '_' .. mode end)
        add_dir(base .. (p and p.name or '') .. '/', function(lf) return lf:sub(1, #mode) == mode end)
    else
        add_dir(base, function(lf) return lf:sub(1, #me + 1) == me .. '_' or lf:sub(1, #me + 1) == me .. '-' end)
        add_dir(base .. (p and p.name or '') .. '/', function() return true end)
    end
    table.sort(out)
    return out
end

local function short(path) return (path:gsub('^.*[/\\]', '')) end

function audit.run(mode)
    local files = audit.files(mode)
    if #files == 0 then
        log(('Audit: no GearSwap files found for %s in %s'):format(
            (mode and mode ~= '') and ('"' .. mode .. '"') or 'this character', gs_dir()))
        log('  //stw audit all reads every file there.')
        return
    end
    local named, by_file = {}, {}
    for _, file in ipairs(files) do
        local f = io.open(file, 'r')
        if f then
            local src = f:read('*a')
            f:close()
            for id in pairs(audit.parse(src)) do
                named[id] = true
                by_file[id] = by_file[id] or short(file)
            end
        end
    end

    local st = sorter.snapshot()
    local in_wardrobe, elsewhere = {}, {}
    for id, bag in pairs(st.bags) do
        for _, it in pairs(bag.items) do
            if rules.is_wardrobe[id] then
                in_wardrobe[it.id] = (in_wardrobe[it.id] or 0) + 1
            elseif id ~= 3 then
                elsewhere[it.id] = elsewhere[it.id] or rules.pretty_bag[bag.name]
            end
        end
    end
    if slips_ok and type(slips.get_player_items) == 'function' then
        local ok, list = pcall(slips.get_player_items)
        if ok and type(list) == 'table' then
            for sid, ids in pairs(list) do
                local num = slips.get_slip_number_by_id and slips.get_slip_number_by_id(sid) or sid
                for _, id in ipairs(type(ids) == 'table' and ids or {}) do
                    elsewhere[id] = elsewhere[id] or ('Porter slip %02d'):format(tonumber(num) or 0)
                end
            end
        end
    end

    local missing, unused = {}, {}
    for id in pairs(named) do
        if not in_wardrobe[id] then
            missing[#missing + 1] = { name = rules.item_name(id), where = elsewhere[id] or 'not on this character', file = by_file[id] }
        end
    end
    for id, n in pairs(in_wardrobe) do
        if not named[id] and rules.is_gear(id) then
            unused[#unused + 1] = { name = rules.item_name(id), n = n }
        end
    end
    local byname = function(a, b) return a.name < b.name end
    table.sort(missing, byname)
    table.sort(unused, byname)
    local reachable = 0
    for _, m in ipairs(missing) do
        if m.where ~= 'not on this character' and not m.where:find('slip') then reachable = reachable + 1 end
    end

    local names = {}
    for _, f in ipairs(files) do names[#names + 1] = short(f) end
    local count = 0
    for _ in pairs(named) do count = count + 1 end
    log(('Audit of %d file%s (%s): %d gear pieces named.'):format(#files, #files == 1 and '' or 's',
        #names > 3 and (names[1] .. ', ' .. names[2] .. ', ...') or table.concat(names, ', '), count))
    if #missing == 0 then
        log('  MISSING: none. Everything your GearSwap files use is in a wardrobe.')
    else
        log(('  MISSING from wardrobes: %d (%d in your bags/slips):'):format(#missing, reachable))
        for i = 1, math.min(#missing, 8) do
            log(('    %s - %s'):format(missing[i].name, missing[i].where))
        end
        if #missing > 8 then log(('    ... and %d more'):format(#missing - 8)) end
    end
    if #unused == 0 then
        log('  UNUSED: none. Every wardrobe piece is named in these files.')
    else
        local t = {}
        for i = 1, math.min(#unused, 6) do t[#t + 1] = unused[i].name end
        log(('  UNUSED in wardrobes (not in these files): %d: %s%s'):format(#unused, table.concat(t, ', '),
            #unused > 6 and ', ...' or ''))
        if mode ~= 'all' then log('  (other jobs may use them: //stw audit all checks every file)') end
    end

    local p = windower.ffxi.get_player()
    local report = windower.addon_path:gsub('[/\\]$', '') .. '/data/audit_' .. (p and p.name or 'unknown') .. '.txt'
    pcall(function()
        local f = io.open(report, 'w')
        if not f then return end
        f:write(('Steward wardrobe audit %s\nFiles: %s\n\nMISSING from wardrobes (%d):\n'):format(
            os.date('%Y-%m-%d %H:%M'), table.concat(names, ', '), #missing))
        for _, m in ipairs(missing) do f:write(('  %-32s %-24s (%s)\n'):format(m.name, m.where, m.file)) end
        f:write(('\nUNUSED in wardrobes (%d):\n'):format(#unused))
        for _, u in ipairs(unused) do f:write(('  %s%s\n'):format(u.name, u.n > 1 and (' x' .. u.n) or '')) end
        f:close()
    end)
    log('  Full list: ' .. report:gsub('/', '\\'))
    journal.write('AUDIT', '%d files, %d named, %d missing, %d unused', #files, count, #missing, #unused)
    audit.last = { missing = missing, unused = unused, files = names }
    return audit.last
end

function audit.init(settings, logger, sorter_module)
    S, log, sorter = settings, logger, sorter_module
end

return audit
