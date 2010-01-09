module game.gamemodes.base;

import framework.framework;
import utils.timesource;
import game.game;
import game.gobject;
import game.controller;
import game.controller_events;

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
    alias Object[char[]] HudRequests;

    mixin Methods!("startGame");

    this(GameController parent, ConfigNode config) {
        //static initialization doesn't work
        mWaitStart[] = Time.Never;
        mWaitStartLocal[] = Time.Never;
        engine = parent.engine;
        logic = parent;
        modeTime = new TimeSource("modeTime", engine.gameTime);
        OnGameStart.handler(engine.events, &startGame);
    }

    this(ReflectCtor c) {
    }

    ///Return ids and status objects of HUD elements you want to show
    ///Called once when the game GUI is created
    HudRequests getHudRequests() {
        return null;
    }

    ///Start a new game, called before first simulate call
    void startGame(GameObject dummy) {
        modeTime.resetTime();
    }

    ///Called every frame, run gamemode-specific code here
    void simulate() {
        modeTime.update();
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
