-- corresponds to src/utils/time.d
-- in what unit timeVal is is also determined by the D code

Time = {}
Time.__index = Time
setmetatable(Time, {__call = function(self, timeVal)
    return setmetatable({timeVal = timeVal}, Time)
end})

function Time:__add(v)
    return Time(self.timeVal + v.timeVal)
end
function Time:__sub(v)
    return Time(self.timeVal - v.timeVal)
end
function Time:__mul(v)
    return Time(self.timeVal * v)
end
function Time:__div(v)
    return Time(self.timeVal / v)
end
function Time:__unm()
    return Time(-self.timeVal)
end

function Time:__eq(v)
    return self.timeVal == v.timeVal
end
function Time:__lt(v)
    return self.timeVal < v.timeVal
end
function Time:__le(v)
    return self.timeVal <= v.timeVal
end

function Time:__tostring()
    return string.format("%g s", self:secs())
end
function Time:print()
    print(tostring(self))
end

function Time:musecs()
    return self.timeVal/1000
end
function Time:msecs()
    return self.timeVal/1000000
end
function Time:secs()
    return self:msecs()/1000
end
function Time:mins()
    return self:msecs()/60000
end

-- like the functions above, but use the passed Time as unit
-- essentially divides and returns a lua number
-- (why does __div return a Time anyway???)
function Time:unitsf(unit)
    return self.timeVal/unit.timeVal
end

function timeMusecs(v)
    return Time(v*1000)
end
function timeMsecs(v)
    return Time(v*1000000)
end
function timeSecs(v)
    return timeMsecs(v*1000)
end
function timeMins(v)
    return timeMsecs(v*60000)
end

Time.Null = Time(0)
Time.Second = timeSecs(1)

-- convert x to Time
-- x is either...
--  - a number => interpreted as seconds
--  - a string => parsed by D code
--  - a Time => passed through
function time(x)
    if type(x) == "number" then
        return timeSecs(x)
    elseif type(x) == "string" then
        return timeParse(x)
    elseif getmetatable(x) == Time then
        return x
    end
    assert(false)
end

