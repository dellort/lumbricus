module game.gobject;

import game.game;
import utils.list2;
import utils.reflection;
import utils.time;

import net.marshal : Hasher;

//not really abstract, but should not be created
abstract class GameObject {
    private bool mActive;
    private GameEngine mEngine;

    //for the controller
    GameObject createdBy;

    //for GameEngine
    ListNode!(typeof(this)) node;

    GameEngine engine() {
        return mEngine;
    }

    final void active(bool set) {
        if (set == mActive)
            return;
        mActive = set;
        if (mActive) {
            engine.ensureAdded(this);
        }
        updateActive();
    }

    final bool active() {
        return mActive;
    }

    //called after active-value updated
    protected void updateActive() {
    }

    //return true if its active in the sense of a game-round
    abstract bool activity();

    this(GameEngine aengine, bool start_active = true) {
        assert(aengine !is null);
        mEngine = aengine;
        active = start_active;
    }

    this (ReflectCtor c) {
    }

    //deltaT = seconds since last frame (game time)
    void simulate(float deltaT) {
        //override this if you need game time
    }

    void kill() {
        active = false;
    }

    void hash(Hasher hasher) {
    }
}

