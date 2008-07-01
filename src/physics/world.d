module physics.world;

import str = std.string;
import std.math : sqrt, PI;
import utils.misc;
import utils.array;
import utils.configfile;
import utils.mylist;
import utils.random;
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
import physics.collisionmap;
import physics.broadphase;
import physics.sortandsweep;

//Uncomment to get detailed physics debugging log (slooooow)
//version = PhysDebug;

class PhysicWorld {
    private List!(PhysicBase) mAllObjects;
    private List!(PhysicForce) mForceObjects;
    private List!(PhysicGeometry) mGeometryObjects;
    private List!(PhysicObject) mObjects;
    private List!(PhysicTrigger) mTriggers;
    private uint mLastTime;

    private PhysicObject[] mObjArr;
    private BroadPhase broadphase;

    package log.Log mLog;
    Random rnd;
    CollisionMap collide;

    public void add(PhysicBase obj) {
        obj.world = this;
        mAllObjects.insert_tail(obj);
        if (auto o = cast(PhysicForce)obj)    mForceObjects.insert_tail(o);
        if (auto o = cast(PhysicGeometry)obj) mGeometryObjects.insert_tail(o);
        if (auto o = cast(PhysicObject)obj) {
            mObjects.insert_tail(o);
            mObjArr ~= o;
        }
        if (auto o = cast(PhysicTrigger)obj)  mTriggers.insert_tail(o);
    }

    private void remove(PhysicBase obj) {
        mAllObjects.remove(obj);
        if (auto o = cast(PhysicForce)obj)    mForceObjects.remove(o);
        if (auto o = cast(PhysicGeometry)obj) mGeometryObjects.remove(o);
        if (auto o = cast(PhysicObject)obj) {
            mObjects.remove(o);
            arrayRemoveUnordered(mObjArr, o);
        }
        if (auto o = cast(PhysicTrigger)obj)  mTriggers.remove(o);
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

        //collideObjects(deltaT);
        broadphase.collide(mObjArr, deltaT);

        foreach (PhysicObject me; mObjects) {
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
                if (collide.canCollide(tr, me))
                    tr.collide(me);
            }
        }

        checkUpdates();
    }

    void checkUpdates() {
        //do updates
        PhysicBase obj = mAllObjects.head();
        while (obj) {
            auto next = mAllObjects.next(obj);
            if (!obj.dead && obj.needsUpdate) {
                obj.doUpdate();
            }
            if (obj.dead) {
                obj.doDie();
                remove(obj);
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

        //no collision if unwanted
        if (!collide.canCollide(obj1, obj2))
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

        collide.callCollide(c); //call collision handler
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

        collide.callCollide(c);
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

    ///r = random number generator to use, null will create a new instance
    public this(Random r) {
        if (r) {
            rnd = new Random();
        } else {
            rnd = r;
        }
        collide = new CollisionMap();
        broadphase = new BPSortAndSweep(&checkObjectCollision);
        mObjects = new List!(PhysicObject)(PhysicObject.objects_node.getListNodeOffset());
        mAllObjects = new List!(PhysicBase)(PhysicBase.allobjects_node.getListNodeOffset());
        mForceObjects = new List!(PhysicForce)(PhysicForce.forces_node.getListNodeOffset());
        mGeometryObjects = new List!(PhysicGeometry)(PhysicGeometry.geometries_node.getListNodeOffset());
        mTriggers = new List!(PhysicTrigger)(PhysicTrigger.triggers_node.getListNodeOffset());
        mLog = log.registerLog("physlog");
    }
}
