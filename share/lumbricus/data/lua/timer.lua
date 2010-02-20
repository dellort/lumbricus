-- game specific machinery for timers and per frame callbacks
-- makes use of the Time data type in time.lua

_currentTime = timeSecs(0)

-- return the current frame's time as Time object
function currentTime()
    return _currentTime
end

-- changes each frame; used to catch the special case when timers re-add
--  themselves with duration 0 on a timer callback (the current code in
--  _run_timers() would go into an endless loop)
_frameCounter = 0

-- gets called by game.d
function game_per_frame()
    _currentTime = Time_current(Game_gameTime())
    _frameCounter = _frameCounter + 1
    _run_timers()
end

-- singly linked list of Timers, sorted by earlierst trigger time
_timerHead = nil

Timer = {}
Timer.__index = Timer

-- create a one-shot timer, in most cases addTimer() will be simpler
function Timer.new()
    return setmetatable({
        _destTime = Time.Null,
        _added = false,
        _periodic = false,
        _paused = false,
    }, Timer)
end

-- set relative amount of time that should be waited until calling the callback
-- duration is a Time
-- calling this activates the timer
-- if duration is 0 or negative, the cb will be called right on the next frame
-- when the wait time has elapsed, the timer is deactivated again
--
-- the periodic option causes the timer to be restarted when it is triggered
-- after the cb is run, start(duration) is called again (with the same duration)
-- this implies that the periodic timer is quantized to game frames (e.g. if the
--  time is smaller than a game frame, the timer will be triggered exactly once
--  per game frame)
function Timer:start(duration, periodic)
    self:cancel()
    if duration < Time.Null then
        duration = Time.Null
    end
    self._destTime = currentTime() + duration
    self._last_duration = duration
    self._periodic = ifnil(periodic, false)
    self:_insert()
    self:_dolink("onStart")
end

-- what is called when waiting time has elapsed
function Timer:setCallback(cb)
    self.cb = cb
end

-- deactivate the timer (also resets pause state)
function Timer:cancel()
    -- corner case: if it was set periodic, must reset even if the timer isn't
    --  started right now (on linked timers, too)
    if (not self:isStarted()) and (not self._periodic) then
        return
    end
    self:_remove()
    self._periodic = false
    self._paused = false
    self:_dolink("onCancel")
end

-- set duration time (as with :start)
-- periodic is optional (if nil, doesn't change it)
-- if the timer is started, the timer gets restarted with the passed values
--  (this function restores the pause state when restarting)
function Timer:setDuration(duration, periodic)
    if self:isStarted() then
        local p = self:paused()
        self:start(duration, periodic)
        self:setPauses(p)
    else
        self._last_duration = duration
        self._periodic = ifnil(periodic, self._periodic)
    end
end

-- restart with last passed duration
-- if the Timer hasn't been started before (or setDuration() was called),
--  nothing happens
function Timer:restart()
    if not self._last_duration then
        return
    end
    self:start(self._last_duration, self._periodic)
end

-- if the Timer is active, make it inactive and set paused state
-- note that the pause state is reset and lost with :start() and :cancel()
function Timer:pause()
    if self._paused or not self._added then
        return
    end
    self._paused = true
    self._pause_time = currentTime()
    self:_remove()
    self:_dolink("onPauseState")
end

function Timer:paused()
    return self._paused
end
Timer.isPaused = Timer.paused -- grrr
function Timer:setPaused(state)
    if state then self:pause() else self:resume() end
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
    self:_dolink("onPauseState")
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

-- if timer is actually running (started and not paused)
function Timer:isActive()
    return self._added
end
-- if timer has been started (even if it is paused right now)
function Timer:isStarted()
    return self._added or self._paused
end

function Timer:_trigger()
    assert(not self._added)
    self:_dolink("onTrigger")
    if self.cb then
        self:cb()
    end
    if self._periodic and not self._added then
        self:restart()
    end
end

-- rather specialized function to hook all actions on this timer
-- link = arbitrary table, the following entries will be called if they exist:
--  link.onStart(link, timer): after the Timer has been started
--  link.onPauseState(link, timer): called after both pausing and resuming
--  link.onCancel(link, timer): Timer got stopped with Timer:cancel()
--  link.onTrigger(link, timer): Timer ellapsed; called before the user code
-- also, before of each of that callback, onUpdate(link, timer) is called
function Timer:setLink(link)
    assert(link)
    -- right now, only at most one link per instance
    -- feel free to extend it to more if you need
    assert(not self._link, "only up to 1 link per Timer")
    self._link = link
end

function Timer:_dolink(name)
    local link = self._link
    if not link then
        return
    end
    if link.onUpdate then
        link.onUpdate(link, self)
    end
    if link[name] then
        link[name](link, self)
    end
end

-- call cb() at the given relative time in the future
-- time is a relative Time
-- cb is an optional callback
-- returns a Timer with the time set
function addTimer(time, cb, periodic)
    local tr = Timer.new()
    tr:setCallback(cb)
    tr:start(time, periodic)
    return tr
end

function addPeriodicTimer(time, cb)
    return addTimer(time, cb, true)
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
    local always = addPeriodicTimer(timeSecs(0), function() c = c + 1 end)
    local always2 = addPeriodicTimer(timeSecs(-1), function() c2 = c2 + 1 end)
    local always3 = addPeriodicTimer(timeSecs(1), function() c3 = c3 + 1 end)
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
