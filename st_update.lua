--[[
Steward updates from its GitHub page (user request 2026-10-14).

  //stw update            check for a newer version (and say how to get it)
  //stw update install    download the newer version into this addon folder, then //lua r steward
  //stw update off|on     stop / start checking when Steward loads

Where it looks: settings update.repo ("owner/name" on GitHub, branch main). The page holds version.txt
(e.g. 1.2.0), manifest.txt (the files that make up Steward, one per line) and those files.
A check reads two tiny files; Windower's Lua can't fetch in the background, so the game may hitch for a
moment. Installing only ever writes the .lua files and README.md named in manifest.txt, into this
addon's folder; your settings, lists and logs (the data folder) are never touched. Nothing is installed
unless you type //stw update install.
]]

local journal = require('st_journal')

local update = { checked = false, latest = nil }
local S, log

update.get = function(url)                  -- blocking fetch; tests replace this
    local https = require('ssl.https')
    local ltn12 = require('ltn12')
    https.TIMEOUT = 8
    local body = {}
    local ok, code = https.request({ url = url, sink = ltn12.sink.table(body), redirect = false,
        headers = { ['user-agent'] = 'Steward (Windower addon)' } })
    if not ok or code ~= 200 then return nil, tostring(code) end
    return table.concat(body)
end

local function raw(file)
    return ('https://raw.githubusercontent.com/%s/%s/%s'):format(S.update.repo, S.update.branch or 'main', file)
end

-- '1.10.2' > '1.9.9'
function update.newer(a, b)
    local function parts(v) local t = {} for n in tostring(v or ''):gmatch('%d+') do t[#t + 1] = tonumber(n) end return t end
    local x, y = parts(a), parts(b)
    for i = 1, math.max(#x, #y) do
        local p, q = x[i] or 0, y[i] or 0
        if p ~= q then return p > q end
    end
    return false
end

local function configured()
    return S.update and type(S.update.repo) == 'string' and S.update.repo:match('^[%w%-_.]+/[%w%-_.]+$') ~= nil
end

-- Returns the newer version string, or nil (and says so unless quiet).
function update.check(quiet)
    if not configured() then
        if not quiet then log('Updates: no GitHub page set yet (//stw update repo <owner>/<name>).') end
        return nil
    end
    local ok, text = pcall(update.get, raw('version.txt'))
    local latest = ok and text and text:match('(%d+%.%d+[%.%d]*)')
    update.checked = true
    if not latest then
        if not quiet then log('Updates: could not reach the GitHub page; try again later.') end
        return nil
    end
    update.latest = latest
    if update.newer(latest, _addon.version) then
        log(('Steward %s is available (you have %s). //stw update install gets it.'):format(latest, _addon.version))
        journal.write('UPDATE', 'version %s available (have %s)', latest, _addon.version)
        return latest
    end
    if not quiet then log(('Steward is up to date (%s).'):format(_addon.version)) end
    return nil
end

-- Download every file in manifest.txt, then write them all (so a failed download changes nothing).
function update.install()
    local latest = update.check(true)
    if not latest then
        if configured() and update.latest then log(('Steward is up to date (%s).'):format(_addon.version)) end
        if not configured() then log('Updates: no GitHub page set yet (//stw update repo <owner>/<name>).') end
        return false
    end
    local ok, manifest = pcall(update.get, raw('manifest.txt'))
    if not ok or not manifest then log('Updates: could not read the file list; nothing changed.') return false end
    local files = {}
    for line in manifest:gmatch('[^\r\n]+') do
        local name = line:gsub('^%s+', ''):gsub('%s+$', '')
        if name ~= '' then
            -- only plain Steward files in this folder: no paths, never the data folder
            if not (name:match('^[%w_]+%.lua$') or name == 'README.md') then
                log(('Updates: unexpected file "%s" in the list; nothing changed.'):format(name))
                return false
            end
            files[#files + 1] = name
        end
    end
    if #files == 0 or not (function() for _, f in ipairs(files) do if f == 'Steward.lua' then return true end end end)() then
        log('Updates: the file list looks wrong; nothing changed.') return false
    end
    local got = {}
    for _, name in ipairs(files) do
        local ok2, text = pcall(update.get, raw(name))
        if not ok2 or not text or #text == 0 then log(('Updates: could not download %s; nothing changed.'):format(name)) return false end
        got[name] = text
    end
    local base = windower.addon_path:gsub('[/\\]$', '') .. '/'
    for _, name in ipairs(files) do
        local f = io.open(base .. name, 'wb')
        if not f then log(('Updates: could not write %s (stopped part-way; //stw update install again).'):format(name)) return false end
        f:write(got[name])
        f:close()
    end
    journal.write('UPDATE', 'installed %s (%d files)', latest, #files)
    log(('Steward %s installed (%d files). Reload it now: //lua r steward'):format(latest, #files))
    return true
end

function update.command(args)
    local sub = (args[1] or ''):lower()
    if sub == 'install' then update.install()
    elseif sub == 'off' or sub == 'on' then
        S.update.check = (sub == 'on')
        require('st_store').save(S)
        log(('Updates: checking when Steward loads is %s.'):format(sub:upper()))
    elseif sub == 'repo' and args[2] then
        S.update.repo = args[2]
        require('st_store').save(S)
        log(('Updates: GitHub page set to %s.'):format(args[2]))
        update.check(false)
    else update.check(false) end
end

-- Once, a little after loading (never during login).
function update.on_load()
    if not (S.update and S.update.check) or not configured() then return end
    coroutine.schedule(function() pcall(update.check, true) end, 30)
end

function update.init(settings, logger)
    S, log = settings, logger
end

return update
