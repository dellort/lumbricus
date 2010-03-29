module game.gamemodes.base;

import framework.framework;
import game.core;
import game.game;
import game.controller;
import utils.configfile;
import utils.time;
import utils.timesource;
import utils.misc;

//NOTE: a game mode doesn't need to derive from this object; it's just for
//  convenience (hud managment, some strange timing helpers)
class Gamemode : GameObject2 {
    private {
        Time[5] mWaitStart, mWaitStartLocal;
        GameController mController;
    }
    protected TimeSource modeTime;

    this(GameEngine a_engine) {
        super(a_engine, "gamemode");
        //static initialization doesn't work (probably D bug 3198)
        mWaitStart[] = Time.Never;
        mWaitStartLocal[] = Time.Never;
        modeTime = new TimeSource("modeTime", engine.gameTime);
        OnGameStart.handler(engine.events, &startGame);
        internal_active = true;
    }

    GameController logic() {
        //the controller is created in a late stage of game initialization
        assert(!!mController);
        return mController;
    }

    ///Start a new game, called before first simulate call
    protected void startGame(GameObject dummy) {
        modeTime.resetTime();
        mController = engine.singleton!(GameController)();
    }

    ///Called every frame, run gamemode-specific code here
    override void simulate() {
        modeTime.update();
    }

    override bool activity() {
        return false;
    }

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
