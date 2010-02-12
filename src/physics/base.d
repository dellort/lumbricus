module physics.base;

import utils.list2;

import physics.world;

//if you need to check a normal when there's almost no collision (i.e. when worm
//  is sitting on ground), add this value to the radius
final float cNormalCheck = 5;

//the physics stuff uses an ID to test if collision between objects is wanted
//all physic objects (type PhysicBase) have an CollisionType
//ok, it's not really an integer ID anymore, but has the same purpose
class CollisionType {
    char[] name;
    bool undefined = true; //true if this is an unresolved forward reference

    //index into the collision-matrix
    int index;

    //needed because of forward referencing etc.
    CollisionType superclass;
    CollisionType[] subclasses;

    this() {
    }
}

//it's illegal to use CollisionType_Invalid in PhysicBase.collision
const CollisionType CollisionType_Invalid = null;

//base type for physic objects (which are contained in a PhysicWorld)
class PhysicBase {
    ObjListNode!(typeof(this)) base_node;
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

    this() {
    }

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

    void kill() {
        dead = true;
    }

    /+package+/ void simulate(float deltaT) {
        if (mLifeTime != float.infinity) {
            mRemainLifeTime -= deltaT;
            if (mRemainLifeTime <= 0) {
                dead = true;
            }
        }
    }
}
