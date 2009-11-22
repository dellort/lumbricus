module game.gamemodes.base;

import framework.framework;
import framework.timesource;
import game.game;
import game.controller;

import utils.factory;
import utils.reflection;
import utils.mybox;
import utils.configfile;
import utils.time;
import utils.misc;

//factory to instantiate gamemodes
alias StaticFactory!("Gamemodes", Gamemode, GameController, ConfigNode)
    GamemodeFactory;

class Gamemode {
    GameEngine engine;
    GameController logic;
    private Time[5] mWaitStart, mWaitStartLocal;
    protected TimeSource modeTime;

    this(GameController parent, ConfigNode config) {
        //static initialization doesn't work
        mWaitStart[] = Time.Never;
        mWaitStartLocal[] = Time.Never;
        engine = parent.engine;
        logic = parent;
        modeTime = new TimeSource("modeTime", engine.gameTime);
    }

    this(ReflectCtor c) {
    }

    ///Initialize gamemode (check requirements or whatever)
    ///Called after controller initialization and client connection
    ///Throw exception if anything is not according to plan
    void initialize() {
    }

    ///Start a new game, called before first simulate call
    void startGame() {
        logic.events.onGameStart(this);
        modeTime.resetTime();
    }

    ///Called every frame, run gamemode-specific code here
    void simulate() {
        modeTime.update();
    }

    ///Called by controller every frame, after simulate
    ///Return true if the game is over
    ///It is the Gamemode's task to make a team win before
    abstract bool ended();

    ///get mode-specific status information
    ///clients have to know about the mode implementation to use it
    ///xxx: it'd probably be better if the Gamemode implementation could create
    ///     a specific GUI (aka HUD) element explicitly
    ///     then this function wouldn't be needed and it'd be more flexible
    ///     overall
    ///xxx2: actually, we almost have this, it's just that everything is put
    ///     into a single object (the object returned by this function)
    abstract Object getStatus();

    //Returns the number of teams with alive members
    //If there are any, firstAlive is set to the first one found
    protected int aliveTeams(out Team firstAlive) {
        int ret;
        foreach (t; logic.teams) {
            if (t.alive()) {
                ret++;
                firstAlive = t;
            }
        }
        return ret;
    }

    //Wait utility functions
    //First call starts the timer, true is returned (and the state is reset)
    //  when the time has elapsed
    //Supports 5 independent numbered timers, default is 0

    //Standard waiting functions are based on engine.gameTime,
    //local waiting functions are based on gamemode time (which can be paused
    //  independently of gameTime)
    protected bool wait(bool Local = false)(Time t, int timerId = 0,
        bool autoReset = true)
    {
        return waitRemain!(Local)(t, timerId, autoReset) <= Time.Null;
    }

    protected Time waitRemain(bool Local = false)(Time t, int timerId = 0,
        bool autoReset = true)
    {
        TimeSourcePublic engTime = engine.gameTime;
        //lol template spaghetti code
        static if (Local) {
            alias mWaitStartLocal waitCache;
            alias modeTime waitTimeSource;
        } else {
            alias mWaitStart waitCache;
            alias engTime waitTimeSource;
        }
        if (waitCache[timerId] == Time.Never) {
            waitCache[timerId] = waitTimeSource.current;
        }
        Time r = max(t - (waitTimeSource.current - waitCache[timerId]),
            Time.Null);
        if (r <= Time.Null && autoReset) {
            waitCache[timerId] = Time.Never;
        }
        return r;
    }

    protected void waitAddTimeLocal(int timerId, Time add) {
        mWaitStartLocal[timerId] += add;
    }

    protected void waitReset(bool Local = false)(int timerId = 0) {
        static if (Local)
            mWaitStartLocal[timerId] = Time.Never;
        else
            mWaitStart[timerId] = Time.Never;
    }
}
