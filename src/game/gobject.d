module game.gobject;

import framework.drawing : Canvas;
import game.game;
import game.events;
import utils.list2;
import utils.reflection;
import utils.time;

import net.marshal : Hasher;

abstract class GameObject : EventTarget {
    private bool mActive;
    private GameEngine mEngine;

    //for the controller
    GameObject createdBy;

    //for GameEngine
    ObjListNode!(typeof(this)) node;

    this(GameEngine aengine, char[] event_target_type) {
        assert(aengine !is null);
        super(event_target_type);
        mEngine = aengine;
        active = false;
    }

    this (ReflectCtor c) {
        super("");
    }

    final GameEngine engine() {
        return mEngine;
    }

    final override Events eventsBase() {
        return mEngine.events;
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
    //  gamepublic.d? I have no ducking clue...
    void debug_draw(Canvas c) {
    }
}

