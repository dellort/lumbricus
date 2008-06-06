module physics.world;

import str = std.string;
import std.math : sqrt, PI;
import utils.misc;
import utils.array : arrayMap;
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
    Random rnd;

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
                if (canCollide(tr, me))
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

        //no collision if unwanted
        if (!canCollide(obj1, obj2))
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

        callCollide(c); //call collision handler
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

        callCollide(c);
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
            if (canCollide(o, gm) && gm.collide(o.pos, o.posp.radius, ncont)) {
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

    //handling of the collision map
private:

    CollisionType[char[]] mCollisionNames;
    CollisionType[] mCollisions; //indexed by CollisionType.index
    //pairs of things which collide with each other
    CollisionType[2][] mHits;

    //CollisionType.index indexes into this, see canCollide()
    bool[][] mTehMatrix;

    //if there are still unresolved CollisionType forward references
    //used for faster error checking (in canCollide() which is a hot-spot)
    bool mHadCTFwRef = true;

    //special types
    CollisionType mCTAlways, mCTNever, mCTAll;

    CollideDelegate mCollideHandler;

    CollisionType newCollisionType(char[] name) {
        assert(!(name in mCollisionNames));
        auto t = new CollisionType();
        t.name = name;
        mCollisionNames[t.name] = t;
        t.index = mCollisions.length;
        mCollisions ~= t;
        mHadCTFwRef = true; //because this is one
        return t;
    }

    public CollisionType collideNever() {
        return mCTNever;
    }
    public CollisionType collideAlways() {
        return mCTAlways;
    }

    //associate a collision handler with code
    //this can handle forward-referencing
    public void setCollideHandler(CollideDelegate oncollide) {
        mCollideHandler = oncollide;
    }

    public bool canCollide(CollisionType a, CollisionType b) {
        if (mHadCTFwRef) {
            checkCollisionHandlers();
        }
        assert(a && b, "no null parameters allowed, use collideNever/Always");
        assert(!a.undefined && !b.undefined, "undefined collision type");
        return mTehMatrix[a.index][b.index];
    }

    public bool canCollide(PhysicBase a, PhysicBase b) {
        assert(a && b);
        if (!a.collision)
            assert(false, "no collision for "~a.toString());
        if (!b.collision)
            assert(false, "no collision for "~b.toString());
        return canCollide(a.collision, b.collision);
    }

    //call the collision handler for these two objects
    public void callCollide(Contact c) {
        assert(!!mCollideHandler);
        mCollideHandler(c);
    }

    //check if all collision handlers were set; if not throw an error
    public void checkCollisionHandlers() {
        char[][] errors;

        foreach(t; mCollisions) {
            if (t.undefined) {
                errors ~= t.name;
            }
        }

        if (errors.length > 0) {
            throw new Exception(str.format("the following collision names were"
                " referenced, but not defined: %s", errors));
        }

        mHadCTFwRef = false;
    }

    //find a collision ID by name
    public CollisionType findCollisionID(char[] name) {
        if (name.length == 0) {
            return mCTNever;
        }

        if (name in mCollisionNames)
            return mCollisionNames[name];

        //a forward reference
        //checkCollisionHandlers() verifies if these are resolved
        return newCollisionType(name);
    }

    public CollisionType[] collisionTypes() {
        return mCollisions.dup;
    }

    //will rebuild mTehMatrix
    void rebuildCollisionStuff() {
        //return an array containing all transitive subclasses of cur
        CollisionType[] getAll(CollisionType cur) {
            CollisionType[] res = [cur];
            foreach (s; cur.subclasses) {
                res ~= getAll(s);
            }
            return res;
        }

        //set if a and b should collide to what
        void setCollide(CollisionType a, CollisionType b, bool what = true) {
            mTehMatrix[a.index][b.index] = what;
            mTehMatrix[b.index][a.index] = what;
        }

        mCTAlways.undefined = false;
        mCTNever.undefined = false;
        mCTAll.undefined = false;
        mHadCTFwRef = false;

        //allocate/clear the matrix
        mTehMatrix.length = mCollisions.length;
        foreach (ref line; mTehMatrix) {
            line.length = mTehMatrix.length;
            line[] = false;
        }

        foreach (ct; mCollisions) {
            mHadCTFwRef |= ct.undefined;
        }

        //relatively hack-like, put in all unparented collisions as subclasses,
        //without setting their parent member, else loadCollisions could cause
        //problems etc.; do that only for getAll()
        mCTAll.subclasses = null;
        foreach (ct; mCollisions) {
            if (!ct.superclass && ct !is mCTAll)
                mCTAll.subclasses ~= ct;
        }

        foreach (CollisionType[2] entry; mHits) {
            auto a = getAll(entry[0]);
            auto b = getAll(entry[1]);
            foreach (xa; a) {
                foreach (xb; b) {
                    setCollide(xa, xb);
                }
            }
        }

        foreach (ct; mCollisions) {
            setCollide(mCTAlways, ct, true);
            setCollide(mCTNever, ct, false);
        }
        //lol paradox
        setCollide(mCTAlways, mCTNever, false);
    }

    //"collisions" node from i.e. worm.conf
    public void loadCollisions(ConfigNode node) {
        auto defines = str.split(node.getStringValue("define"));
        foreach (d; defines) {
            auto cid = findCollisionID(d);
            if (!cid.undefined) {
                throw new Exception("collision name '" ~ cid.name
                    ~ "' redefined");
            }
            cid.undefined = false;
        }
        foreach (char[] name, char[] value; node.getSubNode("classes")) {
            //each entry is class = superclass
            auto cls = findCollisionID(name);
            auto supercls = findCollisionID(value);
            if (cls.superclass) {
                throw new Exception("collision class '" ~ cls.name ~ "' already"
                    ~ " has a superclass");
            }
            cls.superclass = supercls;
            //this is what we really need
            supercls.subclasses ~= cls;
            //check for cirular stuff
            auto t = cls;
            CollisionType[] trace = [t];
            while (t) {
                t = t.superclass;
                trace ~= t;
                if (t is cls) {
                    throw new Exception("circular subclass relation: " ~
                        str.join(arrayMap(trace, (CollisionType x) {
                            return x.name;
                        }), " -> ") ~ ".");
                }
            }
        }
        foreach (char[] name, char[] value; node.getSubNode("hit")) {
            //each value is an array of collision ids which collide with "name"
            auto hits = arrayMap(str.split(value), (char[] id) {
                return findCollisionID(id);
            });
            auto ct = findCollisionID(name);
            foreach (h; hits) {
                mHits ~= [ct, h];
            }
        }
        rebuildCollisionStuff();
    }

    void initCT() {
        mCTAlways = findCollisionID("always");
        mCTAll = findCollisionID("all");
        mCTNever = findCollisionID("never");
    }

    ///r = random number generator to use, null will create a new instance
    public this(Random r) {
        if (r) {
            rnd = new Random();
        } else {
            rnd = r;
        }
        initCT();
        mObjects = new List!(PhysicObject)(PhysicObject.objects_node.getListNodeOffset());
        mAllObjects = new List!(PhysicBase)(PhysicBase.allobjects_node.getListNodeOffset());
        mForceObjects = new List!(PhysicForce)(PhysicForce.forces_node.getListNodeOffset());
        mGeometryObjects = new List!(PhysicGeometry)(PhysicGeometry.geometries_node.getListNodeOffset());
        mTriggers = new List!(PhysicTrigger)(PhysicTrigger.triggers_node.getListNodeOffset());
        mLog = log.registerLog("physlog");
    }
}
