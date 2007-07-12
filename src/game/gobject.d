module game.gobject;
import common.common;
import game.game;
import utils.mylist;
import utils.time;

//not really abstract, but should not be created
abstract class GameObject {
    private bool mActive;
    private GameEngine mEngine;

    //for GameEngine
    package mixin ListNodeMixin node;

    GameEngine engine() {
        return mEngine;
    }

    final void active(bool set) {
        if (set == mActive)
            return;
        mActive = set;
        if (mActive) {
            engine.activate(this);
            //std.stdio.writefln("INSERT: %s", this);
        } else {
            engine.deactivate(this);
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

    this(GameEngine aengine, bool start_active = true) {
        assert(aengine !is null);
        mEngine = aengine;
        active = start_active;
    }

    //deltaT = seconds since last frame (game time)
    void simulate(float deltaT) {
        //override this if you need game time
    }

    void kill() {
        active = false;
    }
}

