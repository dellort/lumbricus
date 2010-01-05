-- game specific machinery for timers and per frame callbacks
-- makes use of the Time data type in time.lua

_currentTime = timeSecs(0)

-- return the current frame's time as Time object
function currentTime()
    return _currentTime
end

_perFrameCbs = {}

-- gets called by game.d
function game_per_frame()
    _currentTime = Time_current(Game_gameTime())
    _run_timers()
    for k,v in pairs(_perFrameCbs) do
        k()
    end
end

-- make cb get called on each game frame (one should be careful with this!)
function frameCallbackAdd(cb)
    _perFrameCbs[cb] = true
end

function frameCallbackRemove(cb)
    _perFrameCbs[cb] = nil
end

-- singly linked list of Timers, sorted by earlierst trigger time
_timerHead = nil

Timer = {}
Timer.__index = Timer

-- create a one-shot timer, in most cases addTimer() will be simpler
function Timer.new()
    local res = {}
    setmetatable(res, Timer)
    res._destTime = Time.Null
    res._added = false
    return res
end

-- set relative amount of time that should be waited until calling the callback
-- duration is a Time
-- calling this activates the timer
-- if duration is 0 or negative, the cb will be called right on the next frame
-- when the wait time has elapsed, the timer is deactivated again
function Timer:setDuration(duration)
    self:_remove()
    self._destTime = currentTime() + duration
    self:_insert()
end

-- what is called when waiting time has elapsed
function Timer:setCallback(cb)
    self.cb = cb
end

-- deactivate the timer
function Timer:cancel()
    self:_remove()
end

function Timer:_insert()
    if self._added then
        return
    end
    -- insert into sorted queue
    local prev = nil
    local cur = _timerHead
    while cur do
        if self._destTime < cur._destTime then
            break
        end
        prev = cur
        cur = cur._next
    end
    if prev then
        self._next = prev._next
        prev._next = self
    else
        self._next = _timerHead
        _timerHead = self
    end
    self._added = true
end

function Timer:_remove()
    if not self._added then
        return
    end
    local prev = nil
    local cur = _timerHead
    while cur do
        if cur == self then
            break
        end
        prev = cur
        cur = cur._next
    end
    assert(cur == self)
    if prev then
        prev._next = self._next
    else
        assert(_timerHead == self)
        _timerHead = self._next
    end
    self._next = nil
    self._added = false
end

function Timer:isActive()
    return self._added
end

-- call cb() at the given relative time in the future
-- time is a Time
-- cb is an optional callback
-- returns a Timer with the time set
function addTimer(time, cb)
    local tr = Timer.new()
    tr:setCallback(cb)
    tr:setDuration(time)
    return tr
end

-- call cb in the next game engine frame
function addOnNextFrame(cb)
    addTimer(Time.Null, cb)
end

function _run_timers()
    -- the time list is sorted; so we need to check only the head of the list,
    --  and can stop iterating it as soon as the time is too high
    local ct = currentTime()
    while _timerHead do
        local cur = _timerHead
        if cur._destTime > ct then
            break
        end
        -- remove from list & trigger
        _timerHead = cur._next
        cur._next = nil
        cur._added = false
        if cur.cb then
            cur.cb()
        end
    end
end

function timertest()
    addTimer(timeSecs(1), function() printf("1 sec") end)
    addTimer(timeSecs(0.5), function() printf("0.5 sec") end)
    addTimer(timeSecs(10), function() printf("10 sec") end)
    addTimer(timeSecs(7), function() printf("7 sec") end)
    addTimer(timeSecs(-1), function() printf("-1 sec") end)
    local function never() printf("never happened!") end
    local x1 = addTimer(timeSecs(-1), never)
    local x2 = addTimer(timeSecs(11), never)
    local x3 = addTimer(timeSecs(8), never)
    x1:cancel()
    x2:cancel()
    x3:cancel()
    addOnNextFrame(function() printf("immediately") end)
end
