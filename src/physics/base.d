module physics.base;

import framework.drawing;

import physics.collisionmap;
import physics.misc;
import physics.world;

import utils.list2;

//if you need to check a normal when there's almost no collision (i.e. when worm
//  is sitting on ground), add this value to the radius
enum float cNormalCheck = 5;

//base type for physic objects (which are contained in a PhysicWorld)
class PhysicBase {
    ObjListNode!(typeof(this)) base_node;
    PhysicWorld mWorld;
    //set to remove object after simulation
    bool remove = false;
    //also works like remove, but will call doDie() after removal
    //various parts of the game may also read this
    //use !obj.active() to determine if an object is "in the world"
    bool dead = false;
    //in seconds
    private float mLifeTime = float.infinity;
    private float mRemainLifeTime;

    //xxx move into PhysicObject as soon as they are unified with triggers
    CollisionType collision = CollisionType_Invalid;

    //free for use by the rest of the game
    //used for collisions- and damage-reporting
    //currently is either null or stores a GObjectSprite instance
    Object backlink;

    this() {
    }

    PhysicWorld world() {
        return mWorld;
    }
    void world(PhysicWorld w) {
        mWorld = w;
        if (w) {
            addedToWorld();
        } else {
            removedFromWorld();
        }
    }

    protected void addedToWorld() {
        //override to do something when the object is added to the PhysicWorld
    }

    protected void removedFromWorld() {
        //same for remove (kill or doDie are not always called)
    }

    void lifeTime(float secs) {
        mLifeTime = secs;
        mRemainLifeTime = secs;
    }

    public void delegate() onDie;

    //called when simulation is done and this.dead was true
    //must invoke onDie if it !is null
    void doDie() {
        if (onDie)
            onDie();
    }

    final void kill() {
        dead = true;
    }

    //return if an object participates in physic simulation
    final bool active() {
        return !(dead || remove);
    }

    /+package+/ void simulate(float deltaT) {
        if (mLifeTime != float.infinity) {
            mRemainLifeTime -= deltaT;
            if (mRemainLifeTime <= 0) {
                dead = true;
            }
        }
    }

    void debug_draw(Canvas c) {
    }
}
