//NOTE: keep this game independent; maybe it'll be useful for other stuff
module game.events;

import framework.lua;
import utils.hashtable;
import utils.misc;
import utils.mybox;

import traits = tango.core.Traits;

//framework.lua is missing stuff
import derelict.lua.lua;


class EventTarget {
    private {
        char[] mEventTargetType;
        //ID mEventTargetTypeID;
        Events mEvents, mPerClass, mPerInstance;
    }

    this(char[] type, Events global_events) {
        assert(!!global_events);
        mEvents = global_events;
        mEventTargetType = type;
        //mEventTargetTypeID = 0;
        mPerClass = mEvents.perClassEvents(mEventTargetType);
    }

    //for global event handlers
    final Events eventsBase() {
        return mEvents;
    }

    //for per-class event handlers; point to an Events instance shared across
    //  all objects of the same type
    final Events classLocalEvents() {
        return mPerClass;
    }

    //for per-instance event handlers; should be avoided if possible, because it
    //  causes lots of memory allocations per instance and event
    //is created on demand (to save memory, assuming it is seldomly used)
    final Events instanceLocalEvents() {
        if (!mPerInstance)
            mPerInstance = new Events();
        return mPerInstance;
    }

    final char[] eventTargetType() {
        return mEventTargetType;
    }

    final void raiseEvent(char[] name, EventPtr args) {
        if (mPerInstance)
            mPerInstance.raise(name, this, args);
        mPerClass.raise(name, this, args);
        mEvents.raise(name, this, args);
    }
}

//Events.handlerT() and Events.raiseT() use ParamStruct to wrap arguments into
//  EventPtr (although users of EventPtr are free to use any type)
//only wrap the tuple; if D had real tuples, I'd use those
struct ParamStruct(Args...) {
    Args args;
}

alias ParamStruct!() NoParams;

struct EventPtr {
    private {
        void* mPtr;
        TypeInfo mType;
    }

    //can be used by events which have no parameters
    static EventPtr Null;
    static this() {
        static NoParams foo;
        Null = EventPtr.Ptr(foo);
    }

    static EventPtr Ptr(T)(ref T event) {
        return EventPtr(&event, typeid(T));
    }

    T get(T)() {
        if (mType !is typeid(T))
            assert(false);
        return *cast(T*)mPtr;
    }

    TypeInfo type() { return mType; }
}

alias void delegate(EventTarget, EventPtr) EventHandler;
alias void delegate(char[], EventTarget, EventPtr) GenericEventHandler;
alias void function(ref EventEntry, EventTarget, EventPtr) DispatchEventHandler;

//marshal D -> Lua
//will call lua.luaCall(), passing the arguments stored in params
alias void function(LuaState lua, EventTarget sender, EventPtr params)
    Event_DtoScript;

//marshal Lua -> D
extern(C)
    alias int function(lua_State* lua, EventTarget target, char[] name)
        Event_ScriptToD;

private struct EventEntry {
    MyBox data;
    DispatchEventHandler handler;
}

private class EventType {
    char[] name;
    TypeInfo paramtype;
    EventEntry[] handlers;
    bool enable_script;
    Event_DtoScript marshal_d2s; //lazily initialized

    this() {}
}

//using RefHashTable because of dmd bug 3086
RefHashTable!(TypeInfo, Event_DtoScript) gEventsDtoScript;

Event_ScriptToD[char[]] gEventsScriptToD;

static this() {
    gEventsDtoScript = new typeof(gEventsDtoScript);
}

//basic idea: emulate virtual functions; just that:
//  1. you can add functions later without editing the root class
//  2. any class can hook into the events of a foreign class
//  3. magically support scripting (raising/handling events in scripts)
//consequences of the implementation...:
//  1. handlers are always registered to classes, never to instances
//  2. adding handlers is SLOW because of memory allocation
//
//also, either raiseT() or raise() should eventually be removed
final class Events {
    private {
        EventType[char[]] mEvents;

        LuaState mScripting;
        char[] mScriptingEventsNamespace;

        //hack
        Events[char[]] mPerClassEvents;
        char[] mTargetType;
    }

    //catch all events
    GenericEventHandler[] generic_handlers;
    //send all events to these objects as well
    Events[] cascade;

    this() {
    }

    //for Events that are for per-class handlers
    this(char[] target_type) {
        mTargetType = target_type;
    }

    //this is a hack insofar, that only the global Events instance should have
    //  this method, and it doesn't really make sense for per-class Events
    //  instances
    final Events perClassEvents(char[] target_type) {
        auto pevents = target_type in mPerClassEvents;
        if (pevents)
            return *pevents;
        auto ev = new Events(target_type);
        mPerClassEvents[target_type] = ev;
        if (mScripting)
            subevents_init_scripting(ev);
        return ev;
    }

    private void subevents_init_scripting(Events ev) {
        assert(!!mScripting);
        ev.setScripting(mScripting, mScriptingEventsNamespace ~ "_"
            ~ ev.mTargetType);
    }

    //xxx shitty performance hack
    private char[] nullTerminate(char[] s) {
        return (s~'\0')[0..$-1];
    }

    //this is also a method which should only exist for the global Events object
    void setScripting(LuaState lua, char[] namespace) {
        mScripting = lua;
        mScriptingEventsNamespace = nullTerminate(namespace);
        mScripting.scriptExec(`
                local namespace = ...
                assert(not _G[namespace])
                _G[namespace] = {}
            `, mScriptingEventsNamespace);
        //xxx make independent from raw Lua API etc....
        lua_State* state = lua.state();
        //--lua.stack0();
        lua_pushcfunction(state, &scriptEventsRaise);
        lua_setglobal(state, (cEventsRaiseFunction ~ '\0').ptr);
        //--lua.stack0();

        foreach (Events sub; mPerClassEvents) {
            subevents_init_scripting(sub);
        }
    }

    char[] scriptingEventsNamespace() {
        return mScriptingEventsNamespace;
    }

    void genericHandler(GenericEventHandler h) {
        generic_handlers ~= h;
    }

    private EventType get_event(char[] name) {
        auto pevent = name in mEvents;
        if (pevent)
            return *pevent;
        auto e = new EventType;
        e.name = nullTerminate(name);
        mEvents[e.name] = e;
        return e;
    }

    private void do_reg_handler(char[] event, TypeInfo paramtype,
        EventEntry a_handler)
    {
        EventType e = get_event(event);
        if (e.paramtype && e.paramtype !is paramtype)
            assert(false, "handlers for same event with different parameters");
        e.paramtype = paramtype;
        e.handlers ~= a_handler;
    }

    private static void handler_generic(ref EventEntry from, EventTarget sender,
        EventPtr params)
    {
        EventHandler h = from.data.unbox!(EventHandler)();
        h(sender, params);
    }

    //event = event name (e.g. "ondamage")
    //paramtype is needed for script->D events (what type to demarshal)
    void handler(char[] event, TypeInfo paramtype, EventHandler a_handler) {
        EventEntry e;
        e.data.box!(EventHandler)(a_handler);
        e.handler = &handler_generic;
        do_reg_handler(event, paramtype, e);
    }

    //relatively inflexible "backend" function:
    //if event happens, lookup the global variable namespace (must give a
    //  table), and then call the entry named event in the table
    //the namespace gets set with setScripting()
    //there can be only one such handler (globally), and scripting uses it to
    //  implement its own event dispatch mechanism (there needs to be only a
    //  single D->scripting function as bridge)
    void enableScriptHandler(char[] event, bool enable) {
        assert(!!mScripting);
        get_event(event).enable_script = enable;
    }

    private void raise_to_script(EventType ev, EventTarget sender,
        EventPtr params)
    {
        if (!ev.enable_script)
            return;
        if (!ev.marshal_d2s) {
            ev.marshal_d2s = gEventsDtoScript[params.type];
        }
        //xxx optimize by not using string lookups (use luaL_ref())
        //also xxx try to abstract the lua specific parts
        lua_State* state = mScripting.state();
        //not stack0() if called from Lua script (calls back)
        //mScripting.stack0();
        lua_getglobal(state, mScriptingEventsNamespace.ptr);
        lua_getfield(state, -1, ev.name.ptr);
        ev.marshal_d2s(mScripting, sender, params);
        lua_pop(state, 1);
        //mScripting.stack0();
    }

    //one should prefer EventTarget.raiseEvent()
    void raise(char[] event, EventTarget sender, EventPtr params) {
        //char[] target = sender.eventTargetType();
        EventType e = get_event(event);
        foreach (ref h; e.handlers) {
            h.handler(h, sender, params);
        }

        foreach (h; generic_handlers) {
            h(event, sender, params);
        }

        raise_to_script(e, sender, params);

        foreach (Events c; cascade) {
            c.raise(event, sender, params);
        }
    }
}


//template metabloat for auto-generating script bindings
//they instantiate template code for script bindings, and register it in global
//  AAs to map typeid(T) -> marshal code
void paramType(T)() {
    paramTypeIn!(T)();
    paramTypeOut!(T)();
}

private template GetArgs(T) {
    static assert(is(T == struct));
    //behave in the same way handlerT uses .tupleof
    //is having to use typeof() a bug or a feature?
    alias typeof(T.tupleof) GetArgs;
}

//D -> script
void paramTypeOut(ParamType)() {
    alias GetArgs!(ParamType) Args;

    static void callScript(LuaState lua, EventTarget sender, EventPtr params) {
        auto args = params.get!(ParamType)();
        lua.luaCall!(void, Object, Args)(sender, args.tupleof);
    }

    gEventsDtoScript[typeid(ParamType)] = &callScript;
}

//script -> D
void paramTypeIn(T)(char[] event) {
    alias GetArgs!(T) Args;

    extern(C) static int demarshal(lua_State* state, EventTarget target,
        char[] name)
    {
        void callFromScript(Args args) {
            //xxx code duplication from DeclareEvent.raise... but then again,
            //  this stuff is trivial, and all actual code is in raiseEvent
            assert(!!target);
            ParamStruct!(Args) args2;
            //dmd bug 3614?
            static if (Args.length)
                args2.args = args;
            auto argsptr = EventPtr.Ptr(args2);
            target.raiseEvent(name, argsptr);
        }

        return callFromLua(&callFromScript, state, 2, cEventsRaiseFunction);
    }

    gEventsScriptToD[event] = &demarshal;
}

const char[] cEventsRaiseFunction = "d_events_raise";

//in Lua: d_events_raise(target, name, ...)
extern(C) private int scriptEventsRaise(lua_State* state) {
    //xxx should be handled like a this pointer for method calls
    EventTarget target = luaStackValue!(EventTarget)(state, 1);
    if (!target)
        raiseLuaError(state, "event target is null");
    char[] event = luaStackValue!(char[])(state, 2);
    //xxx this is awkward and slow too
    //  main problem is that all events in the program with same name must
    //  have the same argument types (even for completely unrelated parts of
    //  the program)
    Event_ScriptToD* demarshal = event in gEventsScriptToD;
    if (!demarshal) {
        //raiseLuaError(state, "no demarshaller for event: " ~ event);
        //DeclareEvent.handler() wasn't called yet => no demarshaller
        //could be an unknown event as well
        return 0;
    }
    return (*demarshal)(state, target, event);
}

//weird way to "declare" and events globally
//this checks event parameter types at compile time
//xxx would be nice as struct too, but I get forward reference errors
//xxx 2 the name will add major symbol name bloat, argh.
template DeclareEvent(char[] name, SenderBase, Args...) {
    static assert(is(SenderBase : EventTarget));
    alias void delegate(SenderBase, Args) Handler;
    alias ParamStruct!(Args) ParamType;
    alias name Name;

    //relies on the compiler doing proper name-mangling
    //(if that goes wrong, anything could happen)
    static bool mInRegged, mOutRegged;

    static void handler(Events base, Handler a_handler) {
        if (!mInRegged) {
            mInRegged = true;
            paramTypeIn!(ParamType)(name);
        }

        EventEntry e;
        e.data.box!(Handler)(a_handler);
        e.handler = &handler_templated;
        base.do_reg_handler(name, typeid(ParamType), e);
    }

    static void raise(SenderBase sender, Args args) {
        if (!mOutRegged) {
            mOutRegged = true;
            paramTypeOut!(ParamType)();
        }

        assert(!!sender);
        ParamType args2;
        //dmd bug 3614?
        static if (Args.length)
            args2.args = args;
        auto argsptr = EventPtr.Ptr(args2);
        sender.raiseEvent(name, argsptr);
    }

    private static void handler_templated(ref EventEntry from,
        EventTarget sender, EventPtr params)
    {
        assert(!!sender);
        auto sender2 = cast(SenderBase)sender;
        assert(!!sender2);
        auto h = from.data.unbox!(Handler)();
        auto args = params.get!(ParamType)();
        h(sender2, args.tupleof);
    }
}

alias DeclareEvent!("some_event", EventTarget, int, bool) SomeEvent;

unittest {
    int i;
    bool b;
    auto xd = {SomeEvent.raise(null, i, b);};
}

/+
//stupid "optimization"

alias size_t ID; //always >0 (0 means invalid)
class Atoms {
    private {
        ID[char[]] mAtoms;
        ID mIDAlloc;
    }

    ID get(char[] s) {
        if (auto p = s in mAtoms) {
            return *p;
        }
        auto nid = ++mIDAlloc;
        mAtoms[s] = nid;
        return nid;
    }

    char[] lookup(ID id) {
        return mAtoms[id];
    }
}
+/
