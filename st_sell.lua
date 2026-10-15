--[[
Steward Sell list: items you want sold to NPC shops (user request 2026-10-12).

Steward never sells anything itself. It hands the list to the SellNPC addon (by Ivaar, in addons\SellNPC):
"//sellnpc <item>" queues an item, and the next time you open any NPC shop SellNPC sells every copy in
your INVENTORY, then forgets its queue. So Steward queues:
  * an item the moment you add it to the Sell list,
  * the whole list after every shop visit (ready for the next one), and
  * the whole list on //stw sell load (or [Load into SellNPC] on the Sell tab).
Taking an item off the list reloads SellNPC (which empties its queue) and queues the rest again.

Never on the list: Keep-list items, items the game won't let you sell to an NPC, and anything that is
in a Mog Wardrobe (wardrobe gear is never sold). SellNPC only sells from the inventory anyway.
]]

local rules = require('st_rules')
local journal = require('st_journal')

local sell = {}
local S, log, loot

sell.send = function(cmd) windower.send_command(cmd) end      -- tests replace this
sell.requeue_delay = 3                                        -- seconds after a shop opens

local function item_flags(id)
    local item = require('resources').items[id]
    return item and item.flags
end

local function has_flag(f, name)
    return type(f) == 'table' and (f[name] == true or (type(f.contains) == 'function' and f:contains(name))) or false
end

-- Item ids in the Mog Wardrobes (never offered or sold).
function sell.wardrobe_ids()
    local set = {}
    for _, bid in ipairs(rules.wardrobes) do
        local bag = windower.ffxi.get_items(bid)
        for _, it in ipairs(type(bag) == 'table' and bag or {}) do
            if type(it) == 'table' and it.id then set[it.id] = true end
        end
    end
    return set
end
local function in_wardrobe(id) return sell.wardrobe_ids()[id] == true end

-- Can this item go on the Sell list? Returns nil, or why not.
function sell.refuse(name)
    local id = loot.id_of(name)
    if not id then return nil end            -- unknown names are rejected by loot.edit with a spelling hint
    local proper = rules.item_name(id)
    if rules.name_set(S.lists.keep)[proper:lower()] then
        return ('%s is on your Keep list, so it is never sold.'):format(proper)
    end
    if has_flag(item_flags(id), 'No NPC Sale') then
        return ('%s cannot be sold to an NPC.'):format(proper)
    end
    if in_wardrobe(id) then
        return ('%s is in a Mog Wardrobe; wardrobe gear is never sold.'):format(proper)
    end
    return nil
end

local function command_for(names)
    local parts = {}
    for i, n in ipairs(names) do
        if i > 1 then parts[#parts + 1] = 'wait 0.2' end
        parts[#parts + 1] = 'sellnpc ' .. n
    end
    return table.concat(parts, '; ')
end

-- Queue these names in SellNPC (skipping any that are no longer allowed).
function sell.queue(names)
    local ok = {}
    for _, n in ipairs(names) do
        if not sell.refuse(n) then ok[#ok + 1] = n end
    end
    if #ok > 0 then sell.send(command_for(ok)) end
    return #ok
end

-- //stw sell load: the whole list into SellNPC.
function sell.load(quiet)
    local n = sell.queue(rules.split(S.lists.sell))
    journal.write('SELL', 'queued %d item(s) in SellNPC', n)
    if not quiet then
        if n == 0 then log('Sell list is empty. Add items on the Sell tab or with //stw sell add <item>.')
        else
            log(('Sell list: %d item(s) queued in SellNPC; they sell from your inventory at the next NPC shop you open.'):format(n))
            log('  (Needs SellNPC loaded: //lua load sellnpc)')
        end
    end
    return n
end

-- After the Sell list changed.
function sell.edited(action, name)
    if action == 'add' then
        local canonical = loot.canonical(name) or name
        if rules.name_set(S.lists.sell)[canonical:lower()] then
            sell.queue({ canonical })
            journal.write('SELL', 'queued %s in SellNPC', canonical)
            log(('  Queued in SellNPC: the %s in your inventory sell at the next NPC shop you open.'):format(canonical))
        end
    else
        -- SellNPC can't take one item off its queue: reload it (empty queue) and queue the rest again.
        local rest = rules.split(S.lists.sell)
        sell.send('lua reload sellnpc' .. (#rest > 0 and ('; wait 1; ' .. command_for(rest)) or ''))
        journal.write('SELL', 'SellNPC reloaded, %d item(s) queued again', #rest)
    end
end

-- Incoming 0x03C (an NPC shop opened): SellNPC sells now and empties its queue; queue the list again
-- a few seconds later so the next shop visit sells new copies too.
local pending = false
function sell.incoming(id)
    if id ~= 0x03C or pending or rules.split(S.lists.sell)[1] == nil then return end
    pending = true
    coroutine.schedule(function()
        pending = false
        sell.load(true)
    end, sell.requeue_delay)
end

function sell.init(settings, logger, loot_module)
    S, log, loot = settings, logger, loot_module
end

return sell
