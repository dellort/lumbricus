-- corresponds to src/utils/color.d
-- NOTE: alternatively, we could pack the color into a number (a double has
--  enough bits to pack 4 x 8bit color values), then a table wouldn't be needed
-- for now, a table for simplicity

-- constructors:
--  Color(r, g, b [, a]): color with the three float values in range [0-1.0]
--  Color(k [, a]): grey value in range [0-1.0]
--  Color(): black (new instance, if you're evil enough to want to mutate it)
-- a (alpha) is by default 1.0 = fully opaque
Color = {}
Color.__index = Color
setmetatable(Color, {__call = function(self, p1, p2, p3, p4)
    local res
    if p3 then
        -- Color(r, g, b [, a])
        res = {r=p1,g=p2,b=p3,a=p4 or 1.0}
    elseif p1 then
        -- Color(k, [, a])
        res = {r=p1,g=p1,b=p1,a=p2 or 1.0}
    else
        -- Color()
        res = {r=0,g=0,b=0,a=1.0}
    end
    return setmetatable(res, Color)
end})

-- constants
Color.Black = Color(0)
Color.White = Color(1)
Color.Transparent = Color(0, 0, 0, 0)

-- and this was in color.d as well
local inf = 1/0 -- float.inf
Color.Invalid = Color(inf, inf, inf, inf)

function Color:__eq(v)
    return self.r == v.r
        and self.g == v.g
        and self.b == v.b
        and self.a == v.a
end

-- is this useful at all?
--[[
function Color:__add(o)
    return Color(self.r+o.r, self.g+o.g, self.b+o.b, self.a+o.a)
end
function Color:__sub(o)
    return Color(self.r-o.r, self.g-o.g, self.b-o.b, self.a-o.a)
end
]]

function Color:__mul(f)
    return Color(self.r*f, self.g*f, self.b*f, self.a*f)
end

function Color:__tostring()
    return utils.format("r={}, g={}, b={}, a={}", self.r, self.g, self.b,
        self.a)
end

-- xxx add more if you need it
