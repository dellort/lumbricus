-- used to correspond to src/utils/time.d
-- now, times are marshalled as double values giving the time in seconds

--[[
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
]]

function timeMusecs(v)
    return v/1000/1000
end
function timeMsecs(v)
    return v/1000
end
function timeSecs(v)
    return v
end
function timeMins(v)
    return v*60
end

Time = {}
Time.Null = 0
Time.Second = 1.0

-- convert x to Time
-- x is either...
--  - a number => interpreted as seconds
--  - a string => parsed by D code
function time(x)
    if type(x) == "number" then
        return x
    elseif type(x) == "string" then
        return timeParse(x)
    end
    assert(false)
end

-- this is for simpler support of RandomValue!(Time), which in Lua recudes to
--  a table {min=minval, max=maxval}
-- if b is nil, b is set to a
-- both a and b are converted by time()
-- this returns a table suitable to be passed as RandomValue!(Time) to D
function timeRange(a, b)
    return utils.range(time(a), b and time(b))
end

