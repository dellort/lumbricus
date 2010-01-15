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
        Events_enableScriptHandler(events, event_name)
    end
    ghandler[#ghandler + 1] = handler
end

function addGlobalEventHandler(event_name, handler)
    do_addEventHandler(Game_events(), event_name, handler)
end

function addPerClassEventHandler(class_name, event_name, handler)
    local spriteclass = Gfx_findSpriteClass(class_name)
    local events = SpriteClass_getEvents(spriteclass, Game)
    do_addEventHandler(events, event_name, handler)
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
        local ctx = testCounter
        set_context(sender, ctx)
        printf("bazooka {} got fired at {}!", ctx,
            Phys_pos(Sprite_physics(sender)))
    end
    local function on_bazooka_die(sender)
        local ctx = get_context(sender)
        printf("bazooka {} died at {}!", ctx, Phys_pos(Sprite_physics(sender)))
    end
    addGlobalEventHandler("game_message", on_message)
    addGlobalEventHandler("game_message", on_message2)
    addPerClassEventHandler("bazooka", "sprite_activate", on_bazooka_activate)
    addPerClassEventHandler("bazooka", "sprite_die", on_bazooka_die)
end
