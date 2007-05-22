module game.physic;
import game.common;
import utils.misc;
import utils.mylist;
import utils.time;
import utils.vector2;
import log = utils.log;
import str = std.string;
import utils.output;
import std.math : sqrt;

//base type for physic objects (which are contained in a PhysicWorld)
class PhysicBase {
    private mixin ListNodeMixin allobjects_node;
    //private bool mNeedSimulation;
    private bool mNeedUpdate;
    PhysicWorld world;
    //set to remove object after simulation
    bool dead = false;
    //in seconds
    private float mLifeTime = float.infinity;
    private float mRemainLifeTime;

    public void delegate() onDie;

    //call when object should be notified with doUpdate() after all physics done
    void needUpdate() {
        mNeedUpdate = true;
    }

    void lifeTime(float secs) {
        mLifeTime = secs;
        mRemainLifeTime = secs;
    }

    void delegate() onUpdate;

    //feedback to other parts of the game
    private void doUpdate() {
        if (onUpdate) {
            onUpdate();
        }
        world.mLog("update: %s", this);
    }

    protected void simulate(float deltaT) {
        if (mLifeTime != float.infinity) {
            mRemainLifeTime -= deltaT;
            if (mRemainLifeTime <= 0) {
                dead = true;
            }
        }
    }

    public void remove() {
        //allobjects_node.removeFromList();
        world.mAllObjects.remove(this);
    }
}

//simple physical object (has velocity, position, mass, radius, ...)
class PhysicObject : PhysicBase {
    private mixin ListNodeMixin objects_node;

    float elasticity = 0.99f; //loss of energy when bumping against a surface
    Vector2f pos; //pixels
    float radius = 10; //pixels
    float mass = 10; //in Milli-Worms, 10 Milli-Worms = 1 Worm
    Vector2f velocity; //in pixels per second
    //xxx to add: rotation, rotation-speed

    bool isGlued;    //for sitting worms (can't be moved that easily)
    float glueForce = 0; //force required to move a glued worm away

    //used temporarely during "simulation"
    Vector2f deltav;

    public void delegate(PhysicObject other) onImpact;

    //fast check if object can collide with other object
    //(includes reverse check)
    bool canCollide(PhysicBase other) {
        return true;
    }

    this() {
        velocity = Vector2f(0, 0);
        deltav = Vector2f(0, 0);
    }

    //look if the worm can't adhere to the rock surface anymore
    private void checkUnglue(bool forceit = false) {
        if ((isGlued && deltav.length < glueForce) && !forceit)
            return;
        //he flies away! arrrgh!
        velocity += deltav;
        deltav = Vector2f(0, 0);
        needUpdate();
    }

    char[] toString() {
        return str.format("%s: %s %s", toHash(), pos, velocity);
    }

    public void remove() {
        super.remove();
        objects_node.removeFromList();
    }
}

//wind, gravitation, ...
//what about explosions?
class PhysicForce : PhysicBase {
    private mixin ListNodeMixin forces_node;

    abstract Vector2f getAccelFor(PhysicObject o, float deltaT);

    public void remove() {
        super.remove();
        //forces_node.removeFromList();
        world.mForceObjects.remove(this);
    }
}

class ConstantForce : PhysicForce {
    //directed force, in Wormtons
    //(1 Wormton = 10 Milli-Worms * 1 Pixel / Seconds^2 [F=ma])
    Vector2f accel;

    Vector2f getAccelFor(PhysicObject, float deltaT) {
        return accel;
    }
}

class ExplosiveForce : PhysicForce {
    float impulse, radius;
    Vector2f pos;

    this() {
        //one time
        lifeTime = 0;
    }

    private float cDistDelta = 0.01f;
    Vector2f getAccelFor(PhysicObject o, float deltaT) {
        Vector2f v = (pos-o.pos);
        float dist = v.length;
        if (dist > cDistDelta)
            return -v.normal()*(impulse/deltaT)*(max(radius-dist,0f)/radius)/o.mass;
        else
            return Vector2f(0,0);
    }
}

//a geometric object which represent (almost) static parts of the map
//i.e. the deathzone (where worms go if they fly too far), the water, and solid
// border of the level (i.e. upper border in caves)
//also used for the bitmap part of the level
class PhysicGeometry : PhysicBase {
    private mixin ListNodeMixin geometries_node;

    //if outside geometry, return false and don't change pos
    //if inside or touching, return true and set pos to a corrected pos
    //(which is the old pos, moved along the normal at that point in the object)
    abstract bool collide(inout Vector2f pos, float radius);
}

//a plane which divides space into two regions (inside and outside plane)
class PlaneGeometry : PhysicGeometry {
    private Vector2f mNormal;
    private float mDistance; //distance of the plane from origin

    void define(Vector2f from, Vector2f to) {
        mNormal = (to - from).orthogonal.normal;
        mDistance = mNormal * from;
    }

    this(Vector2f from, Vector2f to) {
        define(from, to);
    }

    bool collide(inout Vector2f pos, float radius) {
        Vector2f out_pt = pos - mNormal * radius;
        float dist = mNormal * out_pt;
        if (dist >= mDistance)
            return false;
        float gap = mDistance - dist;
        pos += mNormal * gap;
        return true;
    }
}

class PhysicWorld {
    private List!(PhysicBase) mAllObjects;
    private List!(PhysicForce) mForceObjects;
    private List!(PhysicGeometry) mGeometryObjects;
    package List!(PhysicObject) mObjects;
    private uint mLastTime;

    private log.Log mLog;

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

    private void doSimulate(float deltaT) {
        foreach (PhysicBase b; mAllObjects) {
            b.simulate(deltaT);
        }

        //apply forces
        foreach (PhysicObject o; mObjects) {
            o.deltav = Vector2f(0, 0);
            foreach (PhysicForce f; mForceObjects) {
                o.deltav += f.getAccelFor(o, deltaT) * deltaT;
            }
            //adds the force to the velocity
            o.checkUnglue();
            if (!o.isGlued) {
                o.pos += o.velocity * deltaT;
            }
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
                float mindist = other.radius + me.radius;

                //check if they collide at all
                if (q_dist >= mindist*mindist)
                    continue;

                //no collision if unwanted
                if (!me.canCollide(other))
                    continue;

                //actually collide the stuff....

                //sitting worms are not safe
                me.checkUnglue(true);
                other.checkUnglue(true);

                float dist = sqrt(q_dist);
                float gap = mindist - dist;
                Vector2f nd = d / dist;

                if (nd.isNaN()) {
                    //NaN? maybe because dist was 0
                    nd = Vector2f(0);
                }

                //assert(fabs(nd.length()-1.0f) < 0.001);

                me.pos -= nd * (0.5f * gap);
                other.pos += nd * (0.5f * gap);

                float vca = me.velocity * nd;
                float vcb = other.velocity * nd;

                float dva = (vca * (me.mass - other.mass) + vcb * 2.0f * other.mass)
                            / (me.mass + other.mass) - vca;
                float dvb = (vcb * (other.mass - me.mass) + vca * 2.0f * me.mass)
                            / (me.mass + other.mass) - vcb;

                dva *= me.elasticity;
                dvb *= other.elasticity;

                me.velocity += dva * nd;
                other.velocity += dvb * nd;

                me.needUpdate();
                other.needUpdate();

                if (me.onImpact)
                    me.onImpact(other);
                //xxx: also, should it be possible to glue objects here?
            }
        }

        //check against geometry
        foreach (PhysicObject me; mObjects) {
            //no need to check then? (maybe)
            if (me.isGlued)
                continue;

            foreach (PhysicGeometry gm; mGeometryObjects) {
                Vector2f npos = me.pos;
                if (gm.collide(npos, me.radius)) {
                    Vector2f direction = npos - me.pos;

                    //set new position (forgot that d'oh)
                    me.pos = npos;

                    //hm, collide() should return the normal, maybe
                    Vector2f normal = direction.normal;

                    //mirror velocity on surface
                    Vector2f proj = normal * (me.velocity * normal);
                    me.velocity -= proj * 2.0f;

                    //bumped against surface -> loss of energy
                    me.velocity *= me.elasticity;

                    //what about unglue??
                    me.needUpdate();

                    if (me.onImpact)
                        me.onImpact(null);
                    //xxx: glue objects that don't fly fast enough
                }
            }
        }

        //do updates
        PhysicBase obj = mAllObjects.head();
        while (obj) {
            auto next = mAllObjects.next(obj);
            if (obj.mNeedUpdate) {
                obj.mNeedUpdate = false;
                obj.doUpdate();
            }
            if (obj.dead) {
                if (obj.onDie)
                    obj.onDie();
                obj.remove();
            }
            obj = next;
        }
    }

    this() {
        mObjects = new List!(PhysicObject)(PhysicObject.objects_node.getListNodeOffset());
        mAllObjects = new List!(PhysicBase)(PhysicBase.allobjects_node.getListNodeOffset());
        mForceObjects = new List!(PhysicForce)(PhysicForce.forces_node.getListNodeOffset());
        mGeometryObjects = new List!(PhysicGeometry)(PhysicGeometry.geometries_node.getListNodeOffset());
        mLog = log.registerLog("physlog");
    }
}
