module physics.world;

import str = std.string;
import std.math : sqrt, PI;
import utils.misc;
import utils.array;
import utils.configfile;
import utils.list2;
import utils.random;
import utils.reflection;
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
public import physics.zone;
public import physics.links;
import physics.collisionmap;
import physics.broadphase;
import physics.sortandsweep;
import physics.movehandler;

//Uncomment to get detailed physics debugging log (slooooow)
//version = PhysDebug;

class PhysicWorld {
    private List2!(PhysicBase) mAllObjects;
    private List2!(PhysicForce) mForceObjects;
    private List2!(PhysicGeometry) mGeometryObjects;
    private List2!(PhysicObject) mObjects;
    private List2!(PhysicTrigger) mTriggers;
    private List2!(PhysicContactGen) mContactGenerators;
    private uint mLastTime;

    private PhysicObject[] mObjArr;
    private BroadPhase broadphase;
    private Contact[] mContacts;
    private int mContactCount;

    /+package+/ log.Log mLog;
    Random rnd;
    CollisionMap collide;

    this (ReflectCtor c) {
        Types t = c.types();
        c.transient(this, &mContacts);
        t.registerClasses!(typeof(mAllObjects), typeof(mForceObjects),
            typeof(mGeometryObjects), typeof(mObjects), typeof(mTriggers),
            typeof(mContactGenerators));
        t.registerClasses!(CollisionMap, PhysicConstraint, RopeHandler, POSP,
            BPSortAndSweep, PhysicTimedChangerVector2f, PhysicBase,
            CollisionType, EarthQuakeForce, EarthQuakeDegrader,
            PhysicObject, PhysicTimedChangerFloat, ZoneTrigger);
        BroadPhase.registerstuff(c);
        PhysicZone.registerstuff(c);
        PhysicForce.registerstuff(c);
        t.registerMethod(this, &checkObjectCollision, "checkObjectCollision");
        //initialization
        mContacts.length = 1024;
    }

    public void add(PhysicBase obj) {
        obj.world = this;
        obj.base_node = mAllObjects.insert_tail(obj);
        if (auto o = cast(PhysicForce)obj)
            o.forces_node = mForceObjects.insert_tail(o);
        if (auto o = cast(PhysicGeometry)obj)
            o.geometries_node = mGeometryObjects.insert_tail(o);
        if (auto o = cast(PhysicObject)obj) {
            o.objects_node = mObjects.insert_tail(o);
            mObjArr ~= o;
        }
        if (auto o = cast(PhysicTrigger)obj)
            o.triggers_node = mTriggers.insert_tail(o);
        if (auto o = cast(PhysicContactGen)obj)
            o.cgen_node = mContactGenerators.insert_tail(o);
    }

    private void remove(PhysicBase obj) {
        mAllObjects.remove(obj.base_node);
        if (auto o = cast(PhysicForce)obj)
            mForceObjects.remove(o.forces_node);
        if (auto o = cast(PhysicGeometry)obj)
            mGeometryObjects.remove(o.geometries_node);
        if (auto o = cast(PhysicObject)obj) {
            mObjects.remove(o.objects_node);
            arrayRemoveUnordered(mObjArr, o);
        }
        if (auto o = cast(PhysicTrigger)obj)
            mTriggers.remove(o.triggers_node);
        if (auto o = cast(PhysicContactGen)obj)
            mContactGenerators.remove(o.cgen_node);
    }

    private const cPhysTimeStepMs = 10;
    Vector2f gravity = {0, 0};

    public void simulate(Time currentTime) {
        uint ms = currentTime.msecs();
        while (mLastTime + cPhysTimeStepMs < ms) {
            mLastTime += cPhysTimeStepMs;
            doSimulate(cast(float)cPhysTimeStepMs/1000.0f);
        }
        //checkUpdates();
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
        }

        broadphase.collide(mObjArr, &handleContact);
        foreach (PhysicContactGen cg; mContactGenerators) {
            cg.process(&handleContact);
        }

        foreach (PhysicObject me; mObjects) {
            //no need to check then? (maybe)
            //xxx if landscape changed => need to check
            //    <-> landscape changes only after explosions, which unglue
            //    objects, however land-filling weapons will cause problems
            if (!me.isGlued) {
                //check against geometry
                checkGeometryCollisions(me, &handleContact);
            }

            //check triggers
            //check glued objects too, or else not checking would be
            //misinterpreted as not active
            foreach (PhysicTrigger tr; mTriggers) {
                if (collide.canCollide(tr, me))
                    tr.collide(me);
            }
        }

        resolveContacts(deltaT);

        checkUpdates();
    }

    private void handleContact(ref Contact c) {
        if (mContactCount >= mContacts.length) {
            //no more room
            mContacts.length = mContacts.length + 64; //another arbitrary number
        }
        mContacts[mContactCount] = c;
        mContactCount++;
    }

    private void resolveContacts(float deltaT) {
        //xxx simple iteration, i heard rumors about better algorithms ;)
        for (int i = 0; i < mContactCount; i++) {
            //resolve contact
            mContacts[i].resolve(deltaT);
            //update involved objects
            foreach (o; mContacts[i].obj) {
                if (o) {
                    o.checkRotation();
                    o.needUpdate();
                }
            }
            //call collide event handler
            collide.callCollide(mContacts[i]); //call collision handler
        }
        //clear list of contacts
        mContactCount = 0;
    }

    void checkUpdates() {
        //do updates
        foreach (PhysicBase obj; mAllObjects) {
            if (!obj.dead && obj.needsUpdate) {
                obj.doUpdate();
            }
            if (obj.dead) {
                obj.doDie();
                remove(obj);
            }
        }
    }

    private void checkObjectCollision(PhysicObject obj1, PhysicObject obj2,
        CollideDelegate contactHandler)
    {
        //the following stuff handles physically correct collision

        Vector2f d = obj1.pos - obj2.pos;
        float dist = d.length;
        float mindist = obj1.posp.radius + obj2.posp.radius;
        //check if they collide at all
        if (dist >= mindist)
            return;
        if (dist <= 0) {
            //objects are exactly at the same pos, move aside anyway
            dist = mindist/2;
            d = Vector2f(0, dist);
        }

        //no collision if unwanted
        if (!collide.canCollide(obj1, obj2))
            return;

        //generate contact and resolve immediately (well, as before)
        Contact c;
        c.fromObj(obj1, obj2, d/dist, mindist - dist);
        contactHandler(c);

        //xxx: also, should it be possible to glue objects here?
    }

    private void checkGeometryCollisions(PhysicObject obj,
        CollideDelegate contactHandler)
    {
        GeomContact contact;
        if (!collideObjectWithGeometry(obj, contact))
            return;

        Vector2f depthvec = contact.normal*contact.depth;
        obj.checkGroundAngle(depthvec);

        //generate contact and resolve
        Contact c;
        c.fromGeom(contact, obj);
        contactHandler(c);

        //we collided with geometry, but were not fast enough!
        //  => worm gets glued, hahaha.
        //xxx maybe do the gluing somewhere else?
        if (obj.velocity.mulEntries(obj.posp.fixate).length
            <= obj.posp.glueForce && obj.surface_normal.y < 0)
        {
            obj.isGlued = true;
            version(PhysDebug) mLog("glue object %s", me);
            //velocity must be set to 0 (or change glue handling)
            //ok I did change glue handling.
            obj.velocity_int = Vector2f(0);
        }
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
            GeomContact ncont;
            if (collide.canCollide(o, gm) && gm.collide(o.pos, o.posp.radius, ncont)) {
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
        out Vector2f hitPoint, out PhysicObject obj, out Vector2f normal)
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
                normal = contact.normal;
                return true;
            }
        }
        if (firstColl && tmin <= maxLen) {
            hitPoint = start + dir*tmin;
            obj = firstColl;
            normal = (hitPoint - obj.pos).normal;
            return true;
        }
        hitPoint = start + dir*maxLen;
        return false;
    }

    bool thickRay(Vector2f p1, Vector2f p2, float r, out Vector2f hit1,
        out Vector2f hit2)
    {
        bool first = false;
        auto dir = p2 - p1;
        float len = dir.length;
        auto ndir = dir / len;
        float halfStep = r;
        for (float d = r; d < len-r; d += r) {
            auto p = p1 + ndir*(d);
            GeomContact contact;
            if (collideGeometry(p, r, contact)) {
                if (contact.depth != float.infinity)
                    p = p + contact.normal*contact.depth;
                if (!first)
                    hit1 = p;
                first = true;
                hit2 = p;
            }
        }
        return first;
    }

    ///r = random number generator to use, null will create a new instance
    public this(Random r) {
        if (!r) {
            //rnd = new Random();
            assert(false, "you must");
        }
        rnd = r;
        collide = new CollisionMap();
        broadphase = new BPSortAndSweep(&checkObjectCollision);
        mObjects = new List2!(PhysicObject)();
        mAllObjects = new List2!(PhysicBase)();
        mForceObjects = new List2!(PhysicForce)();
        mGeometryObjects = new List2!(PhysicGeometry)();
        mTriggers = new List2!(PhysicTrigger)();
        mContactGenerators = new List2!(PhysicContactGen)();
        mContacts.length = 1024;  //xxx arbitrary number
        mLog = log.registerLog("physlog");
    }
}
