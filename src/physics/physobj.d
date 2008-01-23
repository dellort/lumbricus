module physics.physobj;

import std.math : PI, abs;
import utils.mylist;
import utils.vector2;

import physics.base;
import physics.posp;
import physics.movehandler;
import physics.geometry;

import std.stdio;

//simple physical object (has velocity, position, mass, radius, ...)
class PhysicObject : PhysicBase {
    package mixin ListNodeMixin objects_node;

    private POSP mPosp;
    POSP* posp() {
        //xxx sorry, this is to avoid strange effects for calls like
        //obj.posp.prop = value
        return &mPosp;
    }
    void posp(POSP p) {
        mPosp = p;
        //new POSP -> check values
        collision = world.findCollisionID(mPosp.collisionID, true);
    }

    package Vector2f mPos; //pixels

    bool isGlued;    //for sitting worms (can't be moved that easily)
    bool mHadUpdate;  //flag to see if update() has run at least once

    //in pixels per second, readonly for external code!
    package Vector2f velocity_int = {0,0};

    //constant force the object adds to itself
    //used for jetpack or flying weapons
    Vector2f selfForce = {0, 0};
    //hacky: force didn't really work for jetpack
    //Vector2f selfAddVelocity = {0, 0};

    //additional acceleration, e.g. for gravity override
    Vector2f acceleration = {0, 0};

    //set internally by PhysicWorld (and reset every simulation loop!)
    package Vector2f gravity;

    //per-frame force accumulator
    private Vector2f mForceAccum;

    final Vector2f pos() {
        return mPos;
    }

    final Vector2f velocity() {
        return velocity_int;
    }
    void setInitialVelocity(Vector2f v) {
        assert(!mHadUpdate, "setInitialVelocity is for object creation only");
        velocity_int = v;
    }

    //the worm couldn't adhere to the rock surface anymore
    //called from the PhysicWorld simulation loop only
    /+private+/ void doUnglue() {
        version(PhysDebug) world.mLog("unglue object %s", this);
        //he flies away! arrrgh!
        isGlued = false;
        mWalkingMode = false;
        mIsWalking = false;
        needUpdate();
    }

    //apply a force
    //constant forces won't unglue the object
    void addForce(Vector2f force, bool constant = false) {
        mForceAccum += force;
        if (!constant)
            doUnglue();
    }

    //apply an impulse (always unglues the object)
    //if you have to call this every frame, you're doing something wrong ;)
    void addImpulse(Vector2f impulse) {
        velocity_int += impulse * (1.0f/mPosp.mass);
        doUnglue();
    }

    private void clearAccumulators() {
        mForceAccum = Vector2f.init;
    }

    void update(float deltaT) {
        mHadUpdate = true;
        scope(exit) clearAccumulators();

        if (mPosp.mass == float.infinity) {
            //even a concrete donkey would not move that...
            return;
        }
        if (abs(selfForce.x) > float.epsilon
            || abs(selfForce.y) > float.epsilon)
        {
            doUnglue();
        }
        if (isGlued)
            return;
        //some sanity checks
        assert(mPosp.mass > 0, "Zero mass forbidden");
        assert(deltaT > 0);

        //Update velocity
        Vector2f a = gravity + acceleration
            + (mForceAccum + selfForce) * (1.0f/mPosp.mass);
        velocity_int += a * deltaT;

        //remove unwanted parts
        velocity_int = velocity.mulEntries(mPosp.fixate);

        //clip components at maximum velocity
        velocity_int = velocity.clipAbsEntries(mPosp.velocityConstraint);

        //speed limit
        if (mPosp.speedLimit > float.epsilon) {
            if (velocity_int.length > mPosp.speedLimit)
                velocity_int.length = mPosp.speedLimit;
        }

        //xxx what was that for again? seems to work fine without
        /*if (isGlued) {
            //argh. so a velocity is compared to a "force"... sigh.
            //surface_normal is valid, as objects are always glued to the ground
            if (velocity.length <= mPosp.glueForce
                && velocity*surface_normal <= 0)
            {
                //xxx: reset the velocity vector, because else, the object
                //     will be unglued even it stands on the ground
                //     this should be changed such that the object is only
                //     unglued if it actually could be moved...
                velocity = Vector2f.init;
                //skip to next object, don't change position
                return;
            }
            doUnglue();
        }*/

        //Update position
        move(velocity * deltaT);

        needUpdate();
        checkRotation();

    }

    char[] toString() {
        return str.format("[%s: %s %s]", toHash(), pos, velocity);
    }

    override /+package+/ void doRemove() {
        super.doRemove();
        //objects_node.removeFromList();
        world.mObjects.remove(this);
    }

    override void doDie() {
        //oh oops
        super.doDie();
    }

    //****************** MoveHandler *********************

    MoveHandler moveHandler;

    //(assert validity)
    private void checkHandler() {
        if (moveHandler)
            assert(moveHandler.handledObject is this);
    }

    //set new position
    //  correction = true: small fixup of the position (i.e. collision handling)
    //  correction = false: violent reset of the position (i.e. beamers)
    final void setPos(Vector2f npos, bool correction) {
        checkHandler();
        if (moveHandler) {
            moveHandler.setPosition(npos, correction);
        } else {
            mPos = npos;
        }
    }

    //move the object by this vector
    //the object might modify the vector or so on its own (ropes do that)
    final void move(Vector2f delta) {
        checkHandler();
        if (moveHandler) {
            moveHandler.doMove(delta);
        } else {
            mPos += delta;
        }
    }

    //******************** Rotation and surface normal **********************

    //direction when flying etc., just rotation of the object
    float rotation = 0;
    //last known angle to ground
    float ground_angle = 0;
    //last known surface normal
    Vector2f surface_normal;

    //set rotation (using velocity)
    public void checkRotation() {
        auto len = velocity.length;
        //xxx insert a well chosen value here
        //NOTE: this check also prevents NaNs from getting through
        //intention is that changes must be big enough to change worm direction
        if (len > 0.001) {
            rotation = (velocity/len).toAngle();
        }
    }
    //set rotation (using move-vector from oldpos to pos)
    private void checkRotation2(Vector2f oldpos) {
        Vector2f dir = pos-oldpos;
        auto len = dir.length;
        if (len > 0.001) {
            rotation = (dir/len).toAngle();
        }
    }

    //whenever this object touches the ground, call this with the depth*normal
    //  vector
    package void checkGroundAngle(Vector2f dir) {
        auto len = dir.length;
        if (len > 0.001) {
            surface_normal = (dir/len);
            ground_angle = surface_normal.toAngle();
        }
    }

    //angle where the worm looks to, or is forced to look to (i.e. when sitting)
    float lookey(bool forceGlue = false) {
        if (!isGlued || forceGlue) {
            return rotation;
        } else {
            float angle = ground_angle+PI/2;
            //hm!?!?
            auto a = Vector2f.fromPolar(1, angle);
            auto b = Vector2f.fromPolar(1, rotation);
            if (a*b < 0)
                angle += PI; //+180 degrees
            //modf sucks!
            while (angle > PI*2) {
                angle -= PI*2;
            }
            return angle;
        }
    }

    //****************** Damage and lifepower ********************

    float lifepower = float.infinity;

    void applyDamage(float severity) {
        auto delta = -severity*posp.damageable;
        //world.mLog("damage: %s/%s", severity, delta);
        if (abs(delta) > posp.damageThreshold) {
            lifepower += delta;
            needUpdate();
            //die muaha
            //xxx rather not (WormSprite is died by GameController)
            //if (lifepower <= 0)
              //  dead = true;
        }
    }

    //sry
    int lifepowerInt() {
        return cast(int)(lifepower + 0.5f);
    }

    //********** Walking code, xxx put this anywhere but not here ***********

    //used during simulation
    float walkingTime = 0; //time until next pixel will be walked on
    Vector2f walkTo; //direction
    private bool mWalkingMode;
    private bool mIsWalking;

    void setWalking(Vector2f dir) {
        walkingTime = 0;
        walkTo = dir;
        //or switch off?
        //NOTE: restrict to X axis
        if (abs(dir.x) < 0.01) {
            mWalkingMode = false;
        } else {
            //will definitely try to walk, so look into walking direction
            checkRotation2(pos-dir);
            mWalkingMode = true;
        }
        mIsWalking = false;

        needUpdate();
    }

    //if object _attempts_ to walk
    bool isWalkingMode() {
        return mWalkingMode;
    }

    //if object is walking and actually walks!
    bool isWalking() {
        return mIsWalking;
    }

    override /+package+/ void simulate(float deltaT) {
        super.simulate(deltaT);
        //take care of walking, walkingSpeed > 0 marks walking enabled
        if (isWalkingMode()) {
            walkingTime -= deltaT;
            if (walkingTime <= 0) {
                walkingTime = 1.0 / posp.walkingSpeed; //time for one pixel
                //actually walk (or try to)

                //must stand on surface when walking
                if (!isGlued) {
                    world.mLog("no walk because not glued");
                    return;
                }

                //notice update before you forget it...
                needUpdate();

                Vector2f npos = pos + walkTo;

                //look where's bottom
                //NOTE: y1 > y2 means y1 is _blow_ y2
                bool first = true;
                for (float y = +posp.walkingClimb; y >= -posp.walkingClimb; y--)
                {

                    Vector2f nnpos = npos;
                    nnpos.y += y;
                    auto tmp = nnpos;
                    //log.registerLog("xxx")("%s %s", nnpos, pos);
                    ContactData contact;
                    bool res = world.collideGeometry(nnpos, posp.radius,
                        contact);

                    if (!res) {
                        world.mLog("walk at %s -> %s", nnpos, nnpos-tmp);
                        //no collision, consider this to be bottom

                        auto oldpos = pos;

                        if (first) {
                            //even first tested location => most bottom, fall
                            world.mLog("walk: fall-bottom");
                            mPos = npos;
                            doUnglue();
                        } else {
                            world.mLog("walk: bottom at %s", y);
                            //walk to there...
                            npos.y += y;
                            mPos = npos;
                        }

                        //check worm direction...
                        //disabled because: want worm to look to the real
                        //walking direction, this breaks when walking into caves
                        //where the worm gets stuck
                        //checkRotation2(oldpos);

                        //check ground normal... not good :)
                        //maybe physics should check the normal properly
                        if (world.collideGeometry(pos, posp.radius+cNormalCheck,
                            contact))
                        {
                            checkGroundAngle(contact.depth
                                * contact.normal);
                        }

                        //jup, did walk
                        mIsWalking = true;

                        return;
                    }

                    first = false;
                }

                //if nothing was done, the worm (or the cow :) just can't walk
                mIsWalking = false;
            }
        }
    }
}
