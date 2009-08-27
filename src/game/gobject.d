module game.gobject;

import framework.drawing : Canvas;
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
    ObjListNode!(typeof(this)) node;

    GameEngine engine() {
        return mEngine;
    }

    protected final void active(bool set) {
        if (set == mActive)
            return;
        mActive = set;
        if (mActive) {
            engine.ensureAdded(this);
        }
        updateActive();
    }

    protected final bool active() {
        return mActive;
    }

    //only for game.d, stay away
    package bool _is_active() {
        return mActive;
    }

    //called after active-value updated
    protected void updateActive() {
    }

//    //after creating a game object, start it
//    abstract void activate();

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
        hasher.hash(mActive);
    }

    //can be used to draw for debugging
    //why not use it for normal game rendering, instead of using that crap in
    //  gamepublic.d? I have no fucking clue...
    void debug_draw(Canvas c) {
    }
}

