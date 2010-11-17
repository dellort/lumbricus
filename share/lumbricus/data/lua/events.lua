-- event handler in conjunction with events.d

-- used global variables magically created by D:
-- some methods of class Events and class EventTarget
-- d_event_marshallers

-- this is just for reducing the number of D->Lua transitions on events
-- instead of registering each Lua handler in D, only one Lua handler is
--  registered per event type, and that handler calls all other Lua handlers
-- xxx check if this is an useless optimization
local eventhandlers = {}

local function do_addEventHandler(events, event_name, handler)
    assert(handler)
    T(Events, events)
    -- garbage collection: keep each "events" instance forever, assuming there's
    --  a bounded number of event instances per game
    local ns = eventhandlers[events]
    if not ns then
        ns = {}
        eventhandlers[events] = ns
    end
    local ghandlers = ns[event_name]
    if not ghandlers then
        ghandlers = {}

        local function dispatcher(...)
            -- NOTE: we could try to deal with failing event handlers
            --  but that's probably not worth the slow down & complexity
            for i, event_handler in ipairs(ghandlers) do
                event_handler(...)
            end
        end

        -- this indirection is needed because D is statically typed
        -- the type of the register function depends on event_name
        -- to get around the static type system, the actual function is created
        -- and Lua-registered somewhere in a D template
        local s = events:scriptGetMarshallers(event_name)
        d_event_marshallers[s].register(events, event_name, dispatcher)
    end
    ghandlers[#ghandlers + 1] = handler
end

function addGlobalEventHandler(event_name, handler)
    do_addEventHandler(Game:events(), event_name, handler)
end

function addClassEventHandler(class_name, event_name, handler)
    local events = Game:events():perClassEvents(class_name)
    do_addEventHandler(events, event_name, handler)
end

-- internally used by addInstanceEventHandler()
local _perInstanceDispatchers = {}

-- object = a D EventTarget object
-- event_name = same as in the other functions
-- handler = lua callable: handler(object, ...)
-- xxx think of better name
-- also needs get_context() from gameutils.lua
function addInstanceEventHandler(object, event_name, handler)
    -- there's one per-instance dispatcher per (target-type, event_name)
    -- this handler uses get_context() to get locally registered event handlers

    T(EventTarget, object)

    -- register the per-class handler
    local ns = object:eventTargetType()
    local cls = _perInstanceDispatchers[ns]
    if not cls then
        cls = {}
        _perInstanceDispatchers[ns] = cls
    end
    if not cls[event_name] then
        cls[event_name] = true
        addClassEventHandler(ns, event_name,
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

-- undo addInstanceEventHandler - this is even more expensive
-- Note: if objects die, the event handlers will be removed automatically
-- Note 2: both automatic and manual removal will leave possibly useful global
--  event handlers installed
function removeInstanceEventHandler(object, event_name, handler)
    local ctx = get_context(object, true)
    local ev = ctx and ctx._events
    local handlers = ev and ev[event_name]
    if handlers then
        --array.remove_value(handlers, handler)
        --^ doesn't work, should be able to remove events while they're handled
        --so, copy the handlers array
        handlers2 = array.copy(handlers)
        array.remove_value(handlers2, handler)
        ev[event_name] = handlers2
    end
end

-- cached
local raise_fns = {}

-- target must be a D EventTarget
-- event_name a string
function raiseEvent(target, event_name, ...)
    local fn = raise_fns[event_name]
    if not fn then
        local s = Game:events():scriptGetMarshallers(event_name)
        fn = d_event_marshallers[s].raise
        assert(fn)
        raise_fns[event_name] = fn
    end
    fn(target, event_name, ...)
end

function raiseGlobalEvent(event_name, ...)
    raiseEvent(Game:events():globalDummy(), event_name, ...)
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
            Phys.pos(Sprite.physics(sender)))
        local c = testCounter
        local function test(sender)
            printf("die event from {}", c)
        end
        addInstanceEventHandler(sender, "sprite_die", test)
    end
    local function on_bazooka_die(sender)
        local ctx = get_context(sender)
        printf("bazooka {} died at {}!", ctx.meep,
            Phys.pos(Sprite.physics(sender)))
    end
    --addGlobalEventHandler("game_message", on_message)
    --addGlobalEventHandler("game_message", on_message2)
    addClassEventHandler("x_bazooka", "sprite_activate", on_bazooka_activate)
    addClassEventHandler("x_bazooka", "sprite_die", on_bazooka_die)
    --raiseGlobalEvent("game_message", { lm = { id = "blabla" } })
    --raiseGlobalEvent("game_message", { lm = { id = "bla" } })
end
