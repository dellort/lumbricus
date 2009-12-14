module game.action.list;

import game.action.base;
import game.game;
import game.gfxset;
import game.gobject;
import utils.configfile;
import utils.time;
import utils.randval;
import utils.reflection;
import utils.misc;
import utils.log;
import utils.factory;

///Specify how the list will be executed: one-by-one or all at once
enum ALExecType {
    sequential,
    parallel,
}

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
    this (GfxSet gfx, ConfigNode node, char[] a_name) {
        super(a_name);
        //parameters for _this_ list
        char[] et = node.getStringValue("exec", "sequential");
        if (et == "parallel") {
            execType = ALExecType.parallel;
        }
        repeatCount = node.getIntValue("repeat", 1);
        repeatDelay = node.getValue("repeat_delay", repeatDelay);
        //now load contained actions
        int idx;
        foreach (ConfigNode n; node) {
            idx++;
            if (!n.hasSubNodes())
                continue;
            auto ac = actionFromConfig(gfx, n, myformat("{}::{}", name, idx));
            if (ac) {
                actions ~= ac;
            }
        }
        if (actions.length == 0) {
            //xxx
            throw new Exception("Sorry, empty action list not allowed");
        }
    }

    //run ActionClasses starting at i, relative to scope sc
    //Returns:
    //  0  if one loop executed and ready for next loop
    //  -1 if one loop executed, but there's still defered processing
    //  >0 index to the next action that will be run
    private int run(ActionContext ctx, int theScope, int next, ref int reps) {
        while (reps > 0 && (next = run2(ctx, theScope, next)) == 0) {
            if (next == 0)
                reps--;
            if (!repeatDelay.isNull())
                break;
        }
        return next;
    }

    //same as above, without repeating
    private int run2(ActionContext ctx, int theScope, int i) {
        if (actions.length == 0)
            return 0;
        if (i < 0) {
            if (!ctx.scopeDone(theScope))
                return i;
            else
                i = 0;
        }
        if (execType == ALExecType.parallel) {
            //run everything at once
            assert(i == 0);
            foreach (sc; actions) {
                sc.execute(ctx);
            }
            return ctx.scopeDone(theScope) ? 0 : -1;
        } else {
            //wait for idle until running one
            while (ctx.scopeDone(theScope) && i < actions.length) {
                actions[i].execute(ctx);
                i++;
            }
            //wrap-around
            if (i >= actions.length)
                i = ctx.scopeDone(theScope) ? 0 : -1;
            return i;
        }
    }

    void execute(ActionContext ctx) {
        assert(!!ctx);
        if (actions.length == 0)
            return;
        int myScope = ctx.pushScope();
        int reps = repeatCount;
        int next = run(ctx, myScope, 0, reps);
        if (reps == 0) {
            //everything executed, no more work
            ctx.popScope();
            return;
        } else {
            //need to wait for something
            ctx.putObjOuter(
                new ActionListRunner(this, ctx, myScope, next, reps));
        }
    }
}

//if the loop cannot be run in a single execute() call
//handles all cases where waiting is involved
class ActionListRunner : GameObject {
    private {
        ActionListClass myclass;
        ActionContext mContext;
        int mScopeIdx, mNext, mLoops;
        Time mWaitDone = Time.Never;
    }

    this(ActionListClass owner, ActionContext ctx, int scopeIdx, int next,
        int repeat)
    {
        assert(!!ctx);
        super(ctx.engine, "actionlist");
        active = true;
        myclass = owner;
        mContext = ctx;
        mScopeIdx = scopeIdx;
        mNext = next;
        mLoops = repeat;
        assert(mLoops > 0);
        if (mNext == 0)
            startWait();  //ScriptListClass already finished one loop
    }
    this(ReflectCtor c) {
        super(c);
    }

    bool activity() {
        return active;
    }

    //wait repeatDelay for next loop
    private void startWait() {
        mWaitDone = engine.gameTime.current
            + myclass.repeatDelay.sample(engine.rnd);
    }

    override void simulate(float deltaT) {
        super.simulate(deltaT);
        if (mWaitDone != Time.Never && engine.gameTime.current < mWaitDone) {
            //waiting for next loop
            return;
        }
        mNext = myclass.run(mContext, mScopeIdx, mNext, mLoops);
        if (mNext == 0) {
            //all actions ran
            if (mLoops <= 0) {
                //no more repetitions
                mContext.popScope();
                mContext = null;
                kill();
            } else if (!myclass.repeatDelay.isNull()) {
                startWait();
            }
        }
    }

    override protected void updateActive() {
        //xxx what about context scope?
    }
}

static this() {
    ActionClassFactory.register!(ActionListClass)("list");
}
