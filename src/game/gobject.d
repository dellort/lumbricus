module game.gobject;

import framework.drawing : Canvas;
import game.game;
import game.events;
import utils.list2;
import utils.reflection;
import utils.time;

import net.marshal : Hasher;

abstract class GameObject : EventTarget {
    private bool mInternalActive;
    private GameEngine mEngine;

    //for the controller
    GameObject createdBy;

    //for GameEngine
    ObjListNode!(typeof(this)) node;

    this(GameEngine aengine, char[] event_target_type) {
        assert(aengine !is null);
        super(event_target_type);
        mEngine = aengine;
        //starts out with internal_active == false
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

    //for GameObject, the only meaning of this is whether simulate() should be
    //  called; that's also the reason why the getter/setter is protected
    protected final void internal_active(bool set) {
        if (set == mInternalActive)
            return;
        mInternalActive = set;
        if (mInternalActive) {
            engine.ensureAdded(this);
        }
        updateInternalActive();
    }

    protected final bool internal_active() {
        return mInternalActive;
    }

    //only for game.d, stay away
    package bool _is_active() {
        return mInternalActive;
    }

    //called after internal_active-value updated
    protected void updateInternalActive() {
    }

//    //after creating a game object, start it
//    abstract void activate();

    //return true if its active in the sense of a game-round
    abstract bool activity();

    //deltaT = seconds since last frame (game time)
    //only called when internal_active == true
    void simulate(float deltaT) {
        //override this if you need game time
    }

    void kill() {
        internal_active = false;
    }

    void hash(Hasher hasher) {
        hasher.hash(mInternalActive);
    }

    //can be used to draw for debugging
    //why not use it for normal game rendering, instead of using that crap in
    //  gamepublic.d? I have no ducking clue...
    void debug_draw(Canvas c) {
    }
}

