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
    Vector2f gravity = {0, 0};

    public void simulate(Time currentTime) {
        uint ms = currentTime.msecs();
        while (mLastTime + cPhysTimeStepMs < ms) {
            mLastTime += cPhysTimeStepMs;
            doSimulate(cast(float)cPhysTimeStepMs/1000.0f);
        }
    }

    // --- simulation, all in one function

    private void doSimulate(float deltaT) {
        foreach (PhysicBase b; mAllObjects) {
            b.simulate(deltaT);
        }

        //update all objects (force/velocity/collisions)
        foreach (PhysicObject me; mObjects) {
            //xxx pass gravity to object (this avoids a reference to world)
            me.gravity = gravity;

            //apply force generators
            foreach (PhysicForce f; mForceObjects) {
                f.applyTo(me, deltaT);
            }

            //update position and velocity
            me.update(deltaT);

            //collide with each other PhysicObjects
            // (0.5*n^2 - n) iterations
            //the next two lines mean: iterate over all objects following "me"
            auto other = mObjects.next(me);
            for (;other;other=mObjects.next(other)) {
                checkObjectCollision(me, other);
            }

            //no need to check then? (maybe)
            //xxx if landscape changed => need to check
            //    <-> landscape changes only after explosions, which unglue
            //    objects, however land-filling weapons will cause problems
            if (!me.isGlued) {
                //check against geometry
                checkGeometryCollisions(me);
            }

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

    private void checkObjectCollision(PhysicObject obj1, PhysicObject obj2) {
        //the following stuff handles physically correct collision

        Vector2f d = obj2.pos - obj1.pos;
        float q_dist = d.quad_length();
        float mindist = obj2.posp.radius + obj1.posp.radius;

        //check if they collide at all
        if (q_dist >= mindist*mindist)
            return;

        CollisionCookie cookie;

        //no collision if unwanted
        if (!canCollide(obj1, obj2, cookie))
            return;

        //actually collide the stuff....

        //sitting worms are not safe
        //if it doesn't matter, they'll be glued again in the next frame
        obj1.doUnglue();
        obj2.doUnglue();

        float dist = sqrt(q_dist);
        float gap = mindist - dist;
        Vector2f nd = d / dist;

        if (nd.isNaN()) {
            //NaN? maybe because dist was 0
            nd = Vector2f(0);
        }

        //assert(fabs(nd.length()-1.0f) < 0.001);

        obj1.setPos(obj1.pos - nd * (0.5f * gap), true);
        obj2.setPos(obj2.pos + nd * (0.5f * gap), true);

        float vca = obj1.velocity * nd;
        float vcb = obj2.velocity * nd;

        float ma = obj1.posp.mass, mb = obj2.posp.mass;

        float dva = (vca * (ma - mb) + vcb * 2.0f * mb)
                    / (ma + mb) - vca;
        float dvb = (vcb * (mb - ma) + vca * 2.0f * ma)
                    / (ma + mb) - vcb;

        dva *= obj1.posp.elasticity;
        dvb *= obj2.posp.elasticity;

        obj1.velocity_int += dva * nd;
        obj2.velocity_int += dvb * nd;

        obj1.needUpdate();
        obj2.needUpdate();

        obj1.checkRotation();

        cookie.call(); //call collision handler
        //xxx: also, should it be possible to glue objects here?
    }

    void checkGeometryCollisions(PhysicObject obj) {
        ContactData contact;
        if (!collideObjectWithGeometry(obj, contact))
            return;

        Vector2f depthvec = contact.normal*contact.depth;
        obj.checkGroundAngle(depthvec);

        //set new position ("should" fit)
        obj.setPos(obj.pos + depthvec.mulEntries(obj.posp.fixate),
            true);

        //direction the worm is flying to
        auto flydirection = obj.velocity_int.normal;

        //force directed against surface
        //xxx in worms, only vertical speed counts
        auto bump = -(flydirection * contact.normal);

        if (bump < 0)
            bump = 0;

        //use this for damage
        float damage = max(obj.velocity.length - obj.posp.sustainableForce, 0f)
            * bump * obj.posp.fallDamageFactor;
        if (damage > 0)
            obj.applyDamage(damage);

        //mirror velocity on surface
        Vector2f proj = contact.normal * (obj.velocity * contact.normal);
        obj.velocity_int -= proj * (1.0f + obj.posp.elasticity);

        //bumped against surface -> loss of energy
        //obj.velocity *= obj.posp.elasticity;

        //we collided with geometry, but were not fast enough!
        //  => worm gets glued, hahaha.
        //xxx maybe do the gluing somewhere else?
        if (obj.velocity.mulEntries(obj.posp.fixate).length
            <= obj.posp.glueForce)
        {
            obj.isGlued = true;
            version(PhysDebug) mLog("glue object %s", me);
            //velocity must be set to 0 (or change glue handling)
            //ok I did change glue handling.
            obj.velocity_int = Vector2f(0);
        }

        obj.checkRotation();

        //what about unglue??
        obj.needUpdate();
    }

    //check how an object would collide with all the geometry
    bool collideGeometry(Vector2f pos, float radius, out ContactData contact)
    {
        bool collided = false;
        foreach (PhysicGeometry gm; mGeometryObjects) {
            ContactData ncont;
            if (gm.collide(pos, radius, ncont)) {
                if (!collided)
                    contact = ncont;
                else
                    contact.merge(ncont);
                collided = true;
            }
        }
        return collided;
    }

    bool collideObjectWithGeometry(PhysicObject o, out ContactData contact) {
        bool collided = false;
        foreach (PhysicGeometry gm; mGeometryObjects) {
            CollisionCookie cookie;
            ContactData ncont;
            if (canCollide(o, gm, cookie)
                && gm.collide(o.pos, o.posp.radius, ncont))
            {
                //kind of hack for LevelGeometry
                //if the pos didn't change at all, but a collision was
                //reported, assume the object is completely within the
                //landscape...
                //(xxx: uh, actually a dangerous hack)
                if (ncont.depth == float.infinity) {
                    //so pull it out along the velocity vector
                    ncont.normal = -o.velocity.normal;
                    ncont.depth = o.posp.radius*2;
                }

                if (!collided)
                    contact = ncont;
                else
                    contact.merge(ncont);
                collided = true;

                cookie.call();
            }
        }
        return collided;
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
