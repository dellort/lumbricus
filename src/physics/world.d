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
import physics.plane;
public import physics.posp;
public import physics.trigger;
public import physics.timedchanger;
public import physics.contact;

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
                checkObjectCollision(me, other, deltaT);
            }

            //no need to check then? (maybe)
            //xxx if landscape changed => need to check
            //    <-> landscape changes only after explosions, which unglue
            //    objects, however land-filling weapons will cause problems
            if (!me.isGlued) {
                //check against geometry
                checkGeometryCollisions(me, deltaT);
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

    private void checkObjectCollision(PhysicObject obj1, PhysicObject obj2,
        float deltaT)
    {
        //the following stuff handles physically correct collision

        Vector2f d = obj1.pos - obj2.pos;
        float dist = d.length;
        float mindist = obj1.posp.radius + obj2.posp.radius;
        //check if they collide at all
        if (dist >= mindist)
            return;

        CollisionCookie cookie;

        //no collision if unwanted
        if (!canCollide(obj1, obj2, cookie))
            return;

        //generate contact and resolve immediately (well, as before)
        Contact c;
        c.normal = d/dist;
        c.depth = mindist - dist;
        c.obj[0] = obj1;
        c.obj[1] = obj2;
        c.resolve(deltaT);

        obj1.needUpdate();
        obj2.needUpdate();

        obj1.checkRotation();

        cookie.call(); //call collision handler
        //xxx: also, should it be possible to glue objects here?
    }

    void checkGeometryCollisions(PhysicObject obj, float deltaT) {
        GeomContact contact;
        if (!collideObjectWithGeometry(obj, contact))
            return;

        Vector2f depthvec = contact.normal*contact.depth;
        obj.checkGroundAngle(depthvec);

        //generate contact and resolve
        Contact c;
        c.fromGeom(contact, obj);
        c.resolve(deltaT);

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
    bool collideGeometry(Vector2f pos, float radius, out GeomContact contact)
    {
        bool collided = false;
        foreach (PhysicGeometry gm; mGeometryObjects) {
            GeomContact ncont;
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

    bool collideObjectWithGeometry(PhysicObject o, out GeomContact contact) {
        bool collided = false;
        foreach (PhysicGeometry gm; mGeometryObjects) {
            CollisionCookie cookie;
            GeomContact ncont;
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

    ///Shoot a thin ray into the world and test for object and geometry
    ///intersection.
    ///Params:
    ///  maxLen   = length of the ray, in pixels (range)
    ///  hitPoint = returns the absolute coords of the hitpoint
    ///  obj      = return the hit object (null if landscape was hit)
    bool shootRay(Vector2f start, Vector2f dir, float maxLen,
        out Vector2f hitPoint, out PhysicObject obj)
    {
        //xxx range limit (we have nothing like world bounds)
        if (maxLen > 10000)
            maxLen = 10000;
        dir = dir.normal;
        const float t_inc = 0.75f;
        const float ray_radius = 1.0f;
        //check against objects
        Ray r;
        r.define(start, dir);
        float tmin = float.max;
        PhysicObject firstColl;
        foreach (PhysicObject o; mObjects) {
            float t;
            if (r.intersect(o.pos, o.posp.radius, t) && t < tmin
                && t < maxLen)
            {
                tmin = t;
                firstColl = o;
            }
        }
        //check against landscape
        GeomContact contact;
        for (float t = 0; t < tmin && t < maxLen; t += t_inc) {
            Vector2f p = start + t*dir;
            if (collideGeometry(p, ray_radius, contact)) {
                //found collision before hit object -> stop
                obj = null;
                hitPoint = start + dir*t;
                return true;
            }
        }
        if (firstColl && tmin <= maxLen) {
            hitPoint = start + dir*tmin;
            obj = firstColl;
            return true;
        }
        return false;
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
