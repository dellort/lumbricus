module physics.world;

import str = std.string;
import std.math : sqrt, PI;
import utils.misc;
import utils.array : aaReverseLookup;
import utils.mylist;
import utils.time;
import utils.vector2;
import log = utils.log;
import utils.output;
import random = utils.random;

public import physics.base;
public import physics.earthquake;
public import physics.force;
public import physics.geometry;
public import physics.physobj;
public import physics.posp;
public import physics.trigger;
public import physics.timedchanger;

//Uncomment to get detailed physics debugging log (slooooow)
//version = PhysDebug;

//constant from Stokes's drag
const cStokesConstant = 6*PI;

class PhysicWorld {
    package List!(PhysicBase) mAllObjects;
    package List!(PhysicForce) mForceObjects;
    package List!(PhysicGeometry) mGeometryObjects;
    package List!(PhysicObject) mObjects;
    package List!(PhysicTrigger) mTriggers;
    private uint mLastTime;

    package log.Log mLog;

    public void add(PhysicObject obj) {
        mObjects.insert_tail(obj);
        addBaseObject(obj);
    }
    public void add(PhysicForce obj) {
        mForceObjects.insert_tail(obj);
        addBaseObject(obj);
    }
    public void add(PhysicGeometry obj) {
        mGeometryObjects.insert_tail(obj);
        addBaseObject(obj);
    }
    public void add(PhysicTrigger obj) {
        mTriggers.insert_tail(obj);
        addBaseObject(obj);
    }
    public void addBaseObject(PhysicBase bobj) {
        bobj.world = this;
        mAllObjects.insert_tail(bobj);
    }

    private const cPhysTimeStepMs = 10;

    public void simulate(Time currentTime) {
        uint ms = currentTime.msecs();
        while (mLastTime + cPhysTimeStepMs < ms) {
            mLastTime += cPhysTimeStepMs;
            doSimulate(cast(float)cPhysTimeStepMs/1000.0f);
        }
    }

    // --- nasty earth quake code

    //valid per frame
    private float mEarthQuakeStrength = 0;
    //the force is updated in intervals according to the strength
    //reason: would look silly if it changed each frame
    private Vector2f mEarthQuakeForce;
    // a bit silly/dangerous: sum up the deltaTs until "change" time is
    // reached; initialized with NaN to trigger change in first simulate()
    private float mEarthQuakeLastChangeTime;

    //when something wants to cause an earth quake, it needs to update this
    //each frame (in PhysicBase.simulate()!)
    void addEarthQuakePerFrameStrength(float force) {
        mEarthQuakeStrength += force;
    }

    float earthQuakeStrength() {
        return mEarthQuakeStrength;
    }

    //(code maybe should be in a separate PhysicBase, but that's hard because
    // its simulate() method is called before and after other simulate methods)
    private void earthQuakeFrame(float deltaT) {
        if (mEarthQuakeStrength <= float.epsilon) {
            mEarthQuakeForce = Vector2f.init;
            return;
        }

        mEarthQuakeLastChangeTime += deltaT;

        //NOTE: don't return if mLastChange is NaN
        //this constant is the update-radnom-vector-change time
        if (mEarthQuakeLastChangeTime < 0.2)
            return;

        //new direction
        //xxx: undeterministic randomness
        //using an angle here is a simple way to create a normalized vector
        mEarthQuakeForce = Vector2f.fromPolar(1.0f,
            random.random() * PI * 2.0f) * mEarthQuakeStrength;
        mEarthQuakeLastChangeTime = 0;
    }

    // --- simulation, all in one function

    private void doSimulate(float deltaT) {
        //is changed per frame by EarthQuakeDegraders, which use the function
        //  addEarthQuakePerFrameStrength()
        mEarthQuakeStrength = 0;

        foreach (PhysicBase b; mAllObjects) {
            b.simulate(deltaT);
        }

        earthQuakeFrame(deltaT);

        //apply forces
        foreach (PhysicObject o; mObjects) {
            foreach (PhysicForce f; mForceObjects) {
                o.velocity += f.getAccelFor(o, deltaT) * deltaT;
            }

            //for earth quake, works like a force (as above)
            o.velocity += mEarthQuakeForce * deltaT;

            //xxx this with addVelocity can't be correct?
            o.velocity += o.selfAddVelocity + (o.selfForce * deltaT);

            //remove unwanted parts
            o.velocity = o.velocity.mulEntries(o.posp.fixate);

            //Stokes's drag
            if (o.posp.mediumViscosity != 0.0f)
                o.velocity += ((o.posp.mediumViscosity*cStokesConstant
                    *o.posp.radius)* -o.velocity)/o.posp.mass * deltaT;

            //clip components at maximum velocity
            o.velocity = o.velocity.clipAbsEntries(o.posp.velocityConstraint);

            auto vel = o.velocity;

            if (o.isGlued) {
                //argh. so a velocity is compared to a "force"... sigh.
                //surface_normal is valid, as objects are always glued to the ground
                if (vel.length <= o.posp.glueForce && vel*o.surface_normal <= 0) {
                    //xxx: reset the velocity vector, because else, the object
                    //     will be unglued even it stands on the ground
                    //     this should be changed such that the object is only
                    //     unglued if it actually could be moved...
                    o.velocity = Vector2f(0);
                    //skip to next object, don't change position
                    continue;
                }
                o.doUnglue();
            }

            o.move(vel * deltaT);
            o.needUpdate();
            o.checkRotation();
        }

        //collide with each other PhysicObjects
        // (0.5*n^2 - n) iterations
        foreach (PhysicObject me; mObjects) {
            //the next two lines mean: iterate over all objects following "me"
            auto other = mObjects.next(me);
            for (;other;other=mObjects.next(other)) {

                //the following stuff handles physically correct collision

                Vector2f d = other.pos - me.pos;
                float q_dist = d.quad_length();
                float mindist = other.posp.radius + me.posp.radius;

                //check if they collide at all
                if (q_dist >= mindist*mindist)
                    continue;

                CollisionCookie collide;

                //no collision if unwanted
                if (!canCollide(me, other, collide))
                    continue;

                //actually collide the stuff....

                //sitting worms are not safe
                //if it doesn't matter, they'll be glued again in the next frame
                me.doUnglue();
                other.doUnglue();

                float dist = sqrt(q_dist);
                float gap = mindist - dist;
                Vector2f nd = d / dist;

                if (nd.isNaN()) {
                    //NaN? maybe because dist was 0
                    nd = Vector2f(0);
                }

                //assert(fabs(nd.length()-1.0f) < 0.001);

                me.setPos(me.pos - nd * (0.5f * gap), true);
                other.setPos(other.pos + nd * (0.5f * gap), true);

                float vca = me.velocity * nd;
                float vcb = other.velocity * nd;

                float ma = me.posp.mass, mb = other.posp.mass;

                float dva = (vca * (ma - mb) + vcb * 2.0f * mb)
                            / (ma + mb) - vca;
                float dvb = (vcb * (mb - ma) + vca * 2.0f * ma)
                            / (ma + mb) - vcb;

                dva *= me.posp.elasticity;
                dvb *= other.posp.elasticity;

                me.velocity += dva * nd;
                other.velocity += dvb * nd;

                me.needUpdate();
                other.needUpdate();

                me.checkRotation();

                collide.call(); //call collision handler
                //xxx: also, should it be possible to glue objects here?
            }
        }

        //check for updated geometry objects, and force a full check
        //if geom has changed
        bool forceCheck = false;
        foreach (PhysicGeometry gm; mGeometryObjects) {
            if (gm.lastKnownGen < gm.generationNo) {
                //object has changed
                forceCheck = true;
                gm.lastKnownGen = gm.generationNo;
            }
        }

        //check against geometry
        foreach (PhysicObject me; mObjects) {
            //check triggers
            //check glued objects too, or else not checking would be
            //misinterpreted as not active

            foreach (PhysicTrigger tr; mTriggers) {
                //handler is unused -> registered handler not called
                //instead, the trigger calls a delegate... hmmm
                CollisionCookie handler;
                //xxx: not good, but had to hack it back, sigh
                bool always = tr.collision == CollisionType_Invalid;
                if (always || canCollide(tr, me, handler))
                    tr.collide(me);
            }

            //no need to check then? (maybe)
            //xxx if landscape changed => need to check
            Vector2f normalsum = Vector2f(0);

            if (me.isGlued && !forceCheck)
                continue;

            foreach (PhysicGeometry gm; mGeometryObjects) {
                Vector2f npos = me.pos;
                CollisionCookie cookie;
                if (canCollide(me, gm, cookie)
                    && gm.collide(npos, me.posp.radius))
                {
                    //kind of hack for LevelGeometry
                    //if the pos didn't change at all, but a collision was
                    //reported, assume the object is completely within the
                    //landscape...
                    //(xxx: uh, actually a dangerous hack)
                    if (npos == me.pos) {
                        //so pull it out along the velocity vector
                        npos -= me.velocity.normal*me.posp.radius*2;
                    }

                    Vector2f direction = npos - me.pos;
                    normalsum += direction;

                    if (!me.isGlued)
                        cookie.call();
                    //xxx: glue objects that don't fly fast enough
                }
            }

            auto rnormal = normalsum.normal();
            if (!rnormal.isNaN()) {
                //don't check again for already glued objects
                if (!me.isGlued) {
                    me.checkGroundAngle(normalsum);

                    //set new position ("should" fit)
                    me.setPos(me.pos + normalsum.mulEntries(me.posp.fixate),
                        true);

                    //direction the worm is flying to
                    auto flydirection = me.velocity.normal;

                    //force directed against surface
                    //xxx in worms, only vertical speed counts
                    auto bump = -(flydirection * rnormal);

                    if (bump < 0)
                        bump = 0;

                    //use this for damage
                    me.applyDamage(max(me.velocity.length-me.posp.sustainableForce,0f)*bump*me.posp.fallDamageFactor);

                    //mirror velocity on surface
                    Vector2f proj = rnormal * (me.velocity * rnormal);
                    me.velocity -= proj * (1.0f + me.posp.elasticity);

                    //bumped against surface -> loss of energy
                    //me.velocity *= me.posp.elasticity;

                    //we collided with geometry, but were not fast enough!
                    //  => worm gets glued, hahaha.
                    //xxx maybe do the gluing somewhere else?
                    if (me.velocity.mulEntries(me.posp.fixate).length
                        <= me.posp.glueForce)
                    {
                        me.isGlued = true;
                        version(PhysDebug) mLog("glue object %s", me);
                        //velocity must be set to 0 (or change glue handling)
                        //ok I did change glue handling.
                        me.velocity = Vector2f(0);
                    }

                    me.checkRotation();

                    //what about unglue??
                    me.needUpdate();
                }
            } else {
                if (me.isGlued) {
                    //no valid normal although glued -> terrain disappeared
                    me.doUnglue();
                    me.needUpdate();
                }
            }
        }

        //do updates
        PhysicBase obj = mAllObjects.head();
        while (obj) {
            auto next = mAllObjects.next(obj);
            if (!obj.dead && obj.needsUpdate) {
                obj.doUpdate();
            }
            if (obj.dead) {
                obj.doDie();
                obj.doRemove();
            }
            obj = next;
        }
    }

    //check how an object would collide with all the geometry
    bool collideGeometry(inout Vector2f pos, float radius)
    {
        bool res = false;
        foreach (PhysicGeometry gm; mGeometryObjects) {
            //pos will be changed, that is ok
            res = res | gm.collide(pos, radius);
        }
        return res;
    }

    //handling of the collision map

    //for now, do it this strange way, rectangular array would be better, faster
    //and more sane, but: you don't know the upper bounds of the array yet
    private struct Collide {
        CollisionType a, b;
    }
    private int[Collide] mCollisionMap;
    private CollisionType mCollisionAlloc;

    private CollideDelegate[] mCollideHandlers;
    private int[char[]] mCollideHandlerToIndex;

    CollisionType newCollisionType() {
        return ++mCollisionAlloc;
    }

    //considered to be private; result of canCollide
    //this is used to call the collision handler (was: PhysicBase.onImpact)
    //this is done using .call(), all other members are opaque
    //intention: avoid a second lookup into the collision map on impact
    //           also, maybe the arguments need to be reverted
    struct CollisionCookie {
        private PhysicBase a, b;
        private CollideDelegate oncollide;

        void call() {
            oncollide(a, b);
        }
    }

    private int getCollisionHandlerIndex(char[] name, bool maybecreate) {
        if (!(name in mCollideHandlerToIndex)) {
            if (!maybecreate)
                return -1;
            mCollideHandlerToIndex[name] = mCollideHandlers.length;
            mCollideHandlers ~= null;
        }

        return mCollideHandlerToIndex[name];
    }

    //associate a collision handler with code
    //this can handle forward-referencing
    void setCollideHandler(char[] name, CollideDelegate oncollide) {
        int index = getCollisionHandlerIndex(name, true);

        if (mCollideHandlers[index] !is null) {
            //already set, but there can be only one handler
            throw new Exception("collide-handler '"~name~"' is already set!");
        }

        if (!oncollide)
            oncollide = &collide_nohandler;

        mCollideHandlers[index] = oncollide;
    }

    private void collide_nohandler(PhysicBase a, PhysicBase b) {
    }

    //a should colide with b, and reverse (if allow_reverse is true)
    //  handler_name = name of the handler; can handle forward-refs
    //raises an error if collision is already set
    void setCollide(CollisionType a, CollisionType b, char[] handler_name,
        bool allow_reverse = true)
    {
        bool rev;
        int cook = doCollisionLookup(a, b, rev);
        if (cook >= 0) {
            throw new Exception(str.format("there is already a collision set"
                " between '%s' and '%s' (handler='%s', reverse=%s), can't"
                " set handler to '%s'!",
                aaReverseLookup(mCollisionTypeNames, a, "?"),
                aaReverseLookup(mCollisionTypeNames, b, "?"),
                aaReverseLookup(mCollideHandlerToIndex, cook, "?"),
                rev,
                handler_name));
        }
        mCollisionMap[Collide(a, b)] =
            getCollisionHandlerIndex(handler_name, true);
    }

    private int doCollisionLookup(CollisionType a, CollisionType b,
        out bool revert)
    {
        int* ptr = Collide(a, b) in mCollisionMap;
        if (!ptr) {
            ptr = Collide(b, a) in mCollisionMap;
            revert = true;
        }
        if (ptr) {
            return *ptr;
        } else {
            return -1;
        }
    }

    bool canCollide(PhysicBase a, PhysicBase b, out CollisionCookie stuff) {
        bool revert;
        int cookie = doCollisionLookup(a.collision, b.collision, revert);

        if (cookie < 0)
            return false;

        stuff.a = revert ? b : a;
        stuff.b = revert ? a : b;
        stuff.oncollide = mCollideHandlers[cookie];

        return true;
    }

    //check if all collision handlers were set; if not throw an error
    void checkCollisionHandlers() {
        char[][] errors;

        foreach(int index, handler; mCollideHandlers) {
            if (!handler) {
                errors ~= aaReverseLookup(mCollideHandlerToIndex, index, "?");
            }
        }

        if (errors.length > 0) {
            throw new Exception(str.format("the following collision handlers"
                " weren't set: %s", errors));
        }
    }

    //collision handling stuff: map names to the registered IDs
    //used by loadCollisions() and findCollisionID()
    private CollisionType[char[]] mCollisionTypeNames;

    //find a collision ID by name
    //  doregister = if true, register on not-exist, else throw exception
    CollisionType findCollisionID(char[] name, bool doregister = false) {
        if (name in mCollisionTypeNames)
            return mCollisionTypeNames[name];

        if (!doregister) {
            mLog("WARNING: collision name '%s' not found", name);
            throw new Exception("mooh");
        }

        auto nt = newCollisionType();
        mCollisionTypeNames[name] = nt;
        return nt;
    }

    //"collisions" node from i.e. worm.conf
    void loadCollisions(ConfigNode node) {
        //list of collision IDs, which map to...
        foreach (ConfigNode sub; node) {
            CollisionType obj_a = findCollisionID(sub.name, true);
            //... a list of "collision ID" -> "action" pairs
            foreach (char[] name, char[] value; sub) {
                CollisionType obj_b = findCollisionID(name, true);
                setCollide(obj_a, obj_b, value);
            }
        }
    }

    this() {
        mObjects = new List!(PhysicObject)(PhysicObject.objects_node.getListNodeOffset());
        mAllObjects = new List!(PhysicBase)(PhysicBase.allobjects_node.getListNodeOffset());
        mForceObjects = new List!(PhysicForce)(PhysicForce.forces_node.getListNodeOffset());
        mGeometryObjects = new List!(PhysicGeometry)(PhysicGeometry.geometries_node.getListNodeOffset());
        mTriggers = new List!(PhysicTrigger)(PhysicTrigger.triggers_node.getListNodeOffset());
        mLog = log.registerLog("physlog");
    }
}
