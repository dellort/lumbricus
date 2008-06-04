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
    void loadFromConfig(ConfigNode node) {
        //list of named subnodes, each containing an ActionClass
        //xxx same code as in ActionListClass
        foreach (char[] name, ConfigNode n; node) {
            //empty type value defaults to "list" -> less writing
            char[] type = n.getStringValue("type", "list");
            if (ActionClassFactory.exists(type)) {
                auto ac = ActionClassFactory.instantiate(type);
                ac.loadFromConfig(n);
                //names are unique
                mActions[name] = ac;
            }
        }
    }
}


///base class for ActionClass factory classes (lol, double factory again...)
abstract class ActionClass {
    abstract void loadFromConfig(ConfigNode node);

    abstract Action createInstance(GameEngine eng);
}

///Specify how the list will be executed: one-by-one or all at once
enum ALExecType {
    sequential,
    parallel,
}

//overengineered for sure: allows recursive structures ;)
///a list of ActionClass instances
class ActionListClass : ActionClass {
    //static after loading, so no list class required
    ActionClass[] actions;
    ///see AlExecType
    ALExecType execType = ALExecType.sequential;

    void loadFromConfig(ConfigNode node) {
        //parameters for _this_ list
        char[] et = node.getStringValue("exec", "sequential");
        if (et == "parallel") {
            execType = ALExecType.parallel;
        }
        //now load contained actions
        foreach (ConfigNode n; node) {
            //empty type value defaults to "list" -> less writing
            char[] type = n.getStringValue("type", "list");
            if (ActionClassFactory.exists(type)) {
                auto ac = ActionClassFactory.instantiate(type);
                ac.loadFromConfig(n);
                actions ~= ac;
            }
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
        //current action (for sequential mode)
        int mCurrent = 0;
        //ready flag (sequential mode)
        bool mReady = true;
        //count finished actions (parallel mode)
        int mDoneCounter = 0;
    }

    ActionListClass myclass;

    this(ActionListClass base, GameEngine eng) {
        super(base, eng);
        myclass = base;
        foreach (ActionClass ac; myclass.actions) {
            mActions ~= ac.createInstance(eng);
        }
    }

    //callback method for Actions (meaning an action completed)
    private void acFinish(Action sender) {
        mDoneCounter++;
        //an action finished -> run the next one
        if (myclass.execType == ALExecType.sequential) {
            if (mDoneCounter < mActions.length) {
                runNextAction();
            }
        }
        //all done? then forward done flag
        if (mDoneCounter >= mActions.length) {
            done();
        }
    }

    //run next action in queue
    private void runNextAction() {
        if (mCurrent >= mActions.length)
            return;
        mActions[mCurrent].onFinish = &acFinish;
        mActions[mCurrent].execute();
    }

    override protected void initialStep() {
        //check for empty list
        if (mActions.length == 0) {
            done();
            return;
        }
        if (myclass.execType == ALExecType.parallel) {
            //run all actions at once, without waiting for done() callbacks
            foreach (Action a; mActions) {
                runNextAction();
            }
        } else {
            //execute one action only
            runNextAction();
        }
    }
}

///base class for actions (one-time execution)
//GameObject, lol
abstract class Action : GameObject {
    private ActionClass myclass;
    private bool mActivity = true;

    void delegate(Action sender) onFinish;

    this(ActionClass base, GameEngine eng) {
        //inactive by default (instant actions require no work by engine)
        super(eng, false);
        myclass = base;
    }

    void execute() {
        initialStep();
        if (mActivity) {
            //still work to do -> add to GameEngine for later processing
            active = true;
        }
    }

    ///main action procedures, call done() when action is finished
    ///direct actions
    protected void initialStep() {}

    ///run deferred actions here (don't forget the done() call)
    void simulate(float deltaT) {
    }

    //called by action handler when work is complete
    private void done() {
        if (onFinish) {
            onFinish(this);
        }
        mActivity = false;
        kill();
    }

    bool activity() {
        return mActivity;
    }
}
