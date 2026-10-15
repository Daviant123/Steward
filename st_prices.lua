--[[
Steward prices: Auction House prices from ffxiah.com for the Advice tab (user request 2026-10-12).

  //stw prices          look up the items Advice would sell (only ones that can go on the AH)
  //stw prices stop     stop (so does //stw stop)
  //stw prices server <name>   e.g. carbuncle (the default)

Reads the same public item page your browser shows (https://www.ffxiah.com/item/<id>, plus the
"?stack=1" page for stackable items) for your server, and keeps, per item: the median price of the
recent sales and how many sold per week. Results are saved in data/prices.lua (shared by all your
characters) and reused for a few days.

Windower's Lua can't fetch web pages in the background, so each page briefly freezes the game
(usually well under a second, never more than the 8 s timeout). That's why it only runs when asked,
one page every few seconds. Nothing is bought or sold here: it only fills in the Advice text.
]]

local res = require('resources')
local journal = require('st_journal')

local prices = { running = false, stop = false }
local S, log

prices.servers = {
    asura = 28, bahamut = 1, bismarck = 25, carbuncle = 6, cerberus = 23, fenrir = 7, lakshmi = 27, leviathan = 11,
    odin = 12, phoenix = 5, quetzalcoatl = 16, ragnarok = 20, shiva = 2, siren = 17, sylph = 8, valefor = 9,
    alexander = 10, caitsith = 15, diabolos = 14, fairy = 30, garuda = 22, gilgamesh = 19, hades = 32, ifrit = 13,
    kujata = 24, midgardsormr = 29, pandemonium = 21, ramuh = 4, remora = 31, seraph = 26, titan = 3, unicorn = 18,
}

prices.now = function() return os.time() end
prices.cache = nil            -- id -> { t, m, r, n, sm, sr } (time, median, per week, sales seen, stack median, stack per week)

local function cfg() return S.prices end
local function sid() return prices.servers[(cfg().server or 'carbuncle'):lower()] or 6 end

------------------------------------------------------------------------
-- Fetching (blocking; called inside pcall, never yields)
------------------------------------------------------------------------
-- Returns the page text, or nil and a reason. Follows ffxiah's redirect to the item's full address.
function prices.get(url)
    local https = require('ssl.https')
    local ltn12 = require('ltn12')
    https.TIMEOUT = 8
    for _ = 1, 3 do
        local body = {}
        local ok, code, headers = https.request({
            url = url, sink = ltn12.sink.table(body), redirect = false,
            headers = { cookie = 'sid=' .. sid(), ['user-agent'] = 'Steward (Windower addon)' },
        })
        if not ok then return nil, tostring(code) end
        if (code == 301 or code == 302) and headers and headers.location then
            url = headers.location
            if url:sub(1, 1) == '/' then url = 'https://www.ffxiah.com' .. url end
        elseif code == 200 then
            return table.concat(body)
        else
            return nil, 'HTTP ' .. tostring(code)
        end
    end
    return nil, 'too many redirects'
end

local function median(list)
    if #list == 0 then return nil end
    table.sort(list)
    local mid = math.floor((#list + 1) / 2)
    if #list % 2 == 1 then return list[mid] end
    return math.floor((list[mid] + list[mid + 1]) / 2)
end

-- From one item page: median of the newest sales (last 90 days, at most 30), and sales per week
-- (last 30 days). Falls back to the page's own "Median" when no sales are listed.
function prices.parse(html, server, now)
    now = now or prices.now()
    local sales = {}
    local blob = html and html:match('Item%.sales = %[(.-)%];')
    for obj in (blob or ''):gmatch('{(.-)}') do
        local t = tonumber(obj:match('"saleon":(%d+)'))
        local p = tonumber(obj:match('"price":(%d+)'))
        local sv = tonumber(obj:match('"seller_server":(%d+)'))
        if t and p and (not sv or sv == server) then sales[#sales + 1] = { t = t, p = p } end
    end
    table.sort(sales, function(a, b) return a.t > b.t end)
    local recent, month = {}, 0
    for _, s in ipairs(sales) do
        if now - s.t <= 90 * 86400 and #recent < 30 then recent[#recent + 1] = s.p end
        if now - s.t <= 30 * 86400 then month = month + 1 end
    end
    local m = median(recent)
    if not m and html then
        local pm = html:match('Median%s*</td>.-number%-format>([%d,]+)<')
        m = pm and tonumber((pm:gsub(',', ''))) or nil
        if m == 0 then m = nil end
    end
    return { m = m, r = math.floor(month * 7 / 30 * 10 + 0.5) / 10, n = #recent }
end

------------------------------------------------------------------------
-- Saved prices (data/prices.lua, all characters)
------------------------------------------------------------------------
local function path() return windower.addon_path .. 'data/prices.lua' end

local function read_file()
    local f = io.open(path(), 'r')
    if not f then return {} end
    local text = f:read('*a')
    f:close()
    local chunk = loadstring and loadstring(text) or load(text)
    local ok, t = pcall(chunk or function() return {} end)
    return (ok and type(t) == 'table') and t or {}
end

function prices.load()
    prices.cache = read_file()
    return prices.cache
end

-- Write, keeping newer entries another character saved meanwhile.
function prices.save()
    local disk = read_file()
    for id, e in pairs(prices.cache or {}) do
        if not disk[id] or (disk[id].t or 0) <= (e.t or 0) then disk[id] = e end
    end
    prices.cache = disk
    local ids = {}
    for id in pairs(disk) do ids[#ids + 1] = id end
    table.sort(ids)
    local out = { '-- Steward: ffxiah.com prices (server id, time, median, sold per week, ...). Safe to delete.', 'return {' }
    for _, id in ipairs(ids) do
        local e = disk[id]
        out[#out + 1] = ('[%d]={s=%d,t=%d,m=%s,r=%s,n=%d,sm=%s,sr=%s},'):format(id, e.s or 0, e.t or 0, tostring(e.m or 'nil'),
            tostring(e.r or 0), e.n or 0, tostring(e.sm or 'nil'), tostring(e.sr or 'nil'))
    end
    out[#out + 1] = '}'
    local f = io.open(path(), 'w')
    if f then f:write(table.concat(out, '\n')) f:close() end
end

-- The saved price for an item on your server, or nil.
function prices.of(id)
    if not prices.cache then prices.load() end
    local e = prices.cache[id]
    if e and (e.s or 0) == sid() then return e end
    return nil
end

local function fresh(id)
    local e = prices.of(id)
    return e and prices.now() - (e.t or 0) < (tonumber(cfg().max_age_days) or 3) * 86400
end

------------------------------------------------------------------------
-- What Advice shows
------------------------------------------------------------------------
local function gil(n)
    if not n then return '?' end
    if n >= 1000000 then return (('%.1fM'):format(n / 1000000):gsub('%.0M', 'M')) end
    if n >= 10000 then return ('%dk'):format(math.floor(n / 1000 + 0.5)) end
    local s = tostring(n):reverse():gsub('(%d%d%d)', '%1,'):reverse()
    return (s:gsub('^,', ''))
end
prices.gil = gil
local function per_week(r) r = tonumber(r) or 0 return r == math.floor(r) and ('%d'):format(r) or ('%.1f'):format(r) end

-- Is it worth taking to the AH? Returns a short text for Advice and true/false (nil = not looked up).
function prices.verdict(id)
    if not S then return nil end
    local e = prices.of(id)
    if not e then return nil end
    local min = tonumber(cfg().min_ah) or 2000
    local single = e.m and e.r >= 1 and e.m >= min
    local stack = e.sm and (e.sr or 0) >= 1 and e.sm >= min
    local txt
    if e.sm then
        txt = ('AH %s ea %s/wk, x stack %s'):format(gil(e.m), per_week(e.r), gil(e.sm))
    else
        txt = ('AH %s, %s/wk'):format(gil(e.m), per_week(e.r))
    end
    if not e.m and not e.sm then txt = 'no AH sales lately' end
    return txt, (single or stack) and true or false
end

------------------------------------------------------------------------
-- //stw prices
------------------------------------------------------------------------
local function look_up(id)
    local item = res.items[id]
    local url = 'https://www.ffxiah.com/item/' .. id
    local html, why = prices.get(url)
    if not html then return nil, why end
    local e = prices.parse(html, sid())
    if item and (item.stack or 1) > 1 then
        local h2 = prices.get(url .. '/?stack=1')
        if h2 then
            local st = prices.parse(h2, sid())
            e.sm, e.sr = st.m, st.r
        end
    end
    e.s, e.t = sid(), prices.now()
    return e
end

-- ids: list of item ids to look up (already-fresh ones are skipped).
function prices.run(ids)
    if prices.running then log('Prices: already looking them up. //stw prices stop stops it.') return end
    if not prices.cache then prices.load() end
    local todo = {}
    for _, id in ipairs(ids) do if not fresh(id) then todo[#todo + 1] = id end end
    if #todo == 0 then
        log(('Prices: all %d item(s) were looked up in the last %d days. (Advice tab shows them.)'):format(#ids, tonumber(cfg().max_age_days) or 3))
        return
    end
    local every = math.max(2, tonumber(cfg().every) or 5)
    prices.running, prices.stop = true, false
    log(('Prices: looking up %d item(s) on ffxiah.com (%s), one every %d s (about %d min).'):format(#todo,
        (cfg().server or 'carbuncle'):gsub('^%l', string.upper), every, math.ceil(#todo * every / 60)))
    log('  The game may hitch for a moment at each one. //stw prices stop (or //stw stop) stops it.')
    journal.write('PRICES', 'start: %d item(s), server %s', #todo, tostring(cfg().server))
    local done, failed = 0, 0
    for i, id in ipairs(todo) do
        if prices.stop then break end
        local ok, e, why = pcall(look_up, id)
        if ok and e then
            prices.cache[id] = e
            done = done + 1
            journal.write('PRICES', '%s: median %s, %s/wk, stack %s', res.items[id] and res.items[id].en or id,
                tostring(e.m), tostring(e.r), tostring(e.sm))
        else
            failed = failed + 1
            journal.write('PRICES', '%s: failed (%s)', tostring(id), tostring(ok and why or e))
            if failed >= 3 and done == 0 then break end
        end
        if done > 0 and done % 10 == 0 then prices.save() log(('Prices: %d of %d done.'):format(i, #todo)) end
        if i < #todo and not prices.stop then coroutine.sleep(every) end
    end
    prices.save()
    prices.running = false
    if done == 0 and failed > 0 then log('Prices: ffxiah.com is not answering; stopped. Try again later.') end
    log(('Prices: %d looked up%s%s. See the Advice tab.'):format(done, failed > 0 and (', %d failed'):format(failed) or '',
        prices.stop and ' (stopped)' or ''))
    journal.write('PRICES', 'done: %d ok, %d failed', done, failed)
    if prices.on_finish then prices.on_finish() end
end

function prices.set_server(name)
    name = (name or ''):lower():gsub('%s', '')
    if not prices.servers[name] then
        local t = {}
        for k in pairs(prices.servers) do t[#t + 1] = k end
        table.sort(t)
        log('Prices: unknown server. Servers: ' .. table.concat(t, ', '))
        return false
    end
    cfg().server = name
    return true
end

function prices.init(settings, logger)
    S, log = settings, logger
end

return prices
