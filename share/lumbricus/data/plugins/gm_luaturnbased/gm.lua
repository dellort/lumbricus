local hud_status
local hud_prepare
local teams -- return of Control:teams()
local pteams -- like teams, but teamperm applied
local teamperm -- integer array for team permutation

local turnTime = Timer.New()
local prepareTime = Timer.New()
local suddenDeathTime = Timer.New()
local currentTeam
local lastTeam = nil
local turnCounter = 0 -- was mRoundCounter

local stateMachine -- StateMachine instance

-- called every second (see doinit) and whenever it may be necessary
local function updateTimers()
    local turn_t = turnTime:timeLeft()
    TimeStatus_set_showTurnTime(hud_status, not not turn_t)
    if turn_t then
        TimeStatus_set_turnRemaining(hud_status, turn_t)
        TimeStatus_set_timePaused(hud_status, turnTime:isPaused())
    end
    local prep_t = prepareTime:timeLeft()
    PrepareStatus_set_visible(hud_prepare, not not prep_t)
    if prep_t then
        PrepareStatus_set_prepareRemaining(hud_prepare, prep_t)
    end
end

-- return number_of_alive_teams, first_alive_team
local function aliveTeams()
    local cnt, alive = 0, nil
    for i, t in ipairs(teams) do
        if Team.alive(t) then
            cnt = cnt + 1
            alive = t
        end
    end
    return cnt, alive
end

local function setCurrent(team)
    if currentTeam then
        Team.set_active(currentTeam, false)
        lastTeam = currentTeam
    end
    currentTeam = nil
    if team then
        currentTeam = team
        Team.set_active(currentTeam, true)
    end
end

local function findNextTeam(team)
    if not team then
        -- game has just started, select first team (round-robin)
        return pteams[((Control:currentRound() - 1) % #pteams) + 1]
    end
    -- select next team/worm
    local from = array.indexof(pteams, team)
    local arr = array.rotated(pteams, from + 1)
    for _, v in ipairs(arr) do
        if Team.alive(v) then
            return v
        end
    end
    -- nothing found
    return nil
end

-- most of the game mode is handled via a state machine (coroutines would be
--  nice too, but event handling would be messy)

local StateEnterLeave = {} -- marker metatable
local StateEvent = {}

-- t can contain:
-- - an item named "enter": a function called on state entry
-- - items that are StateTimer (created by ptimer() / timer())
local function state(t)
    function t:setState(state)
        setState(state)
    end
    -- this just fills onevent and enter/leave for more convenient usage
    t.on_event = {}
    t.on_enter = {}
    t.on_leave = {}
    for k, v in pairs(table_copy(t)) do
        if type(v) == "table" then
            local m = getmetatable(v)
            if m == StateEnterLeave then
                array.append(t.on_enter, v.enter)
                array.append(t.on_leave, v.leave)
            elseif m == StateEvent then
                t.on_event[v.name] = v
            end
        end
    end
    t.on_leave = array.reversed(t.on_leave)
    return t
end

-- state machine one-shot timer
-- periodic = optional, boolean whether it's periodic
local function timer(duration, cb, periodic)
    local t = Timer.New()
    local sm -- meh, it's set in enter; this is rather fishy
    t:setCallback(function()
        assert(sm)
        sm:callStateFn(cb)
    end)
    return setmetatable({
        timer = t,
        enter = function(s)
            sm = s._sm
            t:start(duration, periodic)
        end,
        leave = function(s)
            t:cancel()
        end,
    }, StateEnterLeave)
end

-- state machine periodic timer
local function ptimer(time, cb)
    return timer(time, cb, true)
end

-- state machine event handler
-- note that events are feeded to the state machine manually (i.e. doesn't use
--  events.lua stuff automatically)
local function event(name, cb)
    return setmetatable({
        name = name,
        cb = cb,
    }, StateEvent)
end

StateMachine = {}
StateMachine.__index = StateMachine

function StateMachine.New()
    return setmetatable({
        _state = nil,
    }, StateMachine)
end

function StateMachine:setState(state)
    -- same state => ignore
    if self._state == state then
        return
    end
    -- leave handlers
    if self._state then
        local s = self._state
        for i, v in ipairs(s.on_leave) do
            v(s)
        end
        if s.leave then
            s:leave()
        end
    end
    self._state = state
    -- printf("setState {}", tostring(state))
    if not state then
        return
    end
    state._sm = self -- ultrashitty hack
    -- main enter handler (allowed to change the state)
    local enter = state.enter
    if enter then
        -- xxx may lead to stack overflow (except if it eliminates tail calls)
        -- like callStateFn
        local res = enter(state)
        if res and (res ~= state) then
            self:setState(res)
            return
        end
    end
    -- normal enter handlers
    for i, v in ipairs(state.on_enter) do
        v(state)
    end
end

-- calls fn(state, ...), using the return value to possibly change the state
-- all state callbacks should be called like this
function StateMachine:callStateFn(fn, ...)
    local res = fn(self._state, ...)
    if res then
        self:setState(res)
    end
end

-- call event handler
-- return boolean whether an event handler was actually called
function StateMachine:deliverEvent(event, ...)
    local h = self._state.on_event[event]
    if not h then
        return false
    end
    self:callStateFn(h.cb, ...)
    return true
end

-- game mode specific state machine declarations

local states = {}

states.waitForSilence = state {
    enter = function(s)
        -- no control while blowing up worms
        if currentTeam then
            local current = Team.current(currentTeam)
            if current then
                WormControl.forceAbort(Member.control(current))
            end
            Team.setOnHold(currentTeam, true)
            setCurrent(nil)
        end
    end,
    ptimer(time("400ms"), function(s)
        if not Game:checkForActivity() then
            return states.cleaningUp
        end
    end),
}

states.cleaningUp = state {
    enter = function(s)
        Control:updateHealth()
    end,
    ptimer(time("750ms"), function(s)
        -- if there are more to blow up, go back to waiting
        if Control:checkDyingWorms() then
            return states.waitForSilence
        end
        -- check if at least two teams are alive (=> round can go on)
        local nalive, team = aliveTeams()
        if nalive < 2 then
            if nalive > 0 then
                Team.youWinNow(team)
                return states.winning
            else
                return states.roundEnd --was end
            end
        end
        -- xxx missing:
        -- - drop crate
        -- - sudden death
        return states.nextOnHold
    end),
}

states.nextOnHold = state {
    enter = function(s)
        currentTeam = nil
        Game:randomizeWind()
    end,
    ptimer(time("100ms"), function(s)
        if Control:isIdle() then
            return states.prepare
        end
    end),
}

states.prepare = state {
    enter = function(s)
        setCurrent(findNextTeam(lastTeam))
        prepareTime:start(time(5))
        -- xxx: allowSelect, crates
    end,
    leave = function(s)
        prepareTime:cancel()
    end,
    timer(time("5s"), function(s)
        return states.playing
    end),
    event("first_action", function(s, team)
        return states.playing
    end),
}

states.playing = state {
    enter = function(s)
        turnCounter = turnCounter + 1
        turnTime:start(time(30))
        Team.setOnHold(currentTeam, false)
    end,
    leave = function(s)
        turnTime:cancel()
    end,
    -- check for silence every 500ms
    ptimer(time("500ms"), function(s)
        -- xxx delayedAction?
    end),
    event("lost_control", function(s, member)
        return states.waitForSilence
    end),
    timer(time("30s"), function(s)
        -- delayedAction?
        return states.waitForSilence
    end),
}

states.winning = state {
    enter = function(s) end,
    timer(time("5s"), function(s)
        return states.roundEnd
    end),
}

states.roundEnd = state {
    enter = function(s)
        setCurrent(nil)
        Control:endGame()
    end,
}

local function doinit()
    if CratePlugin:addCrateTool then
        CratePlugin:addCrateTool("doubletime")
    end

    teams = Control:teams()

    -- we want teams to be activated in a random order that stays the same
    --  over all rounds
    -- Note that the teamperm indices are 0-based
    -- xxx error handling (but I think it's ok when the plugin "crashes")
    local pers = Game:persistentState()
    teamperm = array.map(ConfigNode.getArray(pers, "team_order"), tonumber)
    if #teamperm ~= #teams then
        -- either the game just started, or a player left -> new random order
        teamperm = {}
        for i, t in ipairs(teams) do
            teamperm[i] = i - 1
        end
        array.randomize_inplace(teamperm)
        ConfigNode.setArray(pers, "team_order", array.map(teamperm, tostring))
    end
    pteams = {}
    for k, i in ipairs(teamperm) do
        pteams[k] = teams[i+1]
    end

    --printf("teamperm: {}", teamperm)

    hud_status = TimeStatus_ctor()
    hud_prepare = PrepareStatus_ctor()
    raiseEvent(Game_globalEvents(), "game_hud_add", "timer", hud_status)
    raiseEvent(Game_globalEvents(), "game_hud_add", "prepare", hud_prepare)

    stateMachine = StateMachine.New()
    stateMachine:setState(states.waitForSilence)

    addPeriodicTimer(time("1s"), updateTimers)
end

addGlobalEventHandler("game_start", doinit)

local doubletime_class = d_find_class("CollectableToolDoubleTime")

addGlobalEventHandler("collect_tool", function(member, tool)
    if d_is_class(tool, doubletime_class) then
        printf("Double time collected!")
    end
end)

addGlobalEventHandler("team_on_first_action", function(team)
    stateMachine:deliverEvent("first_action", team)
end)

addGlobalEventHandler("team_member_on_lost_control", function(member)
    stateMachine:deliverEvent("lost_control", member)
end)
