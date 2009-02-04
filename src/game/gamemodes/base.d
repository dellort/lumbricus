module game.gamemodes.base;

import framework.framework;
import framework.timesource;
import game.game;
import game.controller;
import game.gamepublic;

import utils.factory;
import utils.reflection;
import utils.mybox;
import utils.configfile;
import utils.time;

//factory to instantiate gamemodes
static class GamemodeFactory
    : StaticFactory!(Gamemode, GameController, ConfigNode)
{
}

class Gamemode {
    GameEngine engine;
    GameController logic;
    private bool[10] mWaiting, mWaitingLocal;
    private Time[10] mWaitStart, mWaitStartLocal;
    //protected TimeSource modeTime;

    this(GameController parent, ConfigNode config) {
        engine = parent.engine;
        logic = parent;
        //modeTime = new TimeSource(&engine.gameTime.current);
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
        //modeTime.resetTime();
    }

    ///Called every frame, run gamemode-specific code here
    void simulate() {
        //modeTime.update();
    }

    ///Called by controller every frame, after simulate
    ///Return true if the game is over
    ///It is the Gamemode's task to make a team win before
    abstract bool ended();

    ///Return a mode-specific state identifier
    ///-1 means the game has ended
    abstract int state();

    ///get mode-specific status information
    ///clients have to know about the mode implementation to use it
    abstract MyBox getStatus();

    //Wait utility functions
    //First call starts the timer, true is returned (and the state is reset)
    //  when the time has elapsed
    //Supports 10 independent numbered timers, default is 0

    //Standard waiting functions are based on engine.gameTime
    protected bool wait(Time t) {
        return wait(0, t);
    }

    protected bool wait(int timerId, Time t) {
        if (!mWaiting[timerId]) {
            mWaitStart[timerId] = engine.gameTime.current;
            mWaiting[timerId] = true;
        }
        if (engine.gameTime.current - mWaitStart[timerId] > t) {
            mWaiting[timerId] = false;
            return true;
        }
        return false;
    }

    protected void waitReset(int timerId = 0) {
        mWaitStart[timerId] = engine.gameTime.current;
    }

    //Local waiting functions are based on gamemode time (which can be paused
    //  independently of gameTime)
    /*protected bool waitLocal(Time t) {
        return waitLocal(0, t);
    }

    protected bool waitLocal(int timerId, Time t) {
        if (!mWaitingLocal[timerId]) {
            mWaitStartLocal[timerId] = modeTime.current;
            mWaitingLocal[timerId] = true;
        }
        if (modeTime.current - mWaitStartLocal[timerId] > t) {
            mWaitingLocal[timerId] = false;
            return true;
        }
        return false;
    }

    protected void waitResetLocal(int timerId = 0) {
        mWaitStartLocal[timerId] = modeTime.current;
    }*/
}
