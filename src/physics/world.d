module physics.world;

import str = stdx.string;
import tango.math.Math : sqrt, PI;
import utils.misc;
import utils.array;
import utils.configfile;
import utils.list2;
import utils.random;
import utils.reflection;
import utils.time;
import utils.vector2;
import utils.log;
import utils.output;

public import physics.base;
public import physics.earthquake;
public import physics.force;
public import physics.geometry;
public import physics.physobj;
import physics.plane;
public import physics.misc;
public import physics.trigger;
public import physics.timedchanger;
public import physics.contact;
public import physics.zone;
public import physics.links;
import physics.collisionmap;
import physics.broadphase;
import physics.sortandsweep;

//Uncomment to get detailed physics debugging log (slooooow)
version = PhysDebug;

class PhysicWorld {
    private List2!(PhysicBase) mAllObjects;
    private List2!(PhysicForce) mForceObjects;
    private List2!(PhysicGeometry) mGeometryObjects;
    private List2!(PhysicObject) mObjects;
    private List2!(PhysicTrigger) mTriggers;
    private List2!(PhysicContactGen) mContactGenerators;
    private List2!(PhysicCollider) mObjectColliders;
    private uint mLastTime;

    private PhysicObject[] mObjArr;
    private BroadPhase broadphase;
    private Contact[] mContacts;
    private int mContactCount;

    private static LogStruct!("physics") log;
    Random rnd;
    CollisionMap collide;

    this (ReflectCtor c) {
        Types t = c.types();
        c.transient(this, &mContacts);
        t.registerClasses!(typeof(mAllObjects), typeof(mForceObjects),
            typeof(mGeometryObjects), typeof(mObjects), typeof(mTriggers),
            typeof(mContactGenerators), typeof(mObjectColliders));
        t.registerClasses!(CollisionMap, PhysicConstraint, POSP,
            BPSortAndSweep, PhysicTimedChangerVector2f, PhysicBase,
            CollisionType, EarthQuakeForce, EarthQuakeDegrader,
            PhysicObject, PhysicTimedChangerFloat, ZoneTrigger, PhysicFixate,
            WaterSurfaceGeometry, PlaneGeometry);
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
        if (auto o = cast(PhysicCollider)obj)
            o.coll_node = mObjectColliders.insert_tail(o);
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
        if (auto o = cast(PhysicCollider)obj)
            mObjectColliders.remove(o.coll_node);
    }

    private const cPhysTimeStepMs = 10;
    Vector2f gravity = {0, 0};

    public void simulate(Time currentTime) {
        uint ms = currentTime.msecs();
        while (mLastTime + cPhysTimeStepMs <= ms) {
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

        foreach (PhysicObject me; mObjects) {
            //check triggers
            //check glued objects too, or else not checking would be
            //misinterpreted as not active
            foreach (PhysicTrigger tr; mTriggers) {
                if (collide.canCollide(tr, me))
                    tr.collide(me);
            }
        }

        broadphase.collide(mObjArr, &handleContact);

        foreach (PhysicObject me; mObjects) {
            //no need to check then? (maybe)
            //xxx if landscape changed => need to check
            //    <-> landscape changes only after explosions, which unglue
            //    objects, however land-filling weapons will cause problems
            if (!me.isGlued) {
                //check against geometry
                checkGeometryCollisions(me, &handleContact);
                foreach (PhysicCollider co; mObjectColliders) {
                    //no collision if unwanted
                    ContactHandling ch = collide.canCollide(me, co);
                    if (ch == ContactHandling.none)
                        continue;
                    co.collide(me, &handleContact);
                }
            }
        }

        foreach (PhysicContactGen cg; mContactGenerators) {
            //xxx may be dead, but not removed yet (why did we have this
            //    delayed-remove crap again?)
            if (!cg.dead)
                cg.process(deltaT, &handleContact);
        }

        resolveContacts(deltaT);

        foreach (PhysicContactGen cg; mContactGenerators) {
            cg.afterResolve(deltaT);
        }

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
                }
            }
            //call collide event handler
            collide.callCollide(mContacts[i]); //call collision handler
        }
        //clear list of contacts
        mContactCount = 0;
    }

    private void checkUpdates() {
        //do updates
        foreach (PhysicBase obj; mAllObjects) {
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
        float qdist = d.quad_length;
        float mindist = obj1.posp.radius + obj2.posp.radius;
        //check if they collide at all
        //as a minor optimization, use quad_length to avoid slow sqrt() call xD
        if (qdist >= mindist*mindist)
            return;

        //no collision if unwanted
        ContactHandling ch = collide.canCollide(obj1, obj2);
        if (ch == ContactHandling.none)
            return;

        float dist = sqrt(qdist);
        if (dist <= 0) {
            //objects are exactly at the same pos, move aside anyway
            dist = mindist/2;
            d = Vector2f(0, dist);
        }

        //generate contact and resolve immediately (well, as before)
        if (ch == ContactHandling.normal) {
            Contact c;
            c.fromObj(obj1, obj2, d/dist, mindist - dist);
            contactHandler(c);
        } else if (ch == ContactHandling.noImpulse) {
            //lol, generate 2 contacts that behave like the objects hit a wall
            // (avoids special code in contact.d)
            if (obj1.velocity.length > float.epsilon || obj1.isWalking()) {
                Contact c1;
                c1.fromObj(obj1, null, d/dist, 0.5f*(mindist - dist));
                contactHandler(c1);
            }
            if (obj2.velocity.length > float.epsilon || obj2.isWalking()) {
                Contact c2;
                c2.fromObj(obj2, null, -d/dist, 0.5f*(mindist - dist));
                contactHandler(c2);
            }
        }

        //xxx: also, should it be possible to glue objects here?
    }

    private void checkGeometryCollisions(PhysicObject obj,
        CollideDelegate contactHandler)
    {
        GeomContact contact;
        if (obj.posp.extendNormalcheck) {
            //more expensive check that also yields a normal if the object
            //is "close by" to the surface
            if (collideObjectWithGeometry(obj, contact, true))
                obj.checkGroundAngle(contact);
        }
        if (!collideObjectWithGeometry(obj, contact))
            return;

        if (!obj.posp.extendNormalcheck)
            obj.checkGroundAngle(contact);

        //generate contact and resolve
        Contact c;
        c.fromGeom(contact, obj);
        contactHandler(c);
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

    //special collision function for walking code
    bool collideObjectsW(Vector2f pos, float radius, PhysicObject me = null) {
        //xxx collision matrix? I'm too lazy for that now
        //    also, what about optimized collision (broadphase); worth it?
        foreach (PhysicObject o; mObjects) {
            bool coll(Vector2f p, float r) {
                float mind = (o.posp.radius + r);
                if ((o.pos - p).quad_length < mind*mind)
                    return true;
                return false;
            }

            //no self-collision
            if (o is me)
                continue;
            //no collision if already inside (allow walking out)
            if (me && coll(me.pos, me.posp.radius))
                continue;
            if (coll(pos, radius))
                return true;
        }
        return false;
    }

    bool collideObjectWithGeometry(PhysicObject o, out GeomContact contact,
        bool extendRadius = false)
    {
        bool collided = false;
        foreach (PhysicGeometry gm; mGeometryObjects) {
            GeomContact ncont;
            ContactHandling ch = collide.canCollide(o, gm);
            if (ch && gm.collide(o, extendRadius, ncont))
            {
                //kind of hack for LevelGeometry
                //if the pos didn't change at all, but a collision was
                //reported, assume the object is completely within the
                //landscape...
                //(xxx: uh, actually a dangerous hack)
                if (ncont.depth == float.infinity) {
                    if (o.lastPos.isNaN) {
                        //we don't know a safe position, so pull it out
                        //  along the velocity vector
                        ncont.normal = -o.velocity.normal;
                        //assert(!ncont.normal.isNaN);
                        ncont.depth = o.posp.radius*2;
                    } else {
                        //we know a safe position, so pull it back there
                        Vector2f d = o.lastPos - o.pos;
                        ncont.normal = d.normal;
                        //assert(!ncont.normal.isNaN);
                        ncont.depth = d.length;
                    }
                } else if (ch == ContactHandling.pushBack) {
                    //back along velocity vector
                    //only allowed if less than 90° off from surface normal
                    Vector2f vn = -o.velocity.normal;
                    float a = vn * ncont.normal;
                    if (a > 0)
                        ncont.normal = vn;
                }

                if (!collided)
                    contact = ncont;
                else
                    contact.merge(ncont);

                collided = true;
            }
        }
        if (!collided)
            o.lastPos = o.pos;
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

    ///shoot a thick ray of passed radius between p1 and p2 and
    ///check for landscape collisions
    ///returns true if collided
    ///hit1 returns first hitpoint, hit2 the last (undefined if no collision)
    bool thickRay(Vector2f p1, Vector2f p2, float r, out Vector2f hit1,
        out Vector2f hit2)
    {
        bool hitLandscape = false;
        auto dir = p2 - p1;
        float len = dir.length;
        if (len == 0f)
            return false;
        auto ndir = dir / len;
        //subtracting r at both sides to avoid hitting landscape at
        //beside start/end of line
        for (float d = r; d < len-r; d += r) {
            auto p = p1 + ndir*d;
            GeomContact contact;
            if (collideGeometry(p, r, contact)) {
                if (contact.depth != float.infinity)
                    //move out of landscape
                    p = p + contact.normal*contact.depth;
                if (!hitLandscape)
                    hit1 = p;
                hitLandscape = true;
                hit2 = p;
            }
        }
        return hitLandscape;
    }

    bool thickRay(Vector2f start, Vector2f dir, float maxLen, float r,
        out Vector2f hit, out GeomContact contact)
    {
        //subtracting r at both sides to avoid hitting landscape at
        //beside start/end of line
        for (float d = r; d < maxLen-r; d += r) {
            auto p = start + dir*d;
            if (collideGeometry(p, r, contact)) {
                if (contact.depth != float.infinity)
                    //move out of landscape
                    p = p + contact.normal*contact.depth;
                    hit = p;
                    return true;
            }
        }
        return false;
    }

    ///Move the passed point out of any geometry it hits inside the radius r
    //xxx what about objects? should be handled too
    bool freePoint(ref Vector2f p, float r) {
        GeomContact contact;
        //r+4 chosen by experiment
        if (collideGeometry(p, r+4, contact)) {
            if (contact.depth == float.infinity)
                return false;
            p = p + contact.normal*contact.depth;
        }
        if (collideGeometry(p, r, contact))
            //still inside? maybe it was a tiny cave oslt
            return false;
        return true;
    }

    void objectsAtPred(Vector2f pos, float r,
        void delegate(PhysicObject obj) del,
        bool delegate(PhysicObject obj) match = null)
    {
        assert(!!del);
        foreach (PhysicObject me; mObjects) {
            if (!match || match(me)) {
                Vector2f d = me.pos - pos;
                float qdist = d.quad_length;
                float mindist = me.posp.radius + r;
                if (qdist >= mindist*mindist)
                    continue;
                del(me);
            }
        }
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
        mObjectColliders = new List2!(PhysicCollider)();
        mContacts.length = 1024;  //xxx arbitrary number
    }
}
