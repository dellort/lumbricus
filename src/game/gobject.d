module game.gobject;

import framework.drawing : Canvas;
import game.game;
import game.events;
import utils.list2;
import utils.misc;
import utils.time;

import net.marshal : Hasher;

//hurf
//"abstract" Team, so that not all of the game has to depend from controller.d
/+
class TeamRef : GameObject {
    this(GameEngine aengine, char[] atype) {
        super(aengine, atype);
    }
}
+/

abstract class GameObject : EventTarget {
    private bool mIsAlive;
    private bool mInternalActive;
    private GameEngine mEngine;

    //for the controller
    //TeamRef createdBy;
    GameObject createdBy;

    //for GameEngine
    ObjListNode!(typeof(this)) sim_node, all_node;

    //event_target_type: not needed anymore, but leaving it in for now
    //  basically should give the type of the game object as a string
    this(GameEngine aengine, char[] event_target_type) {
        assert(aengine !is null);
        super(event_target_type, aengine.events);
        mEngine = aengine;
        mIsAlive = true;
        engine._object_created(this);
        //starts out with internal_active == false
    }

    final GameEngine engine() {
        return mEngine;
    }

    //for GameObject, the only meaning of this is whether simulate() should be
    //  called; that's also the reason why the getter/setter is protected
    protected final void internal_active(bool set) {
        if (set == mInternalActive)
            return;
        mInternalActive = set;
        if (mInternalActive) {
            if (!mIsAlive)
                throw new CustomException("setting active=true for a dead object");
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

    final bool objectAlive() {
        return mIsAlive;
    }

    protected void onKill() {
    }

    //when kill() is called, the object is considered to be deallocated on the
    //  next game frame (actually, it may be left to the GC or something, but
    //  we need explicit lifetime for scripting)
    //questionable whether this should be public or protected; public for now,
    //  because it was already public before
    final void kill() {
        if (!mIsAlive)
            return;
        mIsAlive = false;
        onKill();
        internal_active = false;
        engine._object_killed(this);
    }

    //this is a hack
    //some code (wcontrol.d) wants to keep the sprite around, even if it's dead
    //for now I didn't want to change this; but one other hack clears all memory
    //  of a game object to make sure anyone using it will burn his fingers, so
    //  the possibility of not stomping an object had to be introduced
    //Note that this doesn't change semantics (the object will be dead even with
    //  "vetos" added), it just disables the stomping debug code for this object
    //to remove this hack, either...
    //  1. disable stomping, remove this call, and go on normally, or
    //  2. search for code calling killVeto() and fix it
    package Object[] dontDieOnMe;
    final void killVeto(Object user) {
        dontDieOnMe ~= user;
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

