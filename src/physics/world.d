module physics.world;

import tango.math.Math : sqrt, PI;
import utils.misc;
import utils.array;
import utils.list2;
import utils.random;
import utils.time;
import utils.vector2;
import utils.log;
import utils.output;

import tarray = tango.core.Array;

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
import physics.bih;

class PhysicWorld {
    private ObjectList!(PhysicBase, "base_node") mAllObjects;
    private ObjectList!(PhysicForce, "forces_node") mForceObjects;
    private ObjectList!(PhysicGeometry, "geometries_node") mGeometryObjects;
    private ObjectList!(PhysicObject, "objects_node") mObjects;
    private ObjectList!(PhysicTrigger, "triggers_node") mTriggers;
    private ObjectList!(PhysicContactGen, "cgen_node") mContactGenerators;
    private ObjectList!(PhysicCollider, "coll_node") mObjectColliders;
    private uint mLastTime;

    private PhysicObject[] mObjArr;
    private BroadPhase broadphase;
    private Contact[] mContacts;
    private int mContactCount;

    static if (cFixUndeterministicBroadphase) {
        private uint mNewSerial;
    }

    private static LogStruct!("physics") log;
    Random rnd;
    CollisionMap collide;
    CollideDelegate onCollide;

    public void add(PhysicBase obj) {
        argcheck(obj);
        obj.world = this;
        obj.remove = false;
        static if (cFixUndeterministicBroadphase) {
            obj.mSerial = ++mNewSerial;
            assert(mNewSerial != 0);
        }
        mAllObjects.insert_tail(obj);
        if (auto o = cast(PhysicForce)obj)
            mForceObjects.insert_tail(o);
        if (auto o = cast(PhysicGeometry)obj)
            mGeometryObjects.insert_tail(o);
        if (auto o = cast(PhysicObject)obj) {
            mObjects.insert_tail(o);
            mObjArr ~= o;
        }
        if (auto o = cast(PhysicTrigger)obj)
            mTriggers.insert_tail(o);
        if (auto o = cast(PhysicContactGen)obj)
            mContactGenerators.insert_tail(o);
        if (auto o = cast(PhysicCollider)obj)
            mObjectColliders.insert_tail(o);
    }

    private void remove(PhysicBase obj) {
        mAllObjects.remove(obj);
        if (auto o = cast(PhysicForce)obj)
            mForceObjects.remove(o);
        if (auto o = cast(PhysicGeometry)obj)
            mGeometryObjects.remove(o);
        if (auto o = cast(PhysicObject)obj) {
            mObjects.remove(o);
            arrayRemoveUnordered(mObjArr, o);
        }
        if (auto o = cast(PhysicTrigger)obj)
            mTriggers.remove(o);
        if (auto o = cast(PhysicContactGen)obj)
            mContactGenerators.remove(o);
        if (auto o = cast(PhysicCollider)obj)
            mObjectColliders.remove(o);
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

    final ContactHandling canCollide(PhysicBase a, PhysicBase b) {
        return collide.canCollide(a.collision, b.collision);
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

        //check triggers
        foreach (PhysicTrigger tr; mTriggers) {
            foreach (PhysicObject me; mObjects) {
                //check glued objects too, or else not checking would be
                //misinterpreted as not active
                if (canCollide(tr, me))
                    tr.collide(me);
            }
        }

        broadphase.collide(mObjArr, &handleContact);

        static if (cFixUndeterministicBroadphase) {
            //sort contacts (handleContact is called in arbitrary order)
            tarray.sort(mContacts[0..mContactCount],
                (ref Contact a, ref Contact b) {
                    auto xa = a.contactID;
                    auto xb = b.contactID;
                    assert(xa != 0);
                    assert(xb != 0);
                    assert(xa != xb);
                    return xa < xb;
                });
            //and objects (because broadphase.collide may permutate it)
            tarray.sort(mObjArr,
                (PhysicObject a, PhysicObject b) {
                    assert(a.mSerial != b.mSerial);
                    return a.mSerial < b.mSerial;
                });
        }

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
                    ContactHandling ch = canCollide(me, co);
                    if (ch == ContactHandling.none)
                        continue;
                    co.collide(me, &handleContact);
                }
            }
        }

        foreach (PhysicContactGen cg; mContactGenerators) {
            //xxx may be dead, but not removed yet (why did we have this
            //    delayed-remove crap again?)
            if (cg.active)
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
            //mContacts.length = max(mContacts.length * 2, 64);
            mContacts.length = mContacts.length + 64;
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
            callCollide(mContacts[i]); //call collision handler
        }
        //clear list of contacts
        mContactCount = 0;
    }

    private void callCollide(Contact c) {
        if ((c.obj[0] && !c.obj[0].active) || (c.obj[1] && !c.obj[1].active))
            return;
        assert(!!onCollide);
        onCollide(c);
    }

    private void checkUpdates() {
        //do updates
        foreach (PhysicBase obj; mAllObjects) {
            if (!obj.active) {
                if (obj.dead)
                    obj.doDie();
                remove(obj);
            }
        }
    }

    //called by broadphase on potential collision
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
        ContactHandling ch = canCollide(obj1, obj2);
        if (ch == ContactHandling.none)
            return;

        float dist = sqrt(qdist);
        if (dist <= 0) {
            //objects are exactly at the same pos, move aside anyway
            dist = mindist/2;
            d = Vector2f(0, dist);
        }

        static if (cFixUndeterministicBroadphase) {
            ulong a = obj1.mSerial;
            ulong b = obj2.mSerial;
            ulong cid = (a << 32) | b;
        }

        //generate contact and resolve immediately (well, as before)
        if (ch == ContactHandling.normal) {
            Contact c;
            c.fromObj(obj1, obj2, d/dist, mindist - dist);
            static if (cFixUndeterministicBroadphase)
                c.contactID = cid;
            contactHandler(c);
        } else if (ch == ContactHandling.noImpulse) {
            //lol, generate 2 contacts that behave like the objects hit a wall
            // (avoids special code in contact.d)
            if (obj1.velocity.length > float.epsilon || obj1.isWalking()) {
                Contact c1;
                c1.fromObj(obj1, null, d/dist, 0.5f*(mindist - dist));
                static if (cFixUndeterministicBroadphase)
                    c1.contactID = cid;
                contactHandler(c1);
            }
            if (obj2.velocity.length > float.epsilon || obj2.isWalking()) {
                Contact c2;
                c2.fromObj(obj2, null, -d/dist, 0.5f*(mindist - dist));
                static if (cFixUndeterministicBroadphase)
                    c2.contactID = cid | (1L<<63); //unique id
                contactHandler(c2);
            }
        }

        //xxx: also, should it be possible to glue objects here?
    }

    private void checkGeometryCollisions(PhysicObject obj,
        CollideDelegate contactHandler)
    {
        Contact contact;
        if (!collideObjectWithGeometry(obj, contact))
            return;

        obj.checkGroundAngle(contact);

        //generate contact and resolve
        contactHandler(contact);
    }

    //check how an object would collide with all the geometry
    bool collideGeometry(Vector2f pos, float radius, out Contact contact)
    {
        bool collided = false;
        foreach (PhysicGeometry gm; mGeometryObjects) {
            Contact ncont;
            if (gm.collide(pos, radius, ncont)) {
                if (!collided)
                    contact = ncont;
                else
                    contact.mergeFrom(ncont);
                collided = true;
            }
        }
        return collided;
    }

    //special collision function for walking code
    bool collideObjectsW(Vector2f pos, PhysicObject me) {
        float radius = me.posp.radius;
        //xxx also, what about optimized collision (broadphase); worth it?
        foreach (PhysicObject o; mObjects) {
            bool coll(Vector2f p, float r) {
                float mind = (o.posp.radius + r);
                if ((o.pos - p).quad_length < mind*mind)
                    return true;
                return false;
            }

            if (!canCollide(o, me))
                continue;

            //no self-collision, no collision with other walking objects
            if (o is me || o.isWalking())
                continue;
            //no collision if already inside (allow walking out)
            if (coll(me.pos, me.posp.radius))
                continue;
            if (coll(pos, radius))
                return true;
        }
        return false;
    }

    bool collideObjectWithGeometry(PhysicObject o, out Contact contact) {
        argcheck(o);
        bool collided = false;
        foreach (PhysicGeometry gm; mGeometryObjects) {
            Contact ncont;
            ContactHandling ch = canCollide(o, gm);
            if (ch && gm.collide(o, ncont)) {
                ncont.geomPostprocess(ch);

                if (!collided)
                    contact = ncont;
                else
                    contact.mergeFrom(ncont);

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
        for (float t = 0; t < tmin && t < maxLen; t += t_inc) {
            Vector2f p = start + t*dir;
            Contact contact;
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
            Contact contact;
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
        out Vector2f hit, out Contact contact)
    {
        //subtracting r at both sides to avoid hitting landscape at
        //beside start/end of line
        for (float d = 0; d < maxLen; d += r) {
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
        Contact contact;
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

    void objectsAt(Vector2f pos, float r,
        bool delegate(PhysicObject obj) del)
    {
        argcheck(!!del);
        foreach (PhysicObject me; mObjects) {
            Vector2f d = me.pos - pos;
            float qdist = d.quad_length;
            float mindist = me.posp.radius + r;
            if (qdist >= mindist*mindist)
                continue;
            if (!del(me))
                break;
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
        //broadphase = new BPIterate(&checkObjectCollision);
        //broadphase = new BPIterate2(&checkObjectCollision);
        //broadphase = new BPBIH(&checkObjectCollision);
        //broadphase = new BPTileHash(&checkObjectCollision);
        mObjects = new typeof(mObjects)();
        mAllObjects = new typeof(mAllObjects)();
        mForceObjects = new typeof(mForceObjects)();
        mGeometryObjects = new typeof(mGeometryObjects)();
        mTriggers = new typeof(mTriggers)();
        mContactGenerators = new typeof(mContactGenerators)();
        mObjectColliders = new typeof(mObjectColliders)();
        mContacts.length = 1024;  //xxx arbitrary number
    }

    //********************************************************************
    //Below this line are wrappers of the functions above for scripting
    //(because most script languages have no ref/out parameters)
    //xxx this looks very messy

    struct CollideGeometryStruct {
        const cTupleReturn = true;
        int numReturnValues;
        Contact contact;
    }
    CollideGeometryStruct collideGeometryScript(Vector2f pos, float radius) {
        CollideGeometryStruct ret = void;
        bool hit = collideGeometry(pos, radius, ret.contact);
        if (hit) {
            ret.numReturnValues = 1;
        } else {
            ret.numReturnValues = 0;
        }
        return ret;
    }
    CollideGeometryStruct collideObjectWithGeometryScript(PhysicObject o) {
        CollideGeometryStruct ret = void;
        bool hit = collideObjectWithGeometry(o, ret.contact);
        if (hit) {
            ret.numReturnValues = 1;
        } else {
            ret.numReturnValues = 0;
        }
        return ret;
    }

    struct ShootRayStruct {
        const cTupleReturn = true;
        int numReturnValues;
        Vector2f hitPoint;  //always returned
        Vector2f normal;    //only on collision
        PhysicObject obj;   //only on object collision
    }
    ShootRayStruct shootRayScript(Vector2f start, Vector2f dir, float maxLen) {
        ShootRayStruct ret = void;
        bool hit = shootRay(start, dir, maxLen, ret.hitPoint, ret.obj,
            ret.normal);
        if (hit && ret.obj) {
            //object collision
            ret.numReturnValues = 3;
        } else if (hit) {
            //geometry collision
            ret.numReturnValues = 2;
        } else {
            //no collision (hitPoint is at maxLen)
            ret.numReturnValues = 1;
        }
        return ret;
    }

    //xxx renamed thickRay to thickLine (that's what it does)
    struct ThickLineStruct {
        const cTupleReturn = true;
        int numReturnValues;
        Vector2f hit1, hit2;
    }
    ThickLineStruct thickLineScript(Vector2f p1, Vector2f p2, float r) {
        ThickLineStruct ret = void;
        bool hit = thickRay(p1, p2, r, ret.hit1, ret.hit2);
        if (hit) {
            ret.numReturnValues = 2;
        } else {
            ret.numReturnValues = 0;
        }
        return ret;
    }

    struct ThickRayStruct {
        const cTupleReturn = true;
        int numReturnValues;
        Vector2f hit;
        Contact contact;
    }
    ThickRayStruct thickRayScript(Vector2f start, Vector2f dir, float maxLen,
        float r)
    {
        ThickRayStruct ret = void;
        bool hit = thickRay(start, dir, maxLen, r, ret.hit, ret.contact);
        if (hit) {
            ret.numReturnValues = 2;
        } else {
            ret.numReturnValues = 0;
        }
        return ret;
    }

    struct FreePointStruct {
        const cTupleReturn = true;
        int numReturnValues;
        Vector2f p;
    }
    FreePointStruct freePointScript(Vector2f p, float r) {
        FreePointStruct ret;
        bool ok = freePoint(p, r);
        if (ok) {
            ret.p = p;
            ret.numReturnValues = 1;
        }
        return ret;
    }
}

