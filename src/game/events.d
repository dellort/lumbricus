//NOTE: keep this game independent; maybe it'll be useful for other stuff
module game.events;

import framework.lua;
import traits = tango.core.Traits;

class EventTarget {
    private {
        char[] mEventTargetType;
        //ID mEventTargetTypeID;
    }

    this(char[] type) {
        mEventTargetType = type;
        //mEventTargetTypeID = 0;
    }

    abstract Events eventsBase();

    final char[] eventTargetType() {
        return mEventTargetType;
    }

/+
    //for Events.raise()
    private ID getEventTargetTypeID(Events base) {
        //this is going to break if this is used with several Events instances
        //which means the user isn't allowed to do this
        if (!mEventTargetTypeID) {
            mEventTargetTypeID = base.atoms.get(mEventTargetType);
        }
        return mEventTargetTypeID;
    }
+/
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
}

alias void delegate(EventTarget sender, EventPtr params) EventHandler;

//dissect T, which is an event handler delegate/function; see Events.handlerT
//T is roughly of the form:
//template T(Sender, Args...) {
//  alias void delegate/function(Sender sender, Args args) T;
//}
template SplitEventHandler(T) {
    static assert(traits.isCallableType!(T));
    alias traits.ParameterTupleOf!(T) AllParams;
    static assert(AllParams.length > 0, "needs at least sender paremeter");
    alias AllParams[0] Sender;
    alias AllParams[1..$] Args;
    static assert(is(Sender : EventTarget));
    alias ParamStruct!(Args) ParamType;
}

//basic idea: emulate virtual functions; just that:
//  1. you can add functions later without editing the root class
//  2. any class can hook into the events of a foreign class
//  3. magically support scripting (raising/handling events in scripts)
//consequences of the implementation...:
//  1. handlers are always registered to classes, never to instances
//  2. adding handlers is SLOW because of some internal dispatch preparation
//
//the following applies: "make it better", "we can change/fix it later",
//  "it's better than nothing", "I had to do something about this",
//  "making it simple was too complicated", "first make it work, then optimize"
//
//optimization ideas:
//  - pass around unique IDs or precomputed hashes instead of strings
//    for both event identifiers and object types
//  - somehow make raiseT call Lua directly, instead of going through an AA
//    lookup and calling a demarshaller (re-implement the event dispatch
//    mechanism in Lua, also see next item)
//  - don't call Lua if no Lua handlers are registered; if Lua handlers are
//    registered, call Lua only once and do the actual dispatch in Lua (cheaper
//    than marshalling the event parameters multiple times)
//
//also, either raiseT() or raise() should eventually be removed
class Events {
    private {
        TargetList[char[]] mHandlers;
        EventType[char[]] mEvents;

        //LuaState mScripting;
    }

    //only needed to map scripting event to parameter type
    private static class EventType {
        char[] name;
        TypeInfo paramtype;
        //MarshalIn marshal;
    }

    private static class TargetList {
        char[] name;
        TargetList parent;
        //indexed by event type
        EventHandler[][char[]] handlers;
        EventHandler[][char[]] all_handlers;
        bool adding, done; //temporary flags for rebuild_stuff()
    }

    this() {
        //mScripting = ...;
    }

    private EventType get_event(char[] name) {
        auto pevent = name in mEvents;
        if (pevent)
            return *pevent;
        auto e = new EventType;
        e.name = name;
        mEvents[e.name] = e;
        return e;
    }

    private TargetList get_target(char[] name) {
        auto ptarget = name in mHandlers;
        if (ptarget)
            return *ptarget;
        auto t = new TargetList;
        t.name = name;
        mHandlers[t.name] = t;
        return t;
    }

    //update TargetList.all_handlers
    //so that all_handlers will contain the handlers of all target super classes
    private void rebuild_stuff() {
        foreach (TargetList t; mHandlers) {
            t.all_handlers = null;
            t.done = false;
        }

        //add everything from "from" to "to"
        void add_handlers(ref EventHandler[][char[]] to,
            EventHandler[][char[]] from)
        {
            foreach (char[] k, EventHandler[] v; from) {
                if (!(k in to))
                    to[k] = null;
                to[k] ~= v;
            }
        }

        void rebuild(TargetList t) {
            assert(!t.adding, "circular inheritance");
            if (t.done)
                return;

            t.adding = true;
            t.done = true;
            add_handlers(t.all_handlers, t.handlers);
            if (t.parent) {
                rebuild(t.parent);
                add_handlers(t.all_handlers, t.parent.all_handlers);
            }
            t.adding = false;
        }

        foreach (TargetList t; mHandlers) {
            if (!t.done)
                rebuild(t);
        }
    }

    //event = event name (e.g. "ondamage")
    //target = type or super type of the objects to receive events from
    //         (e.g. "worm" or "sprite")
    //paramtype is needed for script->D events (what type to demarshal)
    void handler(char[] event, char[] target, TypeInfo paramtype,
        EventHandler a_handler)
    {
        EventType e = get_event(event);
        if (e.paramtype && e.paramtype !is paramtype)
            assert(false, "handlers for same event with different parameters");
        e.paramtype = paramtype;

        TargetList t = get_target(target);
        if (!(event in t.handlers))
            t.handlers[event] = [];
        t.handlers[event] ~= a_handler;

        rebuild_stuff();
    }

    //e.g. when worm is damaged:
    //  class Worm : ... { void apply_demage() { raise("ondamage", this); }
    void raise(char[] event, EventTarget sender,
        EventPtr params = EventPtr.Null)
    {
        raiseD(event, sender, params);
    }

    //call D event handlers
    private void raiseD(char[] event, EventTarget sender, EventPtr params) {
        char[] target = sender.eventTargetType();
        auto ptarget = target in mHandlers;
        if (!ptarget)
            return;
        TargetList t = *ptarget;
        auto phandlers = event in t.all_handlers;
        if (!phandlers)
            return;
        foreach (EventHandler h; *phandlers) {
            h(sender, params);
        }
    }

    //make target_super a super class of target_sub
    //which means if an event handler is registered for target_super, it will
    //  also receive events from target_sub EventTargets
    void inherit(char[] target_super, char[] target_sub) {
        auto sup = get_target(target_super);
        auto sub = get_target(target_sub);

        if (sub.parent is sup)
            return;

        assert(!sub.parent); //actually, multiple inheritance could work...
        sub.parent = sup;

        rebuild_stuff();
    }


    //the template metabloat version of handler()
    //for EventHandlerT see SplitEventHandler
    void handlerT(EventHandlerT)(char[] event, char[] target,
        EventHandlerT a_handler)
    {
        alias SplitEventHandler!(EventHandlerT) P;

        paramTypeIn!(P.ParamType)();

        struct Closure { //(needless in D2, could use a_handler directly)
            EventHandlerT dest;
            void call(EventTarget sender, EventPtr argptr) {
                auto sender2 = cast(P.Sender)sender;
                //what if it's the wrong type?
                //anyone can raise an event with the wrong sender/arg types
                if (!sender2)
                    return;
                auto args = argptr.get!(P.ParamType)();
                dest(sender2, args.tupleof);
            }
        }

        auto c = new Closure;
        c.dest = a_handler;
        handler(event, target, typeid(P.ParamType), &c.call);
    }

    //again, template metabloat version
    void raiseT(Args...)(char[] event, EventTarget sender, Args args) {
        alias ParamStruct!(Args) ParamType;
        paramTypeOut!(ParamType)();
        ParamType args2;
        //dmd bug 3614?
        static if (Args.length)
            args2.args = args;
        raise(event, sender, EventPtr.Ptr(args2));
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
void paramTypeOut(T)() {
    alias GetArgs!(T) Args;
    //...
}

//script -> D
void paramTypeIn(T)() {
    alias GetArgs!(T) Args;
    //...
}

//weird way to "declare" and events globally
//this checks event parameter types at compile time
template DeclareEvent(char[] name, SenderBase, Args...) {
    void handler(T)(Events base, char[] target, T handler) {
        //type checking
        alias SplitEventHandler!(T) P;
        //actually, it just had to be callable (implicit conversions...)
        static assert(is(Args == P.Args), "wrong types for event "~name~", "
            ~"\nexpected: "~Args.stringof~"\ngot: "~P.Args.stringof);
        //must be "somewhere" in inheritance hierarchy
        static assert(is(P.Sender : SenderBase) || is(SenderBase : P.Sender));
        //xxx if only we could map SenderBase to target...
        //  e.g. if SenderBase was a GObjectSprite, target = "sprite" (although
        //  sprite instances could be more special, but "sprite" would still be
        //  valid)
        base.handlerT(name, target, handler);
    }
    void raise(SenderBase sender, Args args) {
        assert(!!sender);
        sender.eventsBase.raiseT(name, sender, args);
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
