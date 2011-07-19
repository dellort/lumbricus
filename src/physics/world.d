module physics.world;

import framework.drawing;

import std.math;
import utils.misc;
import utils.array;
import utils.list2;
import utils.random;
import utils.time;
import utils.vector2;
import utils.log;

import physics.base;
import physics.force;
import physics.physobj;
import physics.plane;
import physics.misc;
import physics.trigger;
import physics.contact;
import physics.links;
import physics.collide;
import physics.collisionmap;
import physics.broadphase;
import physics.sortandsweep;

class PhysicWorld {
    private ObjectList!(PhysicBase, "base_node") mAllObjects;
    private ObjectList!(PhysicForce, "forces_node") mForceObjects;
    private ObjectList!(PhysicTrigger, "triggers_node") mTriggers;
    private ObjectList!(PhysicContactGen, "cgen_node") mContactGenerators;
    private uint mLastTime;

    //dynamic and static object lists
    //dynamic = can move & mostly small circles, static = can't & large stuff
    private BroadPhase mDynamic, mStatic;

    private Contact[] mContacts;
    private int mContactCount;

    private static LogStruct!("physics") log;
    Random rnd;
    CollisionMap collide;
    CollideDelegate onCollide;

    ///r = random number generator to use
    public this(Random r) {
        argcheck(r);
        rnd = r;
        init_collide();
        collide = new CollisionMap();
        mAllObjects = new typeof(mAllObjects)();
        mForceObjects = new typeof(mForceObjects)();
        mTriggers = new typeof(mTriggers)();
        mContactGenerators = new typeof(mContactGenerators)();
        mContacts.length = 1024;  //xxx arbitrary number
        mDynamic = new BPSortAndSweep(collide);
        //mDynamic = new BPIterate(this);
        mStatic = new BPIterate(collide);
    }

    public void add(PhysicBase obj) {
        argcheck(obj);
        obj.world = this;
        obj.remove = false;
        mAllObjects.insert_tail(obj);
        if (auto o = cast(PhysicForce)obj)
            mForceObjects.insert_tail(o);
        if (auto o = cast(PhysicObject)obj) {
            auto list = o.isStatic ? mStatic : mDynamic;
            list.add(o);
        }
        if (auto o = cast(PhysicTrigger)obj)
            mTriggers.insert_tail(o);
        if (auto o = cast(PhysicContactGen)obj)
            mContactGenerators.insert_tail(o);
    }

    private void remove(PhysicBase obj) {
        obj.world = null;
        mAllObjects.remove(obj);
        if (auto o = cast(PhysicForce)obj)
            mForceObjects.remove(o);
        if (auto o = cast(PhysicObject)obj) {
            auto list = o.isStatic ? mStatic : mDynamic;
            list.remove(o);
        }
        if (auto o = cast(PhysicTrigger)obj)
            mTriggers.remove(o);
        if (auto o = cast(PhysicContactGen)obj)
            mContactGenerators.remove(o);
    }

    void debug_draw(Canvas c) {
        foreach (o; mAllObjects) {
            if (!o.dead)
                o.debug_draw(c);
        }
    }

    private enum cPhysTimeStepMs = 10;
    Vector2f gravity = {0, 0};

    public void simulate(Time currentTime) {
        uint ms = currentTime.msecs();
        while (mLastTime + cPhysTimeStepMs <= ms) {
            mLastTime += cPhysTimeStepMs;
            doSimulate(cast(float)cPhysTimeStepMs/1000.0f);
        }
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
        foreach (PhysicObject me; mDynamic.list) {
            //xxx the old code did something similar, but in a different place
            //position correction and rotation code depend from this
            me.lastPos = me.pos;

            //apply force generators
            foreach (PhysicForce f; mForceObjects) {
                f.applyTo(me, deltaT);
            }

            //update position and velocity
            me.update(deltaT);
        }

        foreach (PhysicObject o; mStatic.list) {
            o.update(deltaT);
        }

        //check triggers
        foreach (PhysicTrigger tr; mTriggers) {
            foreach (PhysicObject me; mDynamic.list) {
                //check glued objects too, or else not checking would be
                //misinterpreted as not active
                if (canCollide(tr, me))
                    tr.collide(me);
            }
        }

        mDynamic.collide(&handleContact);
        mStatic.collideWith(mDynamic, &handleContact);

        foreach (PhysicContactGen cg; mContactGenerators) {
            cg.process(deltaT, &handleContact);
        }

        resolveContacts(deltaT);

        foreach (PhysicContactGen cg; mContactGenerators) {
            cg.afterResolve(deltaT);
        }

        foreach (PhysicObject o; mDynamic.list) {
            //this may use pos/lastPos for advancing rotation
            o.checkRotation();
        }

        //lazy removing & dying
        foreach (PhysicBase obj; mAllObjects) {
            if (!obj.active) {
                if (obj.dead)
                    obj.doDie();
                remove(obj);
            }
        }
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
        foreach (ref contact; mContacts[0 .. mContactCount]) {
            //resolve contact
            contact.resolve(deltaT);
            //call collide event handler
            callCollide(contact); //call collision handler
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

    final BroadPhase dynamicObjects() { return mDynamic; }
    final BroadPhase staticObjects() { return mStatic; }

    //collide a shape with all objects
    //see Broadphase.collideShapeT
    //if you want to test only against all static or dynamic objects, use
    //  dynamicObjects./staticObjects.collideShapeT
    void collideShapeT(T)(ref T shape, CollisionType filter,
        CollideDelegate contactHandler)
    {
        void dolist(Broadphase b) {
            b.collideShapeT!(T)(shape, filter, contactHandler);
        }
        dolist(staticObjects);
        dolist(dynamicObjects);
    }

    //check how an object would collide with all the geometry
    bool collideGeometry(Vector2f pos, float radius, out Contact contact) {
        ContactMerger c;
        Circle circle = Circle(pos, radius);
        mStatic.collideShapeT(circle, collide.always, &c.handleContact);
        contact = c.contact;
        return c.collided;
    }

    //special collision function for walking code
    //assumes walking object is a sphere
    bool collideObjectsW(Vector2f pos, PhysicObject me) {
        float radius = me.posp.radius;
        //xxx also, what about optimized collision (broadphase); worth it?
        //xxx caller manually checks static objects
        foreach (PhysicObject o; mDynamic.list) {
            bool coll(Vector2f p, float r) {
                Contact ct;
                Circle c = Circle(p, r);
                return doCollide(Circle_ID, &c, o.shape_id, o.shape_ptr, ct);
            }

            if (!collide.canCollide(o.collision, me.walkingCollision))
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

    ///Shoot a thin ray into the world and test for object and geometry
    ///intersection.
    ///Params:
    ///  maxLen   = length of the ray, in pixels (range)
    ///  hitPoint = returns the absolute coords of the hitpoint
    ///  obj      = return the hit object (null if landscape was hit)
    //xxx only needed by girder (?) and lua ray weapons
    //xxx unify with thickRay
    bool shootRay(Vector2f start, Vector2f dir, float maxLen,
        out Vector2f hitPoint, out PhysicObject obj, out Vector2f normal)
    {
        //xxx range limit (we have nothing like world bounds)
        if (maxLen > 10000)
            maxLen = 10000;
        dir = dir.normal;
        enum float t_inc = 0.75f;
        enum float ray_radius = 1.0f;
        //check against objects
        Ray r;
        r.define(start, dir);
        float tmin = float.max;
        PhysicObject firstColl;
        //xxx dynamic and static separate
        foreach (PhysicObject o; mDynamic.list) {
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
    ///may be slightly more expensive than direct collision testing
    //xxx what about objects? should be handled too
    bool freePoint(ref Vector2f p, float r) {
        Contact contact;
        //r*2 chosen randomly (relatively high, hoping to get a good normal)
        if (!collideGeometry(p, r*2, contact))
            return true;
        if (contact.depth == float.infinity)
            return false; //no normal, no chance
        //try to move it outside the landscape along the normal
        //randomly chosen increment
        for (float d = 0; d < r*4; d += r/4) {
            auto p2 = p + contact.normal * d;
            Contact c2;
            if (!collideGeometry(p2, r, c2)) {
                p = p2;
                return true;
            }
        }
        return false;
    }

    void objectsAt(Vector2f pos, float r,
        scope bool delegate(PhysicObject obj) del)
    {
        argcheck(!!del);
        Circle circle = Circle(pos, r);
        void handler(ref Contact c) {
            del(c.obj[0]);
        }
        //xxx static?
        dynamicObjects.collideShapeT(circle, collide.always, &handler);
    }

    //********************************************************************
    //Below this line are wrappers of the functions above for scripting
    //(because most script languages have no ref/out parameters)
    //xxx this looks very messy

/+ xxx bring back
    struct CollideGeometryStruct {
        enum cTupleReturn = true;
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
+/

    struct ShootRayStruct {
        enum cTupleReturn = true;
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
        enum cTupleReturn = true;
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
        enum cTupleReturn = true;
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
        enum cTupleReturn = true;
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

