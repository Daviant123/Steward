--[[
Steward window lines: one fixed-width text line built from pieces, some of them clickable.

Hover highlight: the clickable word (or item) under the mouse is drawn in a bright colour and its
whole row gets a lighter background, so it's easy to see what a click will do. Pieces added in a
row with the same click action (e.g. "[ ] " and the item name in the picker) light up together.
]]

local M = {}

M.HL_TEXT = '255,235,120'                 -- hovered clickable text
M.HL_BG = { 52, 72, 112 }                 -- row background under the mouse
M.BG = { 18, 20, 26 }                     -- normal row background

function M.line(width)
    local l = { disp = '', str = '', segs = {}, pieces = {}, width = width }
    local last_action, last_group, groups = nil, nil, 0
    function l:add(text, color, action)
        text = text:gsub('\\', '/')
        local start = #self.disp
        self.disp = self.disp .. text
        self.str = self.str .. (color and ('\\cs(' .. color .. ')' .. text .. '\\cr') or text)
        local group
        if action then
            if action == last_action then group = last_group
            else groups = groups + 1 group = groups end
            self.segs[#self.segs + 1] = { start, #self.disp - 1, action, group = group }
        end
        last_action, last_group = action, group
        self.pieces[#self.pieces + 1] = { text = text, color = color, group = group }
        return self
    end
    function l:col(n) if #self.disp < n then self:add(string.rep(' ', n - #self.disp)) end return self end
    function l:finish()
        if width and #self.disp > width then self.disp = self.disp:sub(1, width) end
        return width and self:col(width) or self
    end
    return l
end

-- Which clickable group is at this column? (nil if none)
function M.group_at(l, col)
    if not l or not col then return nil end
    for _, seg in ipairs(l.segs or {}) do
        if col >= seg[1] and col <= seg[2] then return seg.group end
    end
    return nil
end

-- The line's text, with one group highlighted (or the normal text if group is nil).
function M.render(l, group)
    if not l then return nil end
    if not group or not l.pieces then return l.str end
    local out = {}
    for _, p in ipairs(l.pieces) do
        local color = (p.group == group) and M.HL_TEXT or p.color
        out[#out + 1] = color and ('\\cs(' .. color .. ')' .. p.text .. '\\cr') or p.text
    end
    return table.concat(out)
end

-- Paint a box's background (normal or highlighted). Safe if the text object can't do it.
function M.paint(box, on)
    if box and box.bg_color then
        local c = on and M.HL_BG or M.BG
        pcall(box.bg_color, box, c[1], c[2], c[3])
    end
end

--[[
Hover tracker for a window made of text boxes, one per line.
  local hv = M.tracker()
  hv:move(i, col, layout, boxes)   -- on mouse move (i = row under the mouse or nil)
  hv:apply(layout, boxes)          -- after the window redraws its lines
]]
function M.tracker()
    local t = { row = nil, col = nil, group = nil }
    local function draw(row, group, layout, boxes)
        local b, l = boxes[row], layout[row]
        if not b or not l then return end
        b:text(M.render(l, group) or l.str)
        M.paint(b, group ~= nil)
    end
    function t:move(i, col, layout, boxes)
        local group = i and M.group_at(layout[i], col) or nil
        if i == self.row and group == self.group then self.col = col return end
        if self.row and self.group then draw(self.row, nil, layout, boxes) end
        self.row, self.col, self.group = i, col, group
        if i and group then draw(i, group, layout, boxes) end
    end
    function t:apply(layout, boxes)
        if not self.row then return end
        local group = M.group_at(layout[self.row], self.col)
        self.group = group
        if group then draw(self.row, group, layout, boxes) else M.paint(boxes[self.row], false) end
    end
    function t:clear(layout, boxes)
        if self.row then draw(self.row, nil, layout, boxes) end
        self.row, self.col, self.group = nil, nil, nil
    end
    return t
end

return M
