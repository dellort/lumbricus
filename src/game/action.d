module game.action;

import game.game;
import game.gobject;

import utils.misc;
import utils.vector2;
import utils.time;
import utils.factory;
import utils.configfile;
import utils.randval;
import utils.reflection;
public import utils.mybox;
import utils.log;

alias StaticFactory!("ActionClasses", ActionClass) ActionClassFactory;

///stupid ActionClass hashmap class
class ActionContainer {
    private {
        ActionClass[char[]] mActions;
    }

    //xxx class
    this (ReflectCtor c) {
    }
    this () {
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
    void loadFromConfig(GameEngine eng, ConfigNode node) {
        mActions = null;
        if (!node)
            return;
        //list of named subnodes, each containing an ActionClass
        foreach (char[] name, ConfigNode n; node) {
            auto ac = actionFromConfig(eng, n);
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
ActionClass actionFromConfig(GameEngine eng, ConfigNode node) {
    if (node is null)
        return null;
    //empty type value defaults to "list" -> less writing
    char[] type = node.getStringValue("type", "list");
    if (ActionClassFactory.exists(type)) {
        auto ac = ActionClassFactory.instantiate(type);
        assert(!!ac);
        ac.loadFromConfig(eng, node);
        return ac;
    } else {
        registerLog("game.action")("Action type "~type~" not found.");
        return null;
    }
}


///base class for ActionClass factory classes (lol, double factory again...)
abstract class ActionClass {
    abstract void loadFromConfig(GameEngine eng, ConfigNode node);

    abstract Action createInstance(GameEngine eng);

    //xxx class
    this (ReflectCtor c) {
    }
    this () {
    }
}

///Specify how the list will be executed: one-by-one or all at once
enum ALExecType {
    sequential,
    parallel,
}

///Calling context for an Action instance, passed with execute()
final class ActionContext {
    //return boxed parameters
    //xxx type must match Action's expectation (no checking)
    MyBox delegate(char[] id) paramDg;
    //override Action's activity check by setting this
    bool delegate() activityCheck;

    this(MyBox delegate(char[] id) params = null) {
        paramDg = params;
    }

    this (ReflectCtor c) {
    }

    final T getPar(T)(char[] id) {
        MyBox b;
        if (paramDg)
            b = paramDg(id);
        if (!b.empty) {
            return b.unbox!(T);
        } else {
            throw new Exception("Missing parameter: "~id);
        }
    }

    final T getParDef(T)(char[] id, T def = T.init) {
        MyBox b;
        if (paramDg)
            b = paramDg(id);
        if (!b.empty) {
            return b.unbox!(T);
        } else {
            return def;
        }
    }
}

//overengineered for sure: allows recursive structures ;)
///a list of ActionClass instances
class ActionListClass : ActionClass {
    //static after loading, so no list class required
    ActionClass[] actions;
    ///see AlExecType
    ALExecType execType = ALExecType.sequential;
    ///number of loops over all actions
    int repeatCount = 1;
    RandomValue!(Time) repeatDelay = {Time.Null, Time.Null};

    //xxx class
    this (ReflectCtor c) {
        super(c);
    }
    this () {
    }

    void loadFromConfig(GameEngine eng, ConfigNode node) {
        //parameters for _this_ list
        char[] et = node.getStringValue("exec", "sequential");
        if (et == "parallel") {
            execType = ALExecType.parallel;
        }
        repeatCount = node.getIntValue("repeat", 1);
        //yyy time range
        repeatDelay = node.getValue("repeat_delay", repeatDelay);
        //now load contained actions
        foreach (ConfigNode n; node) {
            //xxx added this when ConfigValue was removed
            //    try to skip entries which were ConfigValues
            if (!n.hasSubNodes())
                continue;
            auto ac = actionFromConfig(eng, n);
            if (ac) {
                actions ~= ac;
            }
        }
        if (actions.length == 0) {
            //xxx
            throw new Exception("Sorry, empty action list not allowed");
        }
    }

    ActionList createInstance(GameEngine eng) {
        return new ActionList(this, eng);
    }

    static this() {
        ActionClassFactory.register!(typeof(this))("list");
    }
}

///list of "active" actions, will run them all based on class config
class ActionList : Action {
    private {
        //same as in ActionListClass
        Action[] mActions;
        //next action due for execution
        int mCurrent;
        //count of finished actions
        int mDoneCounter;
        //repetition counter
        int mRepCounter;
        Time mAllDoneTime, mNextLoopTime;
        bool mAborting, mDoneFlag, mWaitingForNextLoop;
    }

    //called before every loop over all actions
    void delegate(Action sender) onStartLoop;
    //called when all actions of current loop are done
    void delegate(Action sender) onEndLoop;
    ActionListClass myclass;

    this(ActionListClass base, GameEngine eng) {
        super(base, eng);
        myclass = base;
        //create actions
        foreach (ActionClass ac; myclass.actions) {
            auto newInst = ac.createInstance(engine);
            newInst.onFinish = &acFinish;
            mActions ~= newInst;
        }
    }

    this (ReflectCtor c) {
        super(c);
        c.types().registerMethod(this, &acFinish, "acFinish");
    }

    //callback method for Actions (meaning an action completed)
    private void acFinish(Action sender) {
        mDoneCounter++;
        if (mAborting)
            return;
        //an action finished -> run the next one
        if (myclass.execType == ALExecType.sequential) {
            if (mDoneCounter < mActions.length) {
                runNextAction();
                return;
            }
        }
        //all done? then forward done flag
        if (mDoneCounter >= mActions.length) {
            if (onEndLoop)
                onEndLoop(this);
            mAllDoneTime = engine.gameTime.current;
            auto delayT = myclass.repeatDelay.sample(engine.rnd);
            mNextLoopTime = mAllDoneTime + delayT;
            mRepCounter--;
            //note: can be <0, which means infinite execution
            if (mRepCounter == 0) {
                listDone();
            } else {
                //and the whole thing once again
                if (delayT == Time.Null) {
                    runLoop();
                } else {
                    mWaitingForNextLoop = true;
                }
            }
        }
    }

    //only called while waiting for next loop
    override void simulate(float deltaT) {
        if (!mWaitingForNextLoop)
            return;
        if (engine.gameTime.current >= mNextLoopTime) {
            mWaitingForNextLoop = false;
            runLoop();
        }
    }

    override protected bool customActivity() {
        //special case: not waiting for next loop, and all actions report
        //no activity -> at least one has to be using customActivity()
        if (!mWaitingForNextLoop) {
            bool act = false;
            foreach (a; mActions) {
                act |= a.activity();
            }
            return act;
        }
        return true;
    }

    //run next action in queue
    private void runNextAction() {
        if (mCurrent >= mActions.length)
            return;
        mCurrent++;
        //this must be the last statement here
        mActions[mCurrent-1].execute(context);
    }

    override protected ActionRes initialStep() {
        mDoneFlag = false;
        mRepCounter = myclass.repeatCount;
        //check for empty list
        if (mActions.length == 0) {
            return ActionRes.done;
        }
        return runLoop();
    }

    private ActionRes runLoop() {
        mDoneCounter = 0;
        mCurrent = 0;
        if (onStartLoop)
            onStartLoop(this);
        if (mAborting)
            return ActionRes.done;
        if (myclass.execType == ALExecType.parallel) {
            //run all actions at once, without waiting for done() callbacks
            foreach (Action a; mActions) {
                runNextAction();
            }
        } else {
            //execute one action only
            runNextAction();
        }
        if (mDoneFlag)
            return ActionRes.done;
        else
            return ActionRes.moreWork;
    }

    private void listDone() {
        if (active)
            done();
        else
            mDoneFlag = true;
    }

    override void abort() {
        //forward abort call
        mAborting = true;
        foreach (Action ac; mActions) {
            ac.abort();
        }
        //not all actions had to be running, so no check here
        super.abort();
    }
}

enum ActionRes {
    done ,
    moreWork,
}

///base class for actions (can run multiple times, but only after the finish
///call)
//GameObject, lol
abstract class Action : GameObject {
    private ActionClass myclass;
    private bool mActivity;
    protected static LogStruct!("game.action") log;

    ActionContext context;
    void delegate(Action sender) onExecute;
    void delegate(Action sender) onFinish;

    this(ActionClass base, GameEngine eng) {
        //inactive by default (instant actions require no work by engine)
        super(eng, false);
        myclass = base;
    }

    this (ReflectCtor c) {
        super(c);
    }

    final void execute() {
        //create empty context if not set
        if (!context)
            context = new ActionContext();
        if (onExecute)
            onExecute(this);
        //not reentrant
        assert(!mActivity, "Action is still active");
        mActivity = true;
        if (initialStep() == ActionRes.moreWork) {
            //still work to do -> add to GameEngine for later processing
            active = true;
        } else {
            //Warning: may run execute() again from callback
            done();
        }
    }

    final void execute(ActionContext ctx) {
        context = ctx;
        execute();
    }

    ///main action procedure for immediate actions
    ///return true if more work is needed
    protected ActionRes initialStep() {
        return ActionRes.done;
    }

    ///run deferred actions here (don't forget the done() call)
    override void simulate(float deltaT) {
    }

    //called by action handler when work is complete
    protected final void done() {
        //only if currently processing action
        if (!mActivity)
            return;
        mActivity = false;
        active = false;
        if (onFinish) {
            onFinish(this);
        }
    }

    final bool activity() {
        if (mActivity) {
            assert(!!context);
            //context/custom activity checker can only make an active action
            //appear inactive, not the other way round
            if (context.activityCheck)
                return context.activityCheck();
            return customActivity();
        }
        return false;
    }

    ///custom (to-override) activity checker to allow situations where
    ///an action still in the game loop should not be considered active
    ///only considered when action is already running deferred
    //this is dangerous: return false only if you know that your action will
    //not affect gameplay, and the state of your action will not change
    //in a no-activity situation (esp. not go done)
    protected bool customActivity() {
        return true;
    }

    ///stop all activity asap
    void abort() {
        //just stop deferred activity
        //if overriding, make sure this leads to a done() call
        //if there has not been one before
        done();
    }
}

//------------------------------------------------------------------------

///TimedAction: simple action that pauses execution for some msecs
///can also serve as base class for actions requiring a lifetime
class TimedActionClass : ActionClass {
    RandomInt durationMs = {1000, 1000};

    //xxx class
    this (ReflectCtor c) {
        super(c);
    }
    this () {
    }

    void loadFromConfig(GameEngine eng, ConfigNode node) {
        durationMs = node.getValue("duration", durationMs);
    }

    TimedAction createInstance(GameEngine eng) {
        return new TimedAction(this, eng);
    }

    static this() {
        ActionClassFactory.register!(typeof(this))("delay");
    }
}

class TimedAction : Action {
    private {
        Time mFinishTime;
        TimedActionClass myclass;
        bool mDeferredInit = false;
    }

    this(TimedActionClass base, GameEngine eng) {
        super(base, eng);
        myclass = base;
    }

    this (ReflectCtor c) {
        super(c);
    }

    //hehe... (use the 3 functions below)
    override final protected ActionRes initialStep() {
        Time aDuration = timeMsecs(myclass.durationMs.sample(engine.rnd));
        mFinishTime = engine.gameTime.current + aDuration;
        if (doImmediate() == ActionRes.moreWork) {
            //check for 0 delay special case
            if (aDuration > Time.Null)
                mDeferredInit = (initDeferred() == ActionRes.moreWork);
            if (!mDeferredInit)
                return ActionRes.done;
        } else {
            return ActionRes.done;
        }
        return ActionRes.moreWork;
    }

    //all empty, this action just waits (override this)
    protected ActionRes doImmediate() {
        //always gets called
        return ActionRes.moreWork;
    }

    protected ActionRes initDeferred() {
        //just gets called when duration > 0 (and no done() call in immediate)
        //call done() here to avoid setting the timer
        return ActionRes.moreWork;
    }

    protected void cleanupDeferred() {
        //just gets called when initDeferred was run (without done() call)
    }

    override void simulate(float deltaT) {
        if (engine.gameTime.current >= mFinishTime) {
            cleanupDeferred();
            done();
        }
    }

    override void abort() {
        if (mDeferredInit)
            cleanupDeferred();
        super.abort();
    }
}

