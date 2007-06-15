module game.gobject;
import game.common;
import game.game;
import utils.mylist;
import utils.time;

import std.stdio;

interface GameObjectHandler {
    void activate(GameObject obj);

    void deactivate(GameObject obj);
}

//not really abstract, but should not be created
abstract class GameObject {
    private bool mActive;
    private GameObjectHandler mHandler;
    private GameEngine mEngine;

    //for GameEngine
    package mixin ListNodeMixin node;

    GameObjectHandler handler() {
        return mHandler;
    }

    GameEngine engine() {
        return mEngine;
    }

    final void active(bool set) {
        if (set == mActive)
            return;
        mActive = set;
        if (mActive) {
            handler.activate(this);
            //engine.mObjects.insert_tail(this);
            //std.stdio.writefln("INSERT: %s", this);
        } else {
            handler.deactivate(this);
            //engine.mObjects.remove(this);
            //std.stdio.writefln("REMOVE: %s", this);
        }
        updateActive();
    }

    final bool active() {
        return mActive;
    }

    //called after active-value updated
    protected void updateActive() {
    }

    this(GameObjectHandler handler, GameEngine engine, bool start_active = true) {
        assert(handler !is null);
        mEngine = engine;
        mHandler = handler;
        if (start_active)
            active = true;
    }

    //deltaT = seconds since last frame (game time)
    void simulate(float deltaT) {
        //override this if you need game time
    }

    void kill() {
        active = false;
    }
}

