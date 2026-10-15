--[[
Steward settings saving that is safe when several characters run Steward at once (multiboxing).

Windower's config library writes the whole settings.xml from what it read when *this* game
loaded the addon, so when CharC saves, CharA's section goes back to how it was when
CharC logged in: CharA's newer drop list, goal or rules are lost. (Seen in the real
settings.xml: CharA's wardrobe "transit" list from 20:17 was still there hours later.)

store.save(settings) first re-reads the file (so every other character's section is current),
puts this character's values back on top, then saves.
]]

local config = require('config')

local store = {}

local function copy(v)
    if type(v) ~= 'table' then return v end
    local t = {}
    for k, x in pairs(v) do
        if type(x) ~= 'function' then t[k] = copy(x) end
    end
    return t
end

-- Put src's values into dst in place (nested tables keep their identity, so modules that hold
-- settings.lists or settings.rules keep seeing the live values).
local function assign(dst, src)
    for k, v in pairs(src) do
        if type(v) == 'table' and type(rawget(dst, k)) == 'table' then
            assign(rawget(dst, k), v)
        else
            rawset(dst, k, v)
        end
    end
end

function store.save(settings)
    if not settings then return end
    local mine = {}
    for k, v in pairs(settings) do
        if type(v) ~= 'function' then mine[k] = copy(v) end
    end
    if type(config.reload) == 'function' then
        pcall(config.reload, settings)                  -- other characters' sections, fresh from disk
        assign(settings, mine)                          -- this character's values win, even if reload failed half-way
    end
    return settings:save()
end

return store
