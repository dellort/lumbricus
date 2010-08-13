//NOTE: keep this game independent; maybe it'll be useful for other stuff
module game.events;

import framework.lua;
import utils.array;
import utils.misc;
import utils.mybox;

import traits = tango.core.Traits;


class EventTarget {
    private {
        char[] mEventTargetType;
        //ID mEventTargetTypeID;
        Events mEvents, mPerClass, mPerInstance;
    }

    this(char[] type, Events global_events) {
        assert(!!global_events);
        mEvents = global_events;
        resetEventType(type);
    }

    void resetEventType(char[] n) {
        mEventTargetType = n;
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
            mPerInstance = new Events(mEvents);
        return mPerInstance;
    }

    final char[] eventTargetType() {
        return mEventTargetType;
    }

    final void raiseEvent(char[] name, EventPtr args) {
        raiseEvent(Atoms.get(name), args);
    }
    //backend function
    final void raiseEvent(ID eventID, EventPtr args) {
        if (mPerInstance)
            mPerInstance.raise(eventID, this, args);
        mPerClass.raise(eventID, this, args);
        mEvents.raise(eventID, this, args);
    }
}

//Events.handler() and Events.raise() use ParamStruct to wrap arguments into
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
alias void function(ref EventEntry, EventTarget, EventPtr) DispatchEventHandler;

private struct EventEntry {
    MyBox data;
    DispatchEventHandler handler;
}

private class EventType {
    char[] name;
    TypeInfo paramtype;
    EventEntry[] handlers;
    EventEntry[] unreg_list;

    this() {}
}

//create marshaller for D <-> Lua event transport
private alias char[] function(LuaState lua) RegisterMarshaller;

//indexed by event name (it "should" be indexed by event type [i.e. the type of
//  the parameters, for marshalling], but Lua can't know the event argument
//  types)
RegisterMarshaller[char[]] gEventMarshallers;

/+
//have to register the marshallers as the scripting state is created
//this will create Lua closures and store them into the Lua state
void function(LuaState)[] gRegisterEventMarshallers;
+/

//basic idea: emulate virtual functions; just that:
//  1. you can add functions later without editing the root class
//  2. any class can hook into the events of a foreign class
//  3. magically support scripting (raising/handling events in scripts)
//consequences of the implementation...:
//  1. handlers are always registered to classes, never to instances
//  2. adding handlers is SLOW because of memory allocation
final class Events {
    private {
        //indexed by EventType e; mEvents[Atoms.get(e.name)]
        EventType[] mEvents;

        LuaState mScripting;

        //hack
        Events[char[]] mPerClassEvents;
        char[] mTargetType;
        Events mParent;

        //also a hack, referenced by DeclareGlobalEvent
        EventTarget mGlobalEvents;
        //another hack
        bool mLazyRemove;
    }

    this(Events parent = null) {
        mParent = parent;
        if (!parent)
            mGlobalEvents = new EventTarget("global", this);
    }

    //for Events that are for per-class handlers
    this(char[] target_type, Events parent = null) {
        mParent = parent;
        mTargetType = target_type;
    }

    //this is a hack insofar, that only the global Events instance should have
    //  this method, and it doesn't really make sense for per-class Events
    //  instances
    final Events perClassEvents(char[] target_type) {
        auto pevents = target_type in mPerClassEvents;
        if (pevents)
            return *pevents;
        auto ev = new Events(target_type, this);
        mPerClassEvents[ev.mTargetType] = ev;
        if (mScripting)
            subevents_init_scripting(ev);
        return ev;
    }

    private void subevents_init_scripting(Events ev) {
        assert(!!mScripting);
        ev.setScripting(mScripting);
    }

    //this is also a method which should only exist for the global Events object
    void setScripting(LuaState lua) {
        mScripting = lua;

        foreach (Events sub; mPerClassEvents) {
            subevents_init_scripting(sub);
        }
    }

    char[] scriptGetMarshallers(char[] event_name) {
        if (!mScripting)
            throw new CustomException("script trying to access unscripted "
                "Events instance");
        auto pf = event_name in gEventMarshallers;
        argcheck(!!pf, "unknown event: " ~ event_name);
        return (*pf)(mScripting);
    }

    EventTarget globalDummy() {
        return mGlobalEvents;
    }

    private EventType get_event(char[] name) {
        ID id = Atoms.get(name);
        if (id >= mEvents.length)
            mEvents.length = id + 1;
        if (auto event = mEvents[id])
            return event;
        auto e = new EventType;
        e.name = name;
        mEvents[id] = e;
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

    private void do_unreg_handler(char[] event, EventEntry a_handler) {
        EventType e = get_event(event);
        if (mLazyRemove) {
            //unreg called from raise(), remove later
            e.unreg_list ~= a_handler;
        } else {
            arrayRemove(e.handlers, a_handler, true);
        }
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

    //one should prefer EventTarget.raiseEvent()
    void raise(char[] event, EventTarget sender, EventPtr params) {
        raise(Atoms.get(event), sender, params);
    }
    //backend function
    void raise(ID eventID, EventTarget sender, EventPtr params) {
        EventType e = eventID < mEvents.length ? mEvents[eventID] : null;
        //if e doesn't exist, there can't be an event handler anyway
        if (e) {
            mLazyRemove = true;
            foreach (ref h; e.handlers) {
                h.handler(h, sender, params);
            }
            foreach (ref h; e.unreg_list) {
                arrayRemove(e.handlers, h, true);
            }
            e.unreg_list = null;
            mLazyRemove = false;
        }
    }
}


//template metabloat for auto-generating script bindings

private template GetArgs(T) {
    static assert(is(T == struct));
    //behave in the same way handlerT uses .tupleof
    //is having to use typeof() a bug or a feature?
    alias typeof(T.tupleof) GetArgs;
}

//D <-> script marshallers
void paramType(ParamType)(char[] event_name) {
    alias GetArgs!(ParamType) Args;
    alias void delegate(EventTarget, Args) Handler;

    //D -> script
    //xxx code duplication from DeclareEvent.handler

    static void handler_templated(ref EventEntry from,
        EventTarget sender, EventPtr params)
    {
        auto h = from.data.unbox!(Handler)();
        auto args = params.get!(ParamType)();
        h(sender, args.tupleof);
    }

    static void register(Events base, char[] name, Handler a_handler) {
        EventEntry e;
        e.data.box!(Handler)(a_handler);
        e.handler = &handler_templated;
        base.do_reg_handler(name, typeid(ParamType), e);
    }

    //script -> D
    //xxx code duplication from DeclareEvent.raise

    static void raise(EventTarget target, char[] name, Args args) {
        argcheck(target);
        ParamType args2 = ParamType(args);
        auto argsptr = EventPtr.Ptr(args2);
        target.raiseEvent(name, argsptr);
    }

    //register both

    //mangleof is the simplest way to get an unique name
    const char[] c_name = ParamType.mangleof;

    static char[] register_marshallers(LuaState lua) {
        lua.scriptExec(`
                local name, register, raise = ...
                if not d_event_marshallers then
                    _G.d_event_marshallers = {}
                end
                d_event_marshallers[name] = {
                    register = register,
                    raise = raise,
                }
            `, c_name, &register, &raise);
        return c_name;
    }

    //failure means there are multiple events with same name (unsupported)
    assert(!(event_name in gEventMarshallers));
    gEventMarshallers[event_name] = &register_marshallers;
}

//weird way to "declare" and events globally
//this checks event parameter types at compile time
//xxx would be nice as struct too, but I get forward reference errors
//xxx 2 the name will add major symbol name bloat, argh.
class DeclareEvent(char[] name, SenderBase, Args...) {
//fuck, this crap doesn't work at all anymore!
//dmd bugzilla 4033 (but why did it work before?)
//    static assert(is(SenderBase : EventTarget));
    alias void delegate(SenderBase, Args) Handler;
    alias ParamStruct!(Args) ParamType;
    alias name Name;

    //static variables & static this rely on the compiler doing proper
    //  name-mangling to make them unique across the program
    //(if that goes wrong, anything could happen)

    //cached name->ID lookup
    static ID mEventID;

    static this() {
        paramType!(ParamType)(name);
        mEventID = Atoms.get(Name);
    }

    static void handler(Events base, Handler a_handler) {
        EventEntry e;
        e.data.box!(Handler)(a_handler);
        e.handler = &handler_templated;
        base.do_reg_handler(name, typeid(ParamType), e);
    }

    static void remove_handler(Events base, Handler a_handler) {
        EventEntry e;
        e.data.box!(Handler)(a_handler);
        e.handler = &handler_templated;
        base.do_unreg_handler(name, e);
    }

    static void raise(SenderBase sender, Args args) {
        static assert(is(SenderBase : EventTarget));

        assert(!!sender);
        ParamType args2 = ParamType(args);
        auto argsptr = EventPtr.Ptr(args2);
        sender.raiseEvent(mEventID, argsptr);
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

//for now just a wrapper... actually we'd just need an array of delegates for
//  each event-type/GameEngine plus something to register an add-event-handler
//  function for scripting (that handler can be a normal D function, that takes
//  an event handler delegate as parameter) - I want to simplify it once I
//  manage to make up my mind
class DeclareGlobalEvent(char[] name, Args...) {
    alias void delegate(EventTarget, Args) Handler;
    alias void delegate(Args) Handler2;
    alias DeclareEvent!(name, EventTarget, Args) Event;

    static void handler(Events base, Handler2 a_handler) {
        //closure removes the EventTarget from the function signature
        //could remove this in D2
        struct Closure {
            Handler2 handler;
            void call(EventTarget t, Args args) {
                handler(args);
            }
        }
        auto c = new Closure;
        c.handler = a_handler;
        Event.handler(base, &c.call);
    }

    static void raise(Events base, Args args) {
        auto ev = base.mGlobalEvents;
        assert(!!ev);
        Event.raise(ev, args);
    }
}

alias DeclareEvent!("some_event", EventTarget, int, bool) SomeEvent;

unittest {
    int i;
    bool b;
    auto xd = {SomeEvent.raise(null, i, b);};
}

//stupid "optimization"

alias size_t ID; //always >0 (0 means invalid)
class Atoms {
    private static {
        ID[char[]] mAtoms;
        ID mIDAlloc;
    }

    //return an unique, small integer for string s
    //never return 0
    static ID get(char[] s) {
        if (auto p = s in mAtoms) {
            return *p;
        }
        auto nid = ++mIDAlloc;
        mAtoms[s] = nid;
        return nid;
    }

    /+
    static char[] lookup(ID id) {
        loop? use reverse lookup table?
        return mAtoms[id];
    }
    +/
}
