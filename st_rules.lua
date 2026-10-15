--[[
Steward: the organization system.

Every item gets a category. Each category has a home bag (changeable in the GUI).
Weapons and armor in the mog wardrobes are a closed system: they are only ever moved
between wardrobes (sorted by gear slot), never into other bags and never to a porter.
]]

local res = require('resources')

local rules = {}

------------------------------------------------------------------------
-- Bags
------------------------------------------------------------------------
rules.bag_ids = {
    inventory = 0, safe = 1, storage = 2, temporary = 3, locker = 4, satchel = 5, sack = 6, case = 7,
    wardrobe = 8, safe2 = 9, wardrobe2 = 10, wardrobe3 = 11, wardrobe4 = 12, wardrobe5 = 13,
    wardrobe6 = 14, wardrobe7 = 15, wardrobe8 = 16,
}
rules.bag_names = {}
for name, id in pairs(rules.bag_ids) do rules.bag_names[id] = name end

rules.wardrobes = { 8, 10, 11, 12, 13, 14, 15, 16 }          -- wardrobe 1..8
rules.is_wardrobe = {}
for n, id in ipairs(rules.wardrobes) do rules.is_wardrobe[id] = n end

-- Bags you can only open in your Mog House.
rules.mog_house_only = { [1] = true, [2] = true, [4] = true, [9] = true }

-- Non-wardrobe bags a category can be sent to, in the order the GUI cycles through them.
rules.destinations = { 'stay', 'inventory', 'satchel', 'sack', 'case', 'safe', 'safe2', 'locker', 'storage' }

-- If the home bag is full, try these next.
-- Gear outside the wardrobes fills the Mog House bags in this order.
rules.gear_bags = { 'safe', 'safe2', 'storage', 'locker' }

rules.overflow = {
    satchel = { 'sack', 'case' }, sack = { 'satchel', 'case' }, case = { 'sack', 'satchel' },
    safe = { 'safe2', 'locker' }, safe2 = { 'safe', 'locker' }, locker = { 'safe2', 'safe' },
    storage = { 'safe2', 'safe' },
}

rules.pretty_bag = {
    stay = 'Leave in place', inventory = 'Inventory', satchel = 'Mog Satchel', sack = 'Mog Sack', case = 'Mog Case',
    safe = 'Mog Safe', safe2 = 'Mog Safe 2', locker = 'Mog Locker', storage = 'Storage',
    wardrobe = 'Wardrobe 1', wardrobe2 = 'Wardrobe 2', wardrobe3 = 'Wardrobe 3', wardrobe4 = 'Wardrobe 4',
    wardrobe5 = 'Wardrobe 5', wardrobe6 = 'Wardrobe 6', wardrobe7 = 'Wardrobe 7', wardrobe8 = 'Wardrobe 8',
    temporary = 'Temporary',
}

------------------------------------------------------------------------
-- Categories for everything that is not wardrobe gear
------------------------------------------------------------------------
rules.categories = {
    { key = 'crystals',    label = 'Crystals & clusters',        default = 'sack' },
    { key = 'consumables', label = 'Food, medicine, scrolls',    default = 'satchel' },
    { key = 'materials',   label = 'Crafting & loot materials',  default = 'case' },
    { key = 'slips',       label = 'Storage slips',              default = 'case' },
    { key = 'currency',    label = 'Currency, seals, vouchers',  default = 'safe' },
    { key = 'automaton',   label = 'Automaton attachments',      default = 'sack' },
    { key = 'furnishings', label = 'Furniture & plants',         default = 'storage' },
    { key = 'quest',       label = 'Quest items & other',        default = 'safe' },
    { key = 'equipment',   label = 'Gear outside wardrobes',     default = 'safe' },
    { key = 'linkshells',  label = 'Linkshells & pearls',        default = 'stay' },
}
rules.category_label = {}
for _, c in ipairs(rules.categories) do rules.category_label[c.key] = c.label end

-- Item "type" numbers from the game data.
local type_category = {
    [1] = 'materials', [2] = 'quest', [3] = 'materials', [4] = 'equipment', [5] = 'equipment',
    [6] = 'linkshells', [7] = 'consumables', [8] = 'crystals', [9] = 'currency', [10] = 'furnishings',
    [11] = 'furnishings', [12] = 'furnishings', [13] = 'automaton', [14] = 'furnishings', [15] = 'quest',
    [16] = 'quest', [17] = 'quest', [18] = 'quest', [19] = 'quest', [20] = 'quest', [21] = 'quest',
    [22] = 'currency', [23] = 'currency', [24] = 'currency', [25] = 'currency', [26] = 'currency',
    [27] = 'slips', [28] = 'quest',
}

-- Named currencies that the game files list as plain items.
local currency_names = {
    ["beastmen's seal"] = true, ["kindred's seal"] = true, ["kindred's crest"] = true,
    ["high kindred's crest"] = true, ["sacred kindred's crest"] = true,
    ['ordelle bronzepiece'] = true, ['one byne bill'] = true, ['tukuku whiteshell'] = true,
    ['montiont silverpiece'] = true, ['one hundred byne bill'] = true, ['lungo-nango jadeshell'] = true,
    ['ranperre goldpiece'] = true, ['ten thousand byne bill'] = true, ['rimilala stripeshell'] = true,
}

function rules.category(item_id)
    local item = res.items[item_id]
    if not item then return 'quest' end
    if currency_names[(item.english or ''):lower()] then return 'currency' end
    return type_category[item.type] or 'quest'
end

function rules.is_gear(item_id)
    local item = res.items[item_id]
    return item ~= nil and (item.type == 4 or item.type == 5)
end

------------------------------------------------------------------------
-- Wardrobes: organized by gear slot
------------------------------------------------------------------------
-- Slot ids: 0 main, 1 sub, 2 range, 3 ammo, 4 head, 5 body, 6 hands, 7 legs, 8 feet,
--           9 neck, 10 waist, 11/12 ears, 13/14 rings, 15 back
rules.slot_groups = {
    { key = 'weapons',     label = 'Weapons & shields', slots = { 0, 1 } },
    { key = 'head',        label = 'Head',              slots = { 4 } },
    { key = 'body',        label = 'Body',              slots = { 5 } },
    { key = 'hands',       label = 'Hands',             slots = { 6 } },
    { key = 'legs',        label = 'Legs',              slots = { 7 } },
    { key = 'feet',        label = 'Feet',              slots = { 8 } },
    { key = 'accessories', label = 'Neck, ears, rings, waist, back', slots = { 9, 10, 11, 12, 13, 14, 15 } },
    { key = 'ranged',      label = 'Ranged & ammo',     slots = { 2, 3 } },
}

-- Default wardrobe for each group, depending on how many wardrobes are unlocked.
local layouts = {
    [8] = { weapons = 1, head = 2, body = 3, hands = 4, legs = 5, feet = 6, accessories = 7, ranged = 8 },
    [7] = { weapons = 1, head = 2, body = 3, hands = 4, legs = 5, feet = 6, accessories = 7, ranged = 1 },
    [6] = { weapons = 1, head = 2, body = 3, hands = 4, legs = 5, feet = 5, accessories = 6, ranged = 1 },
    [5] = { weapons = 1, head = 2, body = 2, hands = 3, legs = 3, feet = 4, accessories = 5, ranged = 1 },
    [4] = { weapons = 1, head = 2, body = 2, hands = 3, legs = 3, feet = 3, accessories = 4, ranged = 1 },
    [3] = { weapons = 1, head = 2, body = 2, hands = 2, legs = 2, feet = 2, accessories = 3, ranged = 1 },
    [2] = { weapons = 1, head = 2, body = 2, hands = 2, legs = 2, feet = 2, accessories = 2, ranged = 1 },
    [1] = { weapons = 1, head = 1, body = 1, hands = 1, legs = 1, feet = 1, accessories = 1, ranged = 1 },
}
function rules.default_layout(enabled_count)
    return layouts[math.max(1, math.min(8, enabled_count))]
end

local slot_to_group = {}
for _, g in ipairs(rules.slot_groups) do
    for _, s in ipairs(g.slots) do slot_to_group[s] = g.key end
end

-- Which slot group a piece of gear belongs to (by the first slot it can be worn in).
function rules.slot_group(item_id)
    local item = res.items[item_id]
    if not item or not item.slots then return 'accessories' end
    local best
    for slot, v in pairs(item.slots) do
        local s = (type(slot) == 'number' and v == true) and slot or (type(v) == 'number' and v) or nil
        if s and slot_to_group[s] and (not best or s < best) then best = s end
    end
    return best and slot_to_group[best] or 'accessories'
end

------------------------------------------------------------------------
-- Lists
------------------------------------------------------------------------
-- Items that always stay in your inventory (edit in the GUI: Keep tab).
rules.default_keep = table.concat({
    'Warp Ring', 'Dim. Ring (Holla)', 'Dim. Ring (Dem)', 'Dim. Ring (Mea)', 'Echad Ring', 'Trizek Ring',
    'Capacity Ring', 'Facility Ring', 'Caliber Ring', 'Emporox\'s Ring', 'Reraise Earring',
    'Echo Drops', 'Remedy', 'Holy Water', 'Panacea', 'Silent Oil', 'Prism Powder', 'Hi-Potion',
    'Shihei', 'Inoshishinofuda', 'Chonofuda', 'Shikanofuda', 'Sanjaku-Tenugui', 'Toolbag (Shihe)',
    'Instant Warp', 'Instant Reraise', 'Grape Daifuku', 'Sublime Sushi', 'Tropical Crepe',
}, '|')

function rules.split(s)
    local out = {}
    for raw in (s or ''):gmatch('[^|]+') do
        local piece = raw:gsub('^%s+', ''):gsub('%s+$', '')
        if piece ~= '' then out[#out + 1] = piece end
    end
    return out
end

function rules.join(list) return table.concat(list, '|') end

-- Bags a category may overflow into (the 2nd / 3rd choices on the Rules tab).
rules.overflow_choices = { 'satchel', 'sack', 'case', 'safe', 'safe2', 'locker', 'storage' }

-- Your own 2nd/3rd choices per category: settings.overflow (Steward.lua sets overflow_source, so the
-- live settings are always read). '' = automatic (the lists above); otherwise 'bag2|bag3', where
-- 'none' leaves a place empty.
rules.overflow_source = function() return {} end
local function custom_for(cat)
    local t = rules.overflow_source()
    return type(t) == 'table' and type(t[cat]) == 'string' and t[cat] or ''
end

-- The automatic overflow bags for a category whose home is `home`.
function rules.auto_overflow(cat, home)
    if cat == 'equipment' then
        local rest = {}
        for _, b in ipairs(rules.gear_bags) do if b ~= home then rest[#rest + 1] = b end end
        return rest
    end
    return rules.overflow[home] or {}
end

-- The 2nd and 3rd choices as shown on the Rules tab: { bag2, bag3 } ('none' if empty), and
-- whether they're your own (false = automatic).
function rules.overflow_slots(cat, home)
    local custom = custom_for(cat)
    local out = {}
    if custom ~= '' then
        for _, b in ipairs(rules.split(custom)) do out[#out + 1] = b end
    else
        for _, b in ipairs(rules.auto_overflow(cat, home)) do out[#out + 1] = b end
    end
    return { out[1] or 'none', out[2] or 'none' }, custom ~= ''
end

-- Bags to try, in order, for a category whose home is `home`.
function rules.bag_order(cat, home)
    local order, seen = { home }, { [home] = true }
    local custom = custom_for(cat)
    local rest = custom ~= '' and rules.split(custom) or rules.auto_overflow(cat, home)
    for _, b in ipairs(rest) do
        if rules.bag_ids[b] and not rules.is_wardrobe[rules.bag_ids[b]] and b ~= 'inventory' and b ~= 'temporary' and not seen[b] then
            order[#order + 1] = b
            seen[b] = true
        end
    end
    return order
end

-- Lowercased name -> true, for fast lookups.
function rules.name_set(s)
    local set = {}
    for _, n in ipairs(rules.split(s)) do set[n:lower()] = true end
    return set
end

function rules.item_name(item_id)
    local item = res.items[item_id]
    return item and (item.english or item.name) or ('#' .. tostring(item_id))
end

return rules
