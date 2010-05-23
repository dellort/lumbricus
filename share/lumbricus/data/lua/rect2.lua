-- corresponds to src/utils/rect2.d
-- depends on vector2.lua (is there a way to enforce this?)

Rect2 = {}
Rect2.__index = Rect2
setmetatable(Rect2, {__call = function(self, a, b, c, d)
    if c then
        -- x1, y1, x2, y2
        return setmetatable({p1 = Vector2(a, b), p2 = Vector2(c, d)}, Rect2)
    elseif b then
        -- p1, p2
        return setmetatable({p1 = a, p2 = b}, Rect2)
    elseif a then
        -- Vector2(0, 0), p2
        return setmetatable({p1 = Vector2(0), p2 = a}, Rect2)
    else
        return setmetatable({p1=Vector2(0), p2=Vector2(0)}, Rect2)
    end
end})

-- static
function Rect2.Span(a, b, c, d)
    if (c) then
        -- x, y, sx, sy
        return Rect2(a, b, a + c, b + d)
    else
        -- p, size
        return Rect2(a, a + b)
    end
end

function Rect2:__eq(v)
    return self.p1 == v.p1 and self.p2 == v.p2
end

-- translate by r
function Rect2:__add(r)
    return Rect2(self.p1 + r, self.p2 + r)
end
function Rect2:__sub(r)
    return Rect2(self.p1 - r, self.p2 - r)
end

function Rect2:size()
    return self.p2 - self.p1
end

function Rect2:center()
    return self.p1 + (self.p2-self.p1)/2
end

function Rect2:isInside(point)
    return point.x >= self.p1.x and point.y >= self.p1.y
        and point.x < self.p2.x and point.y < self.p2.y
end

function Rect2:print()
    print(tostring(self))
end

function Rect2:__tostring()
    return string.format("[%s - %s]", tostring(self.p1), tostring(self.p2))
end

-- xxx add more if you need it
