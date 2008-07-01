module physics.physobj;

import std.math : PI, abs;
import utils.mylist;
import utils.vector2;
import utils.misc: max;

import physics.base;
import physics.posp;
import physics.movehandler;
import physics.geometry;

//simple physical object (has velocity, position, mass, radius, ...)
class PhysicObject : PhysicBase {
    package mixin ListNodeMixin objects_node;

    private POSP mPosp;

    this() {
        //
    }

    POSP posp() {
        return mPosp;
    }
    void posp(POSP p) {
        mPosp = p;
        //new POSP -> check values
        collision = world.collide.findCollisionID(mPosp.collisionID);
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
        //mWalkingMode = false; (no! object _wants_ to walk, and continue
        //                       when glued again)
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
    //impulses from geometry will cause fall damage
    void addImpulse(Vector2f impulse, bool fromGeom = false) {
        velocity_int += impulse * mPosp.inverseMass;
        if (fromGeom) {
            //hit against geometry -> fall damage
            float impulseLen;
            if (mPosp.fallDamageIgnoreX)
                //just vertical component
                impulseLen = abs(impulse.y);
            else
                //full impulse
                impulseLen = impulse.length;
            //simple linear dependency
            float damage = max(impulseLen - mPosp.sustainableImpulse, 0f)
                * mPosp.fallDamageFactor;
            //use this for damage
            if (damage > 0)
                applyDamage(damage);
        }
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

    //angle where the worm wants to look to
    //the worm is mostly forced to look somewhere else, but when there's still
    //some degree of freedom, this is used
    //(e.g. worm sits -> angle must fit to ground, but could look left or right)
    //automatically set to walking direction when walking is started,
    //and to flying direction during flying
    private float mIntendedLookAngle = 0;

    //set rotation (using velocity)
    public void checkRotation() {
        if (posp.jetpackLooking) {
            auto ndir = selfForce.normal();
            if (!ndir.isNaN()) {
                //special case: moving straight up/down
                //jetpack is either left or right, so keep last direction
                if (ndir.x != 0)
                    mIntendedLookAngle = ndir.toAngle();
            }
            return;
        }

        auto len = velocity.length;
        //xxx insert a well chosen value here
        //NOTE: this check also prevents NaNs from getting through
        //intention is that changes must be big enough to change worm direction
        if (len > 0.001) {
            rotation = (velocity/len).toAngle();
            mIntendedLookAngle = rotation; //(set only when unglued)
        }
    }
    //set rotation (using move-vector from oldpos to pos)
    /+
    private void checkRotation2(Vector2f oldpos) {
        Vector2f dir = pos-oldpos;
        auto len = dir.length;
        if (len > 0.001) {
            rotation = (dir/len).toAngle();
            checkRotation();
        }
    }
    +/

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
    float lookey() {
        if (posp.jetpackLooking)
            return mIntendedLookAngle;
        if (!isGlued) {
            return rotation;
        } else {
            float angle = ground_angle+PI/2;
            //hm!?!?
            auto a = Vector2f.fromPolar(1, angle);
            auto b = Vector2f.fromPolar(1, mIntendedLookAngle);
            float sp = a*b;
            if (sp < 0) {
                a = -a;     //invert for right looking direction
                sp = -sp;
            }

            //check for 90 deg special case (both vectors are normalized)
            if (sp < 0.01) {
                //don't allow 90/270 deg, instead modify the vector
                //to point into intended look direction
                a += 0.01*b;
            }
            angle = a.toAngle();  //lol
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
        dir.y = 0;
        walkingTime = 0;
        walkTo = dir;
        //or switch off?
        //NOTE: restrict to X axis
        if (abs(dir.x) < 0.01) {
            if (!mWalkingMode)
                return;
            mWalkingMode = false;
            if (mIsWalking) {
                mIsWalking = false;

                needUpdate();
            }
        } else {
            //will definitely try to walk, so look into walking direction
            mWalkingMode = true;
        }
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

                //checkRotation2(pos-walkTo);

                //look where's bottom
                //NOTE: y1 > y2 means y1 is _blow_ y2
                bool first = true;
                for (float y = +posp.walkingClimb; y >= -posp.walkingClimb; y--)
                {

                    Vector2f npos = pos + walkTo;
                    npos.y += y;
                    GeomContact contact;
                    bool res = world.collideGeometry(npos, posp.radius,
                        contact);

                    if (!res) {
                        world.mLog("walk at %s -> %s", npos, npos-mPos);
                        //no collision, consider this to be bottom

                        auto oldpos = pos;

                        if (first) {
                            //even first tested location => most bottom, fall
                            world.mLog("walk: fall-bottom");
                            mPos += walkTo;
                            doUnglue();
                        } else {
                            world.mLog("walk: bottom at %s", y);
                            //walk to there...
                            if (mPosp.walkLimitSlopeSpeed) {
                                //one pixel at a time, even on steep slopes
                                //xxx waiting y/walkingSpeed looks odd, but
                                //    would be more correct
                                if (abs(y) <= 1)
                                    mPos += walkTo;
                                if (y > 0)
                                    mPos.y += 1;
                                else if (y < 0)
                                    mPos.y -= 1;
                            } else {
                                //full heigth diff at one, constant x speed
                                mPos += walkTo;
                                mPos.y += y;
                            }
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

                        auto ndir = walkTo.normal();
                        if (!ndir.isNaN())
                            mIntendedLookAngle = ndir.toAngle();

                        //notice update before you forget it...
                        needUpdate();

                        return;
                    }

                    first = false;
                }

                //if nothing was done, the worm (or the cow :) just can't walk
                if (mIsWalking) {
                    mIsWalking = false;
                    //only if state actually changed
                    needUpdate();
                }
            }
        }
    }
}
