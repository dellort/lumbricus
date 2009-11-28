-- corresponds (more or less) directly to src/utils/vector2.d

Vector2 = {}
Vector2.__index = Vector2
setmetatable(Vector2, {__call = function(self, x, y)
    if (y) then
        return setmetatable({x = x, y = y}, Vector2)
    else
        return setmetatable({x = x, y = x}, Vector2)
    end
end})

function Vector2:__add(v)
    return Vector2(self.x + v.x, self.y + v.y)
end

function Vector2:__sub(v)
    return Vector2(self.x - v.x, self.y - v.y)
end

function Vector2:__mul(v)
    if type(v) == "table" then
        return self.x * v.x + self.y * v.y;
    else
        return Vector2(self.x * v, self.y * v)
    end
end

function Vector2:__div(v)
    if type(v) == "table" then
        return Vector2(self.x / v.x, self.y / v.y)
    else
        return Vector2(self.x / v, self.y / v)
    end
end

function Vector2:__unm()
    return Vector2(-self.x, -self.y)
end

function Vector2:__len()
    return math.sqrt(self.x*self.x, self.y*self.y)
end

function Vector2:__eq(v)
    return self.x == v.x and self.y == v.y
end

function Vector2:quad_length()
    return self.x*self.x + self.y*self.y
end

function Vector2:toAngle()
    return math.atan2(self.y, self.x)
end

function Vector2:print()
    print(tostring(self))
end

function Vector2:__tostring()
    return string.format("(%g, %g)", self.x, self.y)
end
