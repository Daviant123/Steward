--[[
Steward guard: stops runaway errors and loops.

  * The same error message is shown at most once a minute.
  * 3 errors within 5 minutes  -> automation pauses.
  * The same item moved back and forth between two bags 3+ times in 10 minutes -> automation pauses.
  * More than 6 automatic sorts that each moved something within 3 minutes -> automation pauses.
  * Paused means: no automatic sorting, dropping, lotting/passing or stacking until you
    press Resume in the window or type //stw resume. Manual commands still work.
]]

local journal = require('st_journal')
local guard = { paused = false, reason = '' }
local log
local errors = {}          -- times of recent errors
local shown = {}           -- message -> last time shown
local item_moves = {}      -- item key -> { times }
local auto_runs = {}       -- times of automatic sorts that moved something

local function now() return os.clock() end

local function recent(list, window)
    local t, out = now(), {}
    for _, x in ipairs(list) do if t - x <= window then out[#out + 1] = x end end
    return out
end

function guard.pause(reason)
    if guard.paused then return end
    guard.paused, guard.reason = true, reason
    journal.write('PAUSE', reason)
    log('Automation PAUSED: ' .. reason)
    log('Fix the cause, then press Resume in the window or type //stw resume.')
    if guard.on_pause then guard.on_pause() end
end

function guard.resume()
    guard.paused, guard.reason = false, ''
    errors, item_moves, auto_runs, shown = {}, {}, {}, {}
    journal.write('RESUME', 'by user')
    log('Automation resumed.')
end

-- Report an error (shown at most once a minute); pauses after 3 in 5 minutes.
function guard.error(where, err)
    local msg = ('%s error: %s'):format(where, tostring(err):gsub('^.-:%d+: ', ''))
    local t = now()
    journal.write('ERROR', '%s | full: %s', msg, tostring(err))
    if not shown[msg] or t - shown[msg] > 60 then
        shown[msg] = t
        log(msg .. '  (//stw log shows details)')
    end
    errors = recent(errors, 300)
    errors[#errors + 1] = t
    if #errors >= 3 then guard.pause(('%d errors in a row (%s)'):format(#errors, msg)) end
end

-- Run fn safely. Never use this around code that sleeps (Windower can't sleep inside pcall).
function guard.call(where, fn, ...)
    local ok, res = pcall(fn, ...)
    if not ok then guard.error(where, res) return nil end
    return res
end

-- An item was moved from one bag to another. Moving many stacks of the same item one way is
-- normal; the same item going A->B and B->A over and over is a loop, so that pauses.
function guard.note_move(item_id, from, to, name)
    local per = item_moves[item_id] or {}
    item_moves[item_id] = per
    local dir, back = from .. '>' .. to, to .. '>' .. from
    per[dir] = recent(per[dir] or {}, 600)
    per[dir][#per[dir] + 1] = now()
    per[back] = recent(per[back] or {}, 600)
    if #per[dir] >= 3 and #per[back] >= 3 then
        guard.pause(('%s keeps moving back and forth'):format(name))
        return false
    end
    return true
end

-- An automatic sort finished.
function guard.note_auto_run(moved)
    if moved == 0 then return end
    auto_runs = recent(auto_runs, 180)
    auto_runs[#auto_runs + 1] = now()
    if #auto_runs > 6 then
        guard.pause(('automatic sorting ran %d times in 3 minutes'):format(#auto_runs))
    end
end

function guard.allow_auto() return not guard.paused end

function guard.init(logger) log = logger end

return guard
