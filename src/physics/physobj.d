module physics.physobj;

import tango.math.Math : PI, abs, isNaN;
import tango.math.IEEE : copysign;
import utils.list2;
import utils.vector2;
import utils.misc;
import utils.log;

import physics.base;
import physics.misc;
import physics.geometry;
import physics.links;

//version = WalkDebug;
version = PhysDebug;

//simple physical object (has velocity, position, mass, radius, ...)
class PhysicObject : PhysicBase {
    ObjListNode!(typeof(this)) objects_node;

    private POSP mPosp;
    private static LogStruct!("physics.obj") log;

    this() {
        //
    }

    final POSP posp() {
        return mPosp;
    }
    final void posp(POSP p) {
        argcheck(p);
        mPosp = p;
        //new POSP -> check values
        updateCollision();
        if (mPosp.fixate.x < float.epsilon || mPosp.fixate.y < float.epsilon) {
            if (!mFixateConstraint) {
                mFixateConstraint = new PhysicFixate(this, mPosp.fixate);
                if (mWorld)
                    mWorld.add(mFixateConstraint);
            }
            mFixateConstraint.fixate = mPosp.fixate;
        } else {
            if (mFixateConstraint) {
                mFixateConstraint.dead = true;
                mFixateConstraint = null;
            }
        }
    }

    override void addedToWorld() {
        super.addedToWorld();
        if (mFixateConstraint)
            mWorld.add(mFixateConstraint);
        updateCollision();
    }

    private void updateCollision() {
        collision = mPosp.collisionID;
        //no null collision ID allowed
        //if the object should never collide, must use CollisionMap.find("none")
        if (!collision)
            throw new CustomException("null collisionID");
    }

    package Vector2f mPos; //pixels
    private PhysicFixate mFixateConstraint;

    private bool mIsGlued;    //for sitting worms (can't be moved that easily)

    bool isGlued() {
        return mIsGlued;
    }
    package void glueObject() {
        mIsGlued = true;
        //velocity must be set to 0 (or change glue handling)
        //ok I did change glue handling.
        velocity_int = Vector2f(0);
    }

    bool mHadUpdate;  //flag to see if update() has run at least once
    bool mOnSurface;
    int mSurfaceCtr;

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
    package Vector2f lastPos;

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
        if (!isGlued)
            return;
        version(PhysDebug) log("unglue object {}", this);
        //he flies away! arrrgh!
        mIsGlued = false;
        //mWalkingMode = false; (no! object _wants_ to walk, and continue
        //                       when glued again)
        mIsWalking = false;
        mOnSurface = false;
    }

    //apply a force
    //constant forces won't unglue the object
    void addForce(Vector2f force, bool constant = false) {
        mForceAccum += force;
        if (!constant) {
            doUnglue();
        }
    }

    //apply an impulse (always unglues the object)
    //if you have to call this every frame, you're doing something wrong ;)
    //impulses from geometry will cause fall damage
    void addImpulse(Vector2f impulse,
        ContactSource source = ContactSource.object)
    {
        velocity_int += impulse * mPosp.inverseMass;
        if (source == ContactSource.geometry) {
            if (!isGlued) {
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
                    applyDamage(damage, DamageCause.fall);
            }
            if (velocity_int.length < mPosp.glueForce && surface_normal.y < 0) {
                //we collided with geometry, but were not fast enough!
                //  => worm gets glued, hahaha.
                //xxx maybe do the gluing somewhere else?
                glueObject;
                version(PhysDebug) log("glue object {}", this);
            }
        }
        if (source == ContactSource.object) {
            doUnglue();
        }
    }

    private void clearAccumulators() {
        mForceAccum = Vector2f.init;
    }

    bool onSurface() {
        return mSurfaceCtr > 0;
    }

    void update(float deltaT) {
        mHadUpdate = true;
        scope(exit) {
            clearAccumulators();
        }

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
        assert(deltaT >= 0);

        if (mOnSurface || mSurfaceCtr > 0) {
            //sliding on surface, so apply friction
            //velocity relative to surface
            Vector2f vrel =
                velocity_int.project_vector(surface_normal.orthogonal);
            float len = vrel.length;
            if (len > 0.1f) {
                //all forces on object
                Vector2f fAll = (gravity + acceleration)*mPosp.mass
                    + mForceAccum + selfForce;
                //normal force
                Vector2f fN = fAll.project_vector(-surface_normal);
                if (mSurfaceCtr < 0) {
                    //start sliding, so stop if not fast enough
                    //xxx kind of a hack to allow worms to jump normally
                    if (len < mPosp.slideAbsorb)
                        //remove vrel component from velocity
                        velocity_int -= vrel;
                } else {
                    float friction = mPosp.friction * surface_friction;
                    mForceAccum += -friction*fN.length*(vrel/len);
                }
            }
        }

        if (mOnSurface)
            mSurfaceCtr = max(mSurfaceCtr+1, 4);
        else
            mSurfaceCtr = min(mSurfaceCtr-1, 4);
        mOnSurface = false;

        //Update velocity
        Vector2f a = acceleration
            + (mForceAccum + selfForce) * mPosp.inverseMass;
        if (!mPosp.zeroGrav)
            a += gravity;
        velocity_int += a * deltaT;

        //clip components at maximum velocity
        velocity_int = velocity.clipAbsEntries(mPosp.velocityConstraint);

        //speed limit
        //xxx hardcoded, but I didn't want to add another dependency on "world"
        //  yet (better sort this out later; circular dependencies etc.)
        const float cMaxSpeed = 2000; //global max limit
        auto speed = velocity_int.length;
        if (speed > mPosp.speedLimit) {
            velocity_int.length = mPosp.speedLimit;
        } else if (speed > cMaxSpeed) {
            velocity_int.length = cMaxSpeed;
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

        checkRotation();
    }

    char[] toString() {
        return myformat("[{}: {} {}]", toHash(), pos, velocity);
    }

    //set new position
    //  correction = true: small fixup of the position (i.e. collision handling)
    //  correction = false: violent reset of the position (i.e. beamers)
    //xxx correction not used anymore, because we have constraints now
    final void setPos(Vector2f npos, bool correction) {
        mPos = npos;
        if (mFixateConstraint && !correction)
            mFixateConstraint.updatePos();
        if (!correction)
            lastPos.x = lastPos.y = float.nan; //we don't know a safe position
    }

    //move the object by this vector
    final void move(Vector2f delta) {
        mPos += delta;
        if (mPosp.rotation == RotateMode.distance) {
            //rotation direction depends from x direction (looks better)
            auto dist = copysign(delta.length(), delta.x);
            rotation += dist/200*2*PI;
        }
    }

    //******************** Rotation and surface normal **********************

    //direction when flying etc., just rotation of the object
    float rotation = 0;
    //last known angle to ground
    float ground_angle = 0;
    //last known surface normal
    Vector2f surface_normal;
    //last known surface friction multiplier
    float surface_friction = 1.0f;
    //return value of lookey(), but smoothened over time
    //introduced because rotation changes chaotically
    float lookey_smooth() {
        return lookey();
    }

    //angle where the worm wants to look to
    //the worm is mostly forced to look somewhere else, but when there's still
    //some degree of freedom, this is used
    //(e.g. worm sits -> angle must fit to ground, but could look left or right)
    //automatically set to walking direction when walking is started,
    //and to flying direction during flying
    private Vector2f mIntendedLook = Vector2f.nan;

    //set rotation (using velocity)
    public void checkRotation() {
        switch (mPosp.rotation) {
            case RotateMode.velocity:
                //when napalm-spamming, 5% of execution time is spent in the
                //  atan2l function called by toAngle()
                rotation = velocity.toAngle();
                break;
            case RotateMode.selfforce:
                auto ndir = selfForce.normal();
                if (!ndir.isNaN()) {
                    //special case: moving straight up/down
                    //jetpack is either left or right, so keep last direction
                    if (ndir.x != 0)
                        mIntendedLook = ndir;
                }
                break;
            default:
        }
    }

    //whenever this object touches the ground, call this with the depth*normal
    //  vector
    package void checkGroundAngle(GeomContact contact) {
        Vector2f dir = contact.normal*contact.depth;
        auto len = dir.length;
        if (len > 0.001) {
            surface_normal = contact.normal;
            surface_friction = contact.friction;
            ground_angle = surface_normal.toAngle();
            mOnSurface = true;
        }
    }

    //manual reset of mIntendedLook
    void resetLook() {
        mIntendedLook = Vector2f.nan;
    }

    void forceLook(Vector2f l) {
        mIntendedLook = l.normal;
    }

    //angle where the worm looks to, or is forced to look to (i.e. when sitting)
    float lookey() {
        if (!isGlued || !mPosp.gluedForceLook) {
            if (mIntendedLook.isNaN)
                //no forced looking direction available
                return rotation;
            else
                //when flying and forced rotation is set, always use it
                return mIntendedLook.toAngle;
        } else {
            //glued but look invalid -> use last rotation
            auto look = mIntendedLook;
            if (look.isNaN)
                look = Vector2f(1,0); //default if no look dir ws set yet
            //glued, use left/right from mIntendedLook and
            //combine with surface normal
            auto a = surface_normal.orthogonal;    //parallel to surface
            auto b = look;                //walking direction
            float sp = a*b;
            if (sp < 0) {
                a = -a;     //invert for right looking direction
                sp = -sp;
            }

            //check for 90 deg special case (both vectors are normalized)
            if (sp < 0.1) {
                //don't allow 90/270 deg, instead modify the vector
                //to point into intended look direction
                a += 0.1*b;
            }
            return a.toAngle();  //lol
        }
    }

    //****************** Damage and lifepower ********************

    public void delegate(float amout, DamageCause type, Object cause) onDamage;
    float lifepower = float.infinity;

    void applyDamage(float severity, DamageCause type, Object cause = null) {
        auto delta = -severity*posp.damageable;
        //log("damage: {}/{}", severity, delta);
        if (abs(delta) > posp.damageThreshold) {
            float before = lifepower;
            lifepower += delta;
            //make sure object is dead if lifepowerInt() reports <= 0
            if (lifepower < 0.5f && lifepower > 0f)
                lifepower = 0f;
            if (mPosp.damageUnfixate && mFixateConstraint) {
                mFixateConstraint.dead = true;
                mFixateConstraint = null;
            }
            float diff = before - lifepower;
            //corner cases; i.e. invincible worm
            if (diff != diff || diff == typeof(diff).infinity)
                diff = 0;
            if (diff != 0 && onDamage && !dead) {
                onDamage(diff, type, cause);
            }
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
    Vector2f walkTo; //direction
    private bool mWalkingMode;
    private bool mIsWalking;
    private bool mWalkStopAtCliff;

    void setWalking(Vector2f dir, bool stopAtCliff = false) {
        dir.y = 0;
        walkTo = dir;
        //or switch off?
        //NOTE: restrict to X axis
        if (abs(dir.x) < 0.01) {
            if (!mWalkingMode)
                return;
            mWalkingMode = false;
            if (mIsWalking) {
                mIsWalking = false;
            }
        } else {
            //will definitely try to walk, so look into walking direction
            mWalkingMode = true;
        }
        mWalkStopAtCliff = stopAtCliff;
    }

    //if object _attempts_ to walk
    bool isWalkingMode() {
        return mWalkingMode;
    }

    //if object is walking and actually walks!
    bool isWalking() {
        return mIsWalking;
    }

    //xxx reserved for later, refactor out
    //(thinking of non-linear movement)
    Vector2f calcDist(float deltaT, Vector2f dir, float speed) {
        return dir * speed * deltaT;
    }

    override /+package+/ void simulate(float deltaT) {
        super.simulate(deltaT);
        //take care of walking, walkingSpeed > 0 marks walking enabled
        if (isWalkingMode()) {
            mIsWalking = false;  //set to true again if object could walk
            Vector2f walkDist = calcDist(deltaT, walkTo, posp.walkingSpeed);
            //actually walk (or try to)

            //must stand on surface when walking
            if (!isGlued) {
                version(WalkDebug) log("no walk because not glued");
                return;
            }

            bool hitLast = true;   //did the last test hit any landscape?
            //look where's bottom
            //NOTE: y1 > y2 means y1 is _below_ y2
            //      take pixel steps
            //scan from top down for first walkable ground
            for (float y = -posp.walkingClimb; y <= +posp.walkingClimb; y++) {
                Vector2f npos = pos + walkDist;
                npos.y += y;
                GeomContact contact;
                bool res = world.collideGeometry(npos, posp.radius, contact);
                //also check with objects
                res |= world.collideObjectsW(npos, posp.radius, this);

                if (!res) {
                    //we found a free area where the worm would fit
                    hitLast = false;
                } else if (!hitLast) {
                    //hit the landscape, but worm would fit on last checked pos
                    //  --> walk there
                    version(WalkDebug) log("walk: bottom at {}", y);
                    y--;
                    version(WalkDebug) log("walk at {} -> {}", npos, npos-mPos);
                    //walk to there...
                    if (mPosp.walkLimitSlopeSpeed) {
                        //one pixel at a time, even on steep slopes
                        //xxx waiting y/walkingSpeed looks odd, but
                        //    would be more correct
                        if (abs(y) <= 1)
                            mPos += walkDist;
                        if (y > 0)
                            mPos.y += 1;
                        else if (y < 0)
                            mPos.y -= 1;
                    } else {
                        //full heigth diff at one, constant x speed
                        mPos += walkDist;
                        mPos.y += y;
                    }
                    hitLast = true;

                    //jup, did walk
                    mIsWalking = true;
                    break;
                }
            }

            if (!hitLast) {
                //no hit at all => most bottom, fall
                version(WalkDebug) log("walk: fall-bottom");
                //if set, don't fall, but stop (mIsWalking will be false)
                if (!mWalkStopAtCliff) {
                    mPos += walkDist;
                    doUnglue();
                    mIsWalking = true;
                }
            }

            if (mIsWalking) {
                //check ground normal... not good :)
                //maybe physics should check the normal properly
                GeomContact contact;
                if (world.collideGeometry(pos, posp.radius+cNormalCheck,
                    contact))
                {
                    checkGroundAngle(contact);
                }

                auto ndir = walkDist.normal();
                if (!ndir.isNaN())
                    mIntendedLook = ndir;
            }
            //if nothing was done, the worm (or the cow :) just can't walk
        }
    }
}
