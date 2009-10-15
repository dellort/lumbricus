module game.action.base;

import common.resset;
import framework.framework;
import game.game;
import game.gfxset;
import game.gobject;
import utils.configfile;
import utils.time;
import utils.randval;
import utils.reflection;
import utils.serialize;
import utils.misc;
import utils.log;
import utils.strparser : fromStr;
import utils.factory;
import str = utils.string;

import tango.core.Traits : ParameterTupleOf;
import tango.stdc.constants.constSupport : ctfe_i2a;

//I see a pattern...
//NOTE: char[] is a unique name, which is used for serialization only
//      (directly passed to ActionClass ctor)
alias StaticFactory!("ActionClasses", ActionClass, GfxSet, ConfigNode,
    char[]) ActionClassFactory;

///stupid ActionClass hashmap class
class ActionContainer {
    private {
        ActionClass[char[]] mActions;
        char[] mName;
    }

    //xxx class
    this (ReflectCtor c) {
    }
    this (char[] name) {
        mName = name;
    }

    ///get an ActionClass by its id
    ActionClass action(char[] id) {
        ActionClass* p = id in mActions;
        if (p) {
            return *p;
        }
        return null;
    }

    /** Load the whole thing from a config node
        Example:
          actions {
            impact {
              type = "..."
            }
            trigger {
              type = "..."
            }
          }
    */
    void loadFromConfig(GfxSet gfx, ConfigNode node) {
        mActions = null;
        if (!node)
            return;
        //list of named subnodes, each containing an ActionClass
        foreach (char[] name, ConfigNode n; node) {
            auto ac = actionFromConfig(gfx, n, mName ~ "::" ~ name);
            if (ac) {
                //names are unique
                mActions[name] = ac;
            }
        }
        //scan values and resolve references (no recursion, sorry)
        foreach (char[] name, char[] value; node) {
            if (value.length > 0 && value in mActions) {
                mActions[name] = mActions[value];
            }
        }
    }
}

///load an action class from a ConfigNode, returns null if class was not found
ActionClass actionFromConfig(GfxSet gfx, ConfigNode node, char[] name) {
    if (node is null)
        return null;
    //empty type value defaults to "list" -> less writing
    char[] type = node.getStringValue("type", "list");
    if (ActionClassFactory.exists(type)) {
        auto ac = ActionClassFactory.instantiate(type, gfx, node, name);
        assert(!!ac);
        //???
        gfx.registerActionClass(ac, ac.name);
        return ac;
    } else {
        registerLog("game.action.base")("Action type "~type~" not found.");
        return null;
    }
}


//just like before
class ActionClass {
    private {
        char[] mName;
    }

    //run it, may put GameObjects on the context stack or just finish
    abstract void execute(ActionContext ctx);

    final char[] name() {
        return mName;
    }

    //xxx class
    this(ReflectCtor c) {
    }
    this(char[] name) {
        mName = name;
    }
}

//This is passed with every execute() call on a ActionClass
//Contains internal parameters (e.g. engine) and manages scoping
//Script functions may expect a derived class
class ActionContext {
    private {
        GameObject[] mObjStack;
        int[] mScopeStack;
    }

    GameEngine engine;

    this(GameEngine eng) {
        assert(!!eng);
        engine = eng;
        reset();
    }
    this(ReflectCtor c) {
    }

    final void reset() {
        mObjStack = null;
        mScopeStack = null;
        //root scope
        pushScope();
    }

    //put a GameObject on the stack (for activity checking)
    final void putObj(GameObject o) {
        mObjStack ~= o;
    }

    //= hack, just for list (the listrunner needs to go into the outer scope)
    final void putObjOuter(GameObject o) {
        int idx = mScopeStack[$-1]-1;
        assert(mObjStack[idx] is null);
        mObjStack[idx] = o;
    }

    //scopes are needed for loops, to check which actions are still running
    //deferred code
    final int pushScope() {
        mObjStack ~= null;
        mScopeStack ~= mObjStack.length;
        return curScope();
    }

    final void popScope() {
        assert(mScopeStack.length > 1, "Scoping error");
        mScopeStack = mScopeStack[0..$-1];
        assert(mScopeStack[$-1] <= mObjStack.length, "Scoping error");
        mObjStack = mObjStack[0..mScopeStack[$-1]];
    }

    final int curScope() {
        return mScopeStack.length - 1;
    }

    //returns true if no activity on scope idx and below
    final bool scopeDone(int idx) {
        if (idx >= mScopeStack.length)
            return true;
        assert(mScopeStack[idx] <= mObjStack.length);
        foreach (obj; mObjStack[mScopeStack[idx]..$]) {
            if (obj && obj.activity) {
                return false;
            }
        }
        return true;
    }

    final bool done() {
        return scopeDone(0);
    }
    final bool active() {
        return !done;
    }

    //cancel background activity
    final void abort() {
        foreach (obj; mObjStack) {
            if (obj)
                obj.kill();
        }
        reset();
    }
}

//for Surface parsing
private void actionParse(GfxSet gfx, out Surface ret, char[] value,
    char[] def)
{
    if (value.length > 0)
        ret = gfx.resources.get!(Surface)(value);
}
void actionParse(GfxSet gfx, out ParticleType ret, char[] value,
    char[] def)
{
    if (value.length > 0)
        ret = gfx.resources.get!(ParticleType)(value);
}

//generic action class with a lot of template magic
//the ONLY reason for this is to cache parameters loaded from config files
//args: D-like syntax, e.g. "param1, param2 = 5"
class MyActionClass(alias Func, char[] args) : ActionClass {
    static assert(str.ctfe_split(args, ',').length + 1 == ParameterTupleOf!(
        typeof(Func)).length, "Invalid action argument string: " ~ args);

    //string mixin: generates a list of variable declarations from function
    //  arguments; Ex.: int param1; float param2;
    static private char[] genArgs(T)(bool replace) {
        alias ParameterTupleOf!(T)[1..$] Params;
        char[] ret = " ";
        foreach (int i, x; Params) {
            char[] tstr = x.stringof;
            if (replace) {
                if (is(x == float))
                    tstr = "RandomFloat";
                if (is(x == int))
                    tstr = "RandomInt";
                if (is(x == Time))
                    tstr = "RandomValue!(Time)";
            }
            ret ~= tstr ~ " param" ~ ctfe_i2a(i) ~ ";\n";
        }
        return ret;
    }

    //parameter cache
    struct ArgStore {
        mixin(genArgs!(typeof(Func))(true));
    }
    private ArgStore store;

    //xxx class
    this(GfxSet gfx, ConfigNode node, char[] a_name)
    {
        super(a_name);
        //parse parameters from node
        char[][] tmpArg = str.split(args, ",");
        foreach (int i, x; store.tupleof) {
            auto tmp = str.split(tmpArg[i], "=");
            assert(tmp.length > 0);
            char[] name = str.strip(tmp[0]);
            char[] def = (tmp.length > 1) ? str.strip(tmp[1]) : "";
            //xxx not sure if this is correct
            static if (is(typeof(actionParse(null, x, "", "")))) {
                //if a special parser exists, use it
                actionParse(gfx, store.tupleof[i], node[name], def);
            } else {
                if (def.length > 0)
                    store.tupleof[i] =
                        node.getValue(name, fromStr!(typeof(x))(def));
                else
                    store.tupleof[i] = node.getValue!(typeof(x))(name);
            }
        }
    }
    this(ReflectCtor c) {
        super(c);
    }
    void execute(ActionContext ctx) {
        //xxx allocating new memory (just because of RandomValue stuff)
        //    maybe pass RandomValues and let the function handle it
        struct ArgPass {
            mixin(genArgs!(typeof(Func))(false));
        }
        ArgPass p;
        foreach (int i, x; store.tupleof) {
            static if (is(typeof(x) == RandomInt)
                || is(typeof(x) == RandomFloat)
                || is(typeof(x) == RandomValue!(Time)))
            {
                p.tupleof[i] = x.sample(ctx.engine.rnd);
            } else {
                p.tupleof[i] = x;
            }
        }
        //make sure the function gets the proper context type
        //if it doesn't match, don't call it
        auto nx = cast(ParameterTupleOf!(typeof(Func))[0])ctx;
        if (nx)
            Func(nx, p.tupleof);
    }
}

/+
private void delegate(Types)[] gActionSerializeRegCache;
//run this after all script functions are registered to setup serialization
void actionSerializeRegister(Types t) {
    foreach (fp; gActionSerializeRegCache) {
        fp(t);
    }
}
+/

//registers a scripting function at the factory, and for serialization
//all regScript calls must be done before the scriptSerializeRegister() call
void regAction(alias Func, char[] args)(char[] id) {
    alias MyActionClass!(Func, args) AcClass;
    ActionClassFactory.register!(AcClass)(id);

    /+
    //whatever
    void reg(Types t) {
        t.registerClass!(AcClass)();
    }
    gActionSerializeRegCache ~= &reg;
    +/
}
