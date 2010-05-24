module physics.physobj;

import framework.drawing;

import tango.math.Math : PI, abs, isNaN;
import tango.math.IEEE : copysign;
import utils.list2;
import utils.log;
import utils.misc;
import utils.rect2;
import utils.vector2;

import physics.base;
import physics.collide;
import physics.contact;
import physics.links;
import physics.misc;
import physics.plane;


debug {
    //version = WalkDebug;
    version = PhysDebug;
}

alias ObjectList!(PhysicObject, "objects_node") PhysicObjectList;

//simple physical object (has velocity, position, mass, radius, ...)
//NOTE: for now, this is abstract, and subclasses define the actual shape -
//      feel free to make it more like normal physic engines (separate Shape
//      objects?), but it's not like we support rigid bodies
class PhysicObject : PhysicBase {
    ObjListNode!(typeof(this)) objects_node;

    //call updatePos() to update this from position/radius
    protected Rect2f mBB;

    private {
        POSP mPosp;
        bool mIsStatic;
        debug static LogStruct!("physics.obj") log;
    }

    package {
        //for collision function dispatch
        //both values are generated by the subclasses, and passed to the
        //  collision dispatcher function
        //stupidly, both variables are actually constant compared to the
        //  object's class or this ptr => waste of bytes
        //could make a virtual function instead to retrieve this, which would
        //  make it slightly slower (and needs slightly more lines of code)
        void* shape_ptr;    //mostly constant offset to this ptr
        uint shape_id;      //constant for each .classinfo
    }

    protected this(void* a_shape_ptr, uint a_shape_id) {
        shape_ptr = a_shape_ptr;
        shape_id = a_shape_id;
        //yyy crap, remove later
        mPosp = new POSP();
    }

    //must be overridden by shape subclasses to update position and bb
    abstract void updatePos();

    final bool isStatic() {
        return mIsStatic;
    }
    final void isStatic(bool set) {
        //there are different lists for static/non-static
        if (world)
            throw new CustomException("can't change isStatic while added");
        mIsStatic = set;
        mIsGlued = !mIsStatic;
    }

    final POSP posp() {
        return mPosp;
    }
    final void posp(POSP p) {
        argcheck(p);
        mPosp = p;
        updatePos();
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

    override void removedFromWorld() {
        super.removedFromWorld();
        //make sure the constraint is removed, too
        //xxx because you can't be sure the constraint will actually be removed
        //    in the same world loop, I added another check
        //    in PhysicFixate.process()
        if (mFixateConstraint) {
            mFixateConstraint.dead = true;
        }
    }

    private void updateCollision() {
        collision = mPosp.collisionID;
        //yyy shitty legacy hack, remove later
        if (isStatic && world) {
            collision = world.collide.find("ground");
            mPosp.mass = float.infinity;
        }
        //no null collision ID allowed
        //if the object should never collide, must use CollisionMap.none()
        if (!collision)
            throw new CustomException("null collisionID");
    }

    //hopefully inlined, extensively used by broadphase, performance critical
    final Rect2f bb() {
        return mBB;
    }

    //xxx: one could just replace mPos by bb.center, or an abstract function
    //     PhysicObjectCircle stores its own position anyway
    private Vector2f mPos; //pixels, call updatePos() when changing
    private PhysicFixate mFixateConstraint;

    private bool mIsGlued;    //for sitting worms (can't be moved that easily)

    final bool isGlued() {
        return mIsGlued;
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
    //xxx nobody actually uses this
    Vector2f acceleration = {0, 0};

    //set internally by PhysicWorld (and reset every simulation loop!)
    package Vector2f lastPos;

    //per-frame force accumulator
    private Vector2f mForceAccum;

    //acceleration + gravity (without other forces)
    //xxx couldn't one use mForceAccum everywhere instead?
    //    e.g. mForceAccum += fullAcceleration * psop.mass
    //    or introduce use mAccelerationAccum, or whatever
    //    contact resolver still needs acceleration for some reason (bug?)
    final Vector2f fullAcceleration() {
        assert(!!world);
        return acceleration + (mPosp.zeroGrav ? Vector2f(0) : world.gravity);
    }

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

    package void glueObject() {
        version(PhysDebug) log("glue object {}", this);
        mIsGlued = true;
        //velocity must be set to 0 (or change glue handling)
        //ok I did change glue handling.
        velocity_int = Vector2f(0);
    }

    //the worm couldn't adhere to the rock surface anymore
    //called from the PhysicWorld simulation loop only
    final void doUnglue() {
        if (!isGlued)
            return;
        if (isStatic)
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
    final void addForce(Vector2f force, bool constant = false) {
        mForceAccum += force;
        if (!constant) {
            doUnglue();
        }
    }

    //apply an impulse (always unglues the object)
    //if you have to call this every frame, you're doing something wrong ;)
    //impulses from geometry will cause fall damage
    final void addImpulse(Vector2f impulse,
        ContactSource source = ContactSource.object)
    {
        if (isStatic)
            return;

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
            }
        } else if (source == ContactSource.object) {
            doUnglue();
        }
    }

    private void clearAccumulators() {
        mForceAccum = Vector2f.init;
    }

    final bool onSurface() {
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
                Vector2f fAll = fullAcceleration*mPosp.mass
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
            mSurfaceCtr = min(mSurfaceCtr+1, 4);
        else
            mSurfaceCtr = max(mSurfaceCtr-1, 0);
        mOnSurface = false;

        //Update velocity
        Vector2f a = fullAcceleration
            + (mForceAccum + selfForce) * mPosp.inverseMass;
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

        //Update position
        move(velocity * deltaT);
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
        updatePos();
        if (mFixateConstraint && !correction)
            mFixateConstraint.updatePos();
        if (!correction)
            lastPos.x = lastPos.y = float.nan; //we don't know a safe position
    }

    //move the object by this vector
    final void move(Vector2f delta) {
        mPos += delta;
        updatePos();
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
    final void checkRotation() {
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
    //xxx special cased to be called in static object collisions
    package void checkGroundAngle(Contact contact) {
        if (contact.depth > 0.001) {
            surface_normal = contact.normal;
            surface_friction = 1.0; //contact.friction;
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
    final float lookey() {
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
            //xxx rather not (objects are died by the game logic)
            //if (lifepower <= 0)
              //  dead = true;
        }
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
        void updatePos(Vector2f p) {
            //xxx: not sure about correction parameter
            setPos(p, true);
        }
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
                Contact contact;
                bool res = world.collideGeometry(npos, posp.radius, contact);
                //also check with objects
                res |= world.collideObjectsW(npos, this);

                if (!res) {
                    //we found a free area where the worm would fit
                    hitLast = false;
                } else if (!hitLast) {
                    //hit the landscape, but worm would fit on last checked pos
                    //  --> walk there
                    version(WalkDebug) log("walk: bottom at {}", y);
                    y--;
                    version(WalkDebug) log("walk at {} -> {}", npos, npos-pos);
                    //walk to there...
                    Vector2f fpos = pos;
                    if (mPosp.walkLimitSlopeSpeed) {
                        //one pixel at a time, even on steep slopes
                        //xxx waiting y/walkingSpeed looks odd, but
                        //    would be more correct
                        if (abs(y) <= 1)
                            fpos += walkDist;
                        if (y > 0)
                            fpos.y += 1;
                        else if (y < 0)
                            fpos.y -= 1;
                    } else {
                        //full heigth diff at one, constant x speed
                        fpos += walkDist;
                        fpos.y += y;
                    }
                    hitLast = true;

                    updatePos(fpos);

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
                    updatePos(pos + walkDist);
                    doUnglue();
                    mIsWalking = true;
                }
            }

            if (mIsWalking) {
                //check ground normal... not good :)
                //maybe physics should check the normal properly
                Contact contact;
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

    //optional debugging stuff
    override void debug_draw(Canvas c) {
        super.debug_draw(c);
        //could draw bounding box
    }
}

class PhysicObjectCircle : PhysicObject {
    private Circle mCircle;

    this() {
        super(&mCircle, Circle_ID);
    }

    override void updatePos() {
        auto r = posp.radius;
        mBB.p1.x = pos.x - r;
        mBB.p1.y = pos.y - r;
        mBB.p2.x = pos.x + r;
        mBB.p2.y = pos.y + r;
        mCircle.pos = pos;
        //hack: change radius on posp change
        mCircle.radius = r;
    }

    override void debug_draw(Canvas c) {
        super.debug_draw(c);

        auto p = toVector2i(pos);

        c.drawCircle(p, cast(int)posp.radius,
            isGlued ? Color(0,1,0) : Color(1,0,0));

        auto r = Vector2f.fromPolar(30, rotation);
        c.drawLine(p, p + toVector2i(r), Color(1,0,0));

        auto n = Vector2f.fromPolar(30, ground_angle);
        c.drawLine(p, p + toVector2i(n), Color(0,1,0));

        auto l = Vector2f.fromPolar(30, lookey_smooth);
        c.drawLine(p, p + toVector2i(l), Color(0,0,1));
    }
}

class PhysicObjectPlane : PhysicObject {
    private Plane mPlane;

    this(Plane a_init) {
        super(&mPlane, Plane_ID);
        mPlane = a_init;
        mBB.p1.x = float.min;
        mBB.p1.y = float.min;
        mBB.p2.x = float.max;
        mBB.p2.y = float.max;
    }

    override void updatePos() {
        //a Plane is infinite, it's also a forced static object (no position)
    }

    override void debug_draw(Canvas c) {
        super.debug_draw(c);
        //xxx see PhysicZonePlane
        //apparently we don't use PhysicObjectPlane at all
        //but PhysicZonePlane should be merged into PhysicObjectPlane
    }
}

//xxx should be named "segment"
class PhysicObjectLine : PhysicObject {
    private Line mLine;

    this(Line a_init) {
        super(&mLine, Line_ID);
        mLine = a_init;
        mBB = mLine.calcBB();
    }

    override void updatePos() {
        //xxx what about position? forced static for now
    }

    override void debug_draw(Canvas c) {
        super.debug_draw(c);
        auto normal = mLine.dir.normal.orthogonal;
        auto disp = normal*mLine.width;
        auto col = Color(0,1,0);
        int w = cast(int)mLine.width;
        c.drawCircle(toVector2i(mLine.start), w, col);
        c.drawCircle(toVector2i(mLine.start+mLine.dir), w, col);
        auto a1 = mLine.start - disp;
        auto b1 = mLine.start + disp;
        auto a2 = mLine.start + mLine.dir - disp;
        auto b2 = mLine.start + mLine.dir + disp;
        c.drawLine(toVector2i(a1), toVector2i(a2), col);
        c.drawLine(toVector2i(b1), toVector2i(b2), col);
    }
}
