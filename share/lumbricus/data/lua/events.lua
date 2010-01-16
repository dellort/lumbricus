-- event handler in conjunction with events.d

-- this table is used implicitly by the D code for all global event handlers
-- D calls eventhandlers_global["event name"](sender, args...)
-- but only if Events_enableScriptHandler has been called for the event name
-- it is always created automatically
-- eventhandlers_global = {}

EventHandlerMeta = {
    __call = function(self, ...)
        for i, h in ipairs(self) do
            h(...)
        end
    end
}

function do_addEventHandler(events, event_name, handler)
    local ns_name = Events_scriptingEventsNamespace(events)
    local ns = _G[ns_name]
    assert(ns)
    local ghandler = ns[event_name]
    if not ghandler then
        ghandler = {}
        setmetatable(ghandler, EventHandlerMeta)
        ns[event_name] = ghandler
        Events_enableScriptHandler(events, event_name, true)
    end
    ghandler[#ghandler + 1] = handler
end

function addGlobalEventHandler(event_name, handler)
    do_addEventHandler(Game_events(), event_name, handler)
end

function addPerClassEventHandler(class_name, event_name, handler)
    local events = Events_perClassEvents(Game_events(), class_name)
    do_addEventHandler(events, event_name, handler)
end

-- internally used by addInstanceEventHandler()
_perInstanceDispatchers = {}

-- object = a D EventTarget object
-- event_name = same as in the other functions
-- handler = lua callable: handler(object, ...)
-- xxx think of better name
-- also needs get_context() from gameutils.lua
function addInstanceEventHandler(object, event_name, handler)
    -- there's one per-instance dispatcher per (target-type, event_name)
    -- this handler uses get_context() to get locally registered event handlers

    -- register the per-class handler
    local ns = EventTarget_eventTargetType(object)
    local cls = _perInstanceDispatchers[ns]
    if not cls then
        cls = {}
        _perInstanceDispatchers[ns] = cls
    end
    if not cls[event_name] then
        cls[event_name] = true
        addPerClassEventHandler(ns, event_name,
            -- this is the per-instance dispatch function
            function(sender, ...)
                local ctx = get_context(sender, true)
                if not ctx then return end
                local ev = ctx._events
                if not ev then return end
                local handlers = ev[event_name]
                if not handlers then return end
                for i, h in ipairs(handlers) do
                    h(sender, ...)
                end
            end
        )
    end

    -- register the per-instance handler
    local ctx = get_context(object)
    local ev = ctx._events
    if not ev then
        ev = {}
        ctx._events = ev
    end
    local handlers = ev[event_name]
    if not handlers then
        handlers = {}
        ev[event_name] = handlers
    end
    handlers[#handlers + 1] = handler
end

-- target must be a D EventTarget
-- name is the event name
function raiseEvent(target, name, ...)
    d_events_raise(target, name, ...)
end

testCounter = 0

function eventtest()
    local function on_message(sender, msg)
        printf("message: {}", msg)
    end
    local function on_message2(sender, msg)
        printf("message, 2nd handler: {}", msg)
    end
    local function on_bazooka_activate(sender)
        testCounter = testCounter + 1
        local ctx = get_context(sender)
        ctx.meep = testCounter
        printf("bazooka {} got fired at {}!", ctx.meep,
            Phys_pos(Sprite_physics(sender)))
        local c = testCounter
        local function test(sender)
            printf("die event from {}", c)
        end
        addInstanceEventHandler(sender, "sprite_die", test)
    end
    local function on_bazooka_die(sender)
        local ctx = get_context(sender)
        printf("bazooka {} died at {}!", ctx.meep,
            Phys_pos(Sprite_physics(sender)))
    end
    addGlobalEventHandler("game_message", on_message)
    addGlobalEventHandler("game_message", on_message2)
    addPerClassEventHandler("bazooka", "sprite_activate", on_bazooka_activate)
    addPerClassEventHandler("bazooka", "sprite_die", on_bazooka_die)
end
