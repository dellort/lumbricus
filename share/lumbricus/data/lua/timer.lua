-- game specific machinery for timers and per frame callbacks
-- makes use of the Time data type in time.lua

_currentTime = timeSecs(0)

-- return the current frame's time as Time object
function currentTime()
    return _currentTime
end

_perFrameCbs = {}

-- changes each frame; used to catch the special case when timers re-add
--  themselves with duration 0 on a timer callback (the current code in
--  _run_timers() would go into an endless loop)
_frameCounter = 0

-- gets called by game.d
function game_per_frame()
    _currentTime = Time_current(Game_gameTime())
    _frameCounter = _frameCounter + 1
    _run_timers()
    for k,v in pairs(_perFrameCbs) do
        k()
    end
end

-- make cb get called on each game frame (one should be careful with this!)
function addFrameCallback(cb)
    _perFrameCbs[cb] = true
end

function removeFrameCallback(cb)
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
    res._periodic = false
    res._paused = false
    return res
end

-- set relative amount of time that should be waited until calling the callback
-- duration is a Time
-- calling this activates the timer
-- if duration is 0 or negative, the cb will be called right on the next frame
-- when the wait time has elapsed, the timer is deactivated again
function Timer:start(duration)
    self:_remove()
    self._paused = false
    if duration < Time.Null then
        duration = Time.Null
    end
    self._destTime = currentTime() + duration
    self._last_duration = duration
    self:_insert()
end

-- what is called when waiting time has elapsed
function Timer:setCallback(cb)
    self.cb = cb
end

-- the periodic option causes the timer to be restarted when it is triggered
-- after the cb is run, start(duration) is called again (with the same duration)
-- this implies that the periodic timer is quantized to game frames (e.g. if the
--  time is smaller than a game frame, the timer will be triggered exactly once
--  per game frame)
-- xxx maybe periodic should be automatically set to false in some situations,
--  and/or be a parameter for start()?
function Timer:setPeriodic(periodic)
    self._periodic = ifnil(periodic, true)
end

-- deactivate the timer
function Timer:cancel()
    self:_remove()
end

-- if the Timer is active, make it inactive and set paused state
-- note that the pause state is reset and lost with :start()
function Timer:pause()
    if self._paused or not self._added then
        return
    end
    self._paused = true
    self._pause_time = currentTime()
    self:_remove()
end

-- if the Timer is in pause state, re-activate the timer again
function Timer:resume()
    if not self._paused then
        return
    end
    assert(not self._added)
    self._paused = false
    local diff = currentTime() - self._pause_time
    self._pause_time = nil
    self._destTime = self._destTime + diff
    self:_insert()
end

-- if active, return destTime - currentTime
-- if paused, return timeLeft() at the point when pause() was called
-- otherwise, return nil
-- note that the returned time may be negative (if the time is up, but the
--  Timer hasn't been triggered+deactivated yet)
function Timer:timeLeft()
    local rel
    if self._added then
        rel = currentTime()
    elseif self._paused then
        rel = self._pause_time
    else
        return nil
    end
    return self._destTime - rel
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
    -- see _frameCounter for purpose
    self._added_frame = _frameCounter
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

function Timer:_trigger()
    assert(not self._added)
    if self.cb then
        self.cb()
    end
    if self._periodic and self._last_duration and not self._added then
        self:start(self._last_duration)
    end
end

-- call cb() at the given relative time in the future
-- time is a relative Time
-- cb is an optional callback
-- returns a Timer with the time set
function addTimer(time, cb)
    local tr = Timer.new()
    tr:setCallback(cb)
    tr:start(time)
    return tr
end

function addPeriodicTimer(time, cb)
    local t = addTimer(time, cb)
    t:setPeriodic()
    return t
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
        assert(cur._added)
        if cur._destTime > ct or cur._added_frame == _frameCounter then
            break
        end
        -- remove from list & trigger
        _timerHead = cur._next
        cur._next = nil
        cur._added = false
        cur:_trigger()
    end
end

function timertest()
    local c = 0
    local c2 = 0
    local c3 = 0
    local always = addTimer(timeSecs(0), function() c = c + 1 end)
    local always2 = addTimer(timeSecs(-1), function() c2 = c2 + 1 end)
    local always3 = addTimer(timeSecs(1), function() c3 = c3 + 1 end)
    always:setPeriodic(true)
    always2:setPeriodic(true)
    always3:setPeriodic(true)
    addTimer(timeSecs(1), function() printf("1 sec") always2:pause() end)
    local p = addTimer(timeSecs(2), function() printf("2+6.5 sec") end)
    addTimer(timeSecs(0.5), function() printf("0.5 sec") p:pause() end)
    addTimer(timeSecs(10), function() printf("10 sec") end)
    addTimer(timeSecs(7), function()
        printf("7 sec")
        always2:resume()
        printf("timeLeft for 2 sec timer: {}", p:timeLeft())
        p:resume()
        printf("timeLeft for 2 sec timer (2): {}", p:timeLeft())
    end)
    addTimer(timeSecs(-1), function() printf("-1 sec") end)
    local function never() printf("never happened!") end
    local x1 = addTimer(timeSecs(-1), never)
    local x2 = addTimer(timeSecs(11), never)
    local x3 = addTimer(timeSecs(8), never)
    x1:cancel()
    x2:cancel()
    x3:cancel()
    addOnNextFrame(function() printf("immediately") end)
    addTimer(timeSecs(11), function()
        printf("stop always, c={}", c)
        always:cancel()
        always2:cancel()
        always3:cancel()
    end)
    addTimer(timeSecs(12), function()
        printf("c={},c2={},c3={}", c, c2, c3)
        addTimer(Time.Null, function() printf("all should be done now") end)
    end)
end
