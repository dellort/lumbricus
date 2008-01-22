module physics.base;

import utils.mylist;

import physics.world;

//if you need to check a normal when there's almost no collision (i.e. when worm
//  is sitting on ground), add this value to the radius
final float cNormalCheck = 5;

//the physics stuff uses an ID to test if collision between objects is wanted
//all physic objects (type PhysicBase) have an CollisionType
typedef uint CollisionType;
const CollisionType_Invalid = uint.max;

alias void delegate(PhysicBase a, PhysicBase b) CollideDelegate;

//base type for physic objects (which are contained in a PhysicWorld)
class PhysicBase {
    package mixin ListNodeMixin allobjects_node;
    //private bool mNeedSimulation;
    private bool mNeedUpdate;
    PhysicWorld mWorld;
    //set to remove object after simulation
    bool dead = false;
    //in seconds
    private float mLifeTime = float.infinity;
    private float mRemainLifeTime;

    CollisionType collision = CollisionType_Invalid;

    //free for use by the rest of the game
    //used for collisions- and damage-reporting
    //currently is either null or stores a GObjectSprite instance
    Object backlink;

    PhysicWorld world() {
        return mWorld;
    }
    void world(PhysicWorld w) {
        mWorld = w;
        if (w) {
            addedToWorld();
        }
    }

    protected void addedToWorld() {
        //override to do something when the object is added to the PhysicWorld
    }

    //call when object should be notified with doUpdate() after all physics done
    void needUpdate() {
        mNeedUpdate = true;
    }
    package bool needsUpdate() {
        return mNeedUpdate;
    }

    void lifeTime(float secs) {
        mLifeTime = secs;
        mRemainLifeTime = secs;
    }

    public void delegate() onUpdate;
    public void delegate() onDie;

    //called when simulation is done and this.dead was true
    //must invoke onDie if it !is null
    void doDie() {
        if (onDie)
            onDie();
    }

    //feedback to other parts of the game
    package void doUpdate() {
        mNeedUpdate = false;
        if (onUpdate) {
            onUpdate();
        }
        //world.mLog("update: %s", this);
    }

    /+package+/ void simulate(float deltaT) {
        if (mLifeTime != float.infinity) {
            mRemainLifeTime -= deltaT;
            if (mRemainLifeTime <= 0) {
                dead = true;
            }
        }
    }

    /+package+/ void doRemove() {
        //allobjects_node.removeFromList();
        world.mAllObjects.remove(this);
    }
}