module game.action;

import game.game;
import game.gobject;

import utils.misc;
import utils.vector2;
import utils.mylist;
import utils.time;
import utils.factory;
import utils.configfile;

class ActionClassFactory : StaticFactory!(ActionClass)
{
}

///stupid ActionClass hashmap class
class ActionContainer {
    private {
        ActionClass[char[]] mActions;
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
        ac.loadFromConfig(eng, node);
        return ac;
    } else {
        eng.mLog("Action type "~type~" not found.");
        return null;
    }
}


///base class for ActionClass factory classes (lol, double factory again...)
abstract class ActionClass {
    abstract void loadFromConfig(GameEngine eng, ConfigNode node);

    abstract Action createInstance(GameEngine eng);
}

///Specify how the list will be executed: one-by-one or all at once
enum ALExecType {
    sequential,
    parallel,
}

alias void* ActionParT;
//alias ActionParT[char[]] ActionParams;

///holder for action parameters
//xxx make this better
struct ActionParams {
    private ActionParT[char[]] mParams;

    //called whenever a parameter is accessed
    void delegate(ActionParams* sender, char[] id) onBeforeRead;

    ActionParT opIndex(char[] id) {
        return mParams[id];
    }

    ActionParT opIndexAssign(ActionParT p, char[] id) {
        mParams[id] = p;
        return p;
    }

    //actions have to use this to read parameters, or callback won't work
    T* getPar(T)(char[] id) {
        if (onBeforeRead)
            onBeforeRead(this, id);
        ActionParT* pt = id in mParams;
        if (pt) {
            return cast(T*)*pt;
        } else {
            return null;
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
    Time repeatDelay = Time.Null;

    void loadFromConfig(GameEngine eng, ConfigNode node) {
        //parameters for _this_ list
        char[] et = node.getStringValue("exec", "sequential");
        if (et == "parallel") {
            execType = ALExecType.parallel;
        }
        repeatCount = node.getIntValue("repeat", 1);
        repeatDelay = timeMsecs(node.getIntValue("repeat_delay", 0));
        //now load contained actions
        foreach (ConfigNode n; node) {
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
            mAllDoneTime = engine.gameTime.current;
            mNextLoopTime = mAllDoneTime + myclass.repeatDelay;
            mRepCounter--;
            //note: can be <0, which means infinite execution
            if (mRepCounter == 0) {
                listDone();
            } else {
                //and the whole thing once again
                if (myclass.repeatDelay == Time.Null) {
                    runLoop();
                } else {
                    mWaitingForNextLoop = true;
                    active = true;
                }
            }
        }
    }

    //only called while waiting for next loop
    override void simulate(float deltaT) {
        if (!mWaitingForNextLoop)
            return;
        if (engine.gameTime.current >= mNextLoopTime) {
            active = false;
            mWaitingForNextLoop = false;
            runLoop();
        }
    }

    //run next action in queue
    private void runNextAction() {
        if (mCurrent >= mActions.length)
            return;
        mCurrent++;
        //this must be the last statement here
        mActions[mCurrent-1].execute(params);
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
        assert(mDoneCounter >= mActions.length,
            "Should have all done() calls here");
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

    ActionParams params;
    void delegate(Action sender) onExecute;
    void delegate(Action sender) onFinish;

    this(ActionClass base, GameEngine eng) {
        //inactive by default (instant actions require no work by engine)
        super(eng, false);
        myclass = base;
    }

    final void execute() {
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

    final void execute(ActionParams p) {
        params = p;
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
        return mActivity;
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
    Time duration;
    bool randomDuration;

    void loadFromConfig(GameEngine eng, ConfigNode node) {
        duration = timeMsecs(node.getIntValue("duration",1000));
        randomDuration = node.getBoolValue("random_duration",false);
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

    //hehe... (use the 3 functions below)
    override final protected ActionRes initialStep() {
        Time aDuration;
        if (myclass.randomDuration)
            aDuration = timeMsecs(myclass.duration.msecs
                * engine.rnd.nextDouble());
        else
            aDuration = myclass.duration;
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

