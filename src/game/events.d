//NOTE: keep this game independent; maybe it'll be useful for other stuff
module game.events;

import framework.lua;
import utils.misc;
import utils.mybox;
import utils.reflection;
import utils.serialize;

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

alias void delegate(EventTarget, EventPtr) EventHandler;
alias void delegate(char[], EventTarget, EventPtr) GenericEventHandler;
alias void function(ref EventEntry, EventTarget, EventPtr) DispatchEventHandler;

private struct EventEntry {
    MyBox data;
    DispatchEventHandler handler;
}

private class EventType {
    char[] name;
    TypeInfo paramtype;
    //MarshalIn marshal;
    EventEntry[] handlers;

    this() {}
    this(ReflectCtor c) {}
}

//basic idea: emulate virtual functions; just that:
//  1. you can add functions later without editing the root class
//  2. any class can hook into the events of a foreign class
//  3. magically support scripting (raising/handling events in scripts)
//consequences of the implementation...:
//  1. handlers are always registered to classes, never to instances
//  2. adding handlers is SLOW because of memory allocation
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
final class Events {
    private {
        EventType[char[]] mEvents;

        //LuaState mScripting;
    }

    //catch all events
    GenericEventHandler[] generic_handlers;
    //send all events to these objects as well
    Events[] cascade;

    this() {
        //mScripting = ...;
    }

    this (ReflectCtor c) {
        c.types.registerClasses!(EventType);
    }

    void genericHandler(GenericEventHandler h) {
        generic_handlers ~= h;
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

    void raise(char[] event, EventTarget sender, EventPtr params) {
        //char[] target = sender.eventTargetType();
        EventType e = get_event(event);
        foreach (ref h; e.handlers) {
            h.handler(h, sender, params);
        }

        foreach (h; generic_handlers) {
            h(event, sender, params);
        }

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
//xxx would be nice as struct too, but I get forward reference errors
//xxx 2 the name will add major symbol name bloat, argh.
template DeclareEvent(char[] name, SenderBase, Args...) {
    alias void delegate(SenderBase, Args) Handler;
    alias ParamStruct!(Args) ParamType;
    alias name Name;

    static void handler(Events base, Handler a_handler) {
        paramTypeIn!(ParamType)();

        EventEntry e;
        e.data.box!(Handler)(a_handler);
        e.handler = &handler_templated;
        base.do_reg_handler(name, typeid(ParamType), e);
    }

    static void raise(SenderBase sender, Args args) {
        paramTypeOut!(ParamType)();

        assert(!!sender);
        ParamType args2;
        //dmd bug 3614?
        static if (Args.length)
            args2.args = args;
        sender.eventsBase.raise(name, sender, EventPtr.Ptr(args2));
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

//disgusting serialization hacks follow
//this only deals with the handler_templated functions
//you could just put the dispatcher as virtual function into a templated class,
//  and then register that class for serialization, but the thought of the bloat
//  when generating a class per handler wouldn't let me sleep at night

private {
    DispatchEventHandler[char[]] gEventHandlerDispatchers;
}

//[read|write]Handler make up the custom serializer for the templated dispatch
//  function... the serializer searches through EventHandlerDispatchers and
//  maps the function pointer to a name

private void readHandler(SerializeBase base, SafePtr p,
    void delegate(SafePtr) reader)
{
    char[] name;
    reader(base.types.ptrOf(name));
    auto ph = name in gEventHandlerDispatchers;
    if (!ph) {
        throw new SerializeError("can't read event dispatch handler");
    }
    p.write!(DispatchEventHandler)(*ph);
}

private void writeHandler(SerializeBase base, SafePtr p,
    void delegate(SafePtr) writer)
{
    DispatchEventHandler search = p.read!(DispatchEventHandler)();
    foreach (char[] n, DispatchEventHandler h; gEventHandlerDispatchers) {
        if (search is h) {
            writer(base.types.ptrOf(n));
            return;
        }
    }
    //most likely forgot to pass sth. to registerSerializableEventHandlers()
    //there's nothing you can do about this error; except maybe reverse lookup
    //  the function address to a symbol name using your favorite OMF/ELF tool
    //xxx or like in Types.readDelegateError()
    throw new SerializeError("unregistered event type?");
}

//call with DeclareEvent alias (e.g. SomeEvent)
//this means T is a fully instantiated template (wtf...)
void registerSerializableEventHandlers(T...)(Types types) {
    const clen = T.length; //can't pass this directly to Repeat LOL DMD
    foreach (x; Repeat!(clen)) {
        add_bloat_fn(&T[x].handler_templated, T[x].Name);
        //to enable serialization of EventType.paramtype
        types.getType!(T[x].ParamType)();
    }
}

private void add_bloat_fn(DispatchEventHandler f, char[] name) {
    assert(!(name in gEventHandlerDispatchers), "non-unique event name?");
    gEventHandlerDispatchers[name] = f;
}

static this() {
    add_bloat_fn(&Events.handler_generic, "_generic_");
}

void eventsInitSerializeCtx(SerializeContext ctx) {
    ctx.addCustomSerializer!(DispatchEventHandler)(null, &readHandler,
        &writeHandler);
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
