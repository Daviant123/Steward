--[[
Steward activity log: one file per character per day in
  Windower\addons\Steward\data\logs\<Name>_<YYYY-MM-DD>.log

Every move, skip, sort start/finish (with bag counts), error, pause, porter step and
drop/lot/pass is written here, so real-game behaviour can be reviewed and tuned.
Turn off with //stw log off.
]]

local journal = { enabled = true }

local dir_ready = false
local function path()
    local p = windower.ffxi.get_player()
    local name = p and p.name or 'unknown'
    local base = windower.addon_path:gsub('[/\\]$', '') .. '/'
    local dir = base .. 'data/logs/'
    if not dir_ready then
        if windower.dir_exists and not windower.dir_exists(base .. 'data') then
            windower.create_dir(base .. 'data')
        end
        if windower.dir_exists and not windower.dir_exists(dir) then windower.create_dir(dir) end
        dir_ready = true
    end
    return dir .. name .. '_' .. os.date('%Y-%m-%d') .. '.log'
end

function journal.file() return path() end

-- journal.write('MOVE', 'Fire Crystal x12 inventory -> sack (Mog Sack)')
function journal.write(tag, msg, ...)
    if not journal.enabled then return end
    if select('#', ...) > 0 then msg = msg:format(...) end
    local ok = pcall(function()
        local f = io.open(path(), 'a')
        if not f then return end
        f:write(('%s [%-6s] %s\n'):format(os.date('%H:%M:%S'), tag, tostring(msg)))
        f:close()
    end)
    return ok
end

return journal
