module game.physic;
import game.common;
import utils.misc;
import utils.mylist;
import utils.time;
import utils.vector2;
import log = utils.log;
import str = std.string;
import utils.output;
import std.math : sqrt, PI;

//if you need to check a normal when there's almost no collision (i.e. when worm
//  is sitting on ground), add this value to the radius
final float cNormalCheck = 5;

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
        //world.mLog("update: %s", this);
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

    //percent of wind influence
    float windInfluence = 0.0f;

    bool isGlued;    //for sitting worms (can't be moved that easily)
    float glueForce = 0; //force required to move a glued worm away

    float walkingSpeed = 0; //pixels per seconds, or so
    float walkingClimb = 10; //pixels of height per 1-pixel which worm can climb
    //used during simulation
    float walkingTime = 0; //time until next pixel will be walked on
    Vector2f walkTo; //direction
    private bool mIsWalking;

    //used temporarely during "simulation"
    Vector2f deltav;

    //direction when flying etc., just rotation of the object
    float rotation = 0;
    //last known angle to ground
    float ground_angle = 0;

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
        isGlued = false;
        //xxx switch off walking mode?
        walkingSpeed = 0;
        mIsWalking = false;
        needUpdate();
    }

    //push a worm into a direction (i.e. for jumping)
    void push(Vector2f force) {
        //xxx maybe make that better
        velocity += force;
        checkUnglue(true);
    }

    //set rotation (using velocity)
    private void checkRotation() {
        auto len = velocity.length;
        //xxx insert a well chosen value here
        //NOTE: this check also prevents NaNs from getting through
        //intention is that changes must be big enough to change worm direction
        if (len > 0.001) {
            rotation = (velocity/len).toAngle();
        }
    }
    //set rotation (using move-vector from oldpos to pos)
    private void checkRotation2(Vector2f oldpos) {
        Vector2f dir = pos-oldpos;
        auto len = dir.length;
        if (len > 0.001) {
            rotation = (dir/len).toAngle();
        }
    }

    //whenever this object touches the ground, call this with the depth*normal
    //  vector
    private void checkGroundAngle(Vector2f dir) {
        auto len = dir.length;
        if (len > 0.001) {
            ground_angle = (dir/len).toAngle();
        }
    }

    //angle where the worm looks to, or is forced to look to (i.e. when sitting)
    float lookey(bool forceGlue = false) {
        if (!isGlued || forceGlue) {
            return rotation;
        } else {
            float angle = ground_angle+PI/2;
            //hm!?!?
            auto a = Vector2f.fromPolar(1, angle);
            auto b = Vector2f.fromPolar(1, rotation);
            if (a*b < 0)
                angle += PI; //+180 degrees
            //modf sucks!
            while (angle > PI*2) {
                angle -= PI*2;
            }
            return angle;
        }
    }

    char[] toString() {
        return str.format("%s: %s %s", toHash(), pos, velocity);
    }

    public void remove() {
        super.remove();
        //objects_node.removeFromList();
        world.mObjects.remove(this);
    }

    void setWalking(Vector2f dir) {
        //xxx
        walkingSpeed = 40;
        walkingTime = 0;
        walkTo = dir;
        //or switch off?
        if (dir.length < 0.01) {
            walkingSpeed = 0;
        } else {
            //will definitely try to walk, so look into walking direction
            checkRotation2(pos-dir);
        }
        mIsWalking = false;

        needUpdate();
    }

    //if object _attempts_ to walk
    bool isWalkingMode() {
        return walkingSpeed > 0;
    }

    //if object is walking and actually walks!
    bool isWalking() {
        return mIsWalking;
    }

    override protected void simulate(float deltaT) {
        super.simulate(deltaT);
        //take care of walking, walkingSpeed > 0 marks walking enabled
        if (isWalkingMode()) {
            walkingTime -= deltaT;
            if (walkingTime <= 0) {
                walkingTime = 1.0 / walkingSpeed; //time for one pixel
                //actually walk (or try to)

                //must stand on surface when walking
                if (!isGlued) {
                    log.registerLog("xxx")("no walk because not glued");
                    return;
                }

                //notice update before you forget it...
                needUpdate();

                Vector2f npos = pos + walkTo;

                //look where's bottom
                //NOTE: y1 > y2 means y1 is _blow_ y2
                bool first = true;
                for (float y = +walkingClimb; y >= -walkingClimb; y--) {

                    Vector2f nnpos = npos;
                    nnpos.y += y;
                    auto tmp = nnpos;
                    //log.registerLog("xxx")("%s %s", nnpos, pos);
                    bool res = world.collideGeometry(nnpos, radius);

                    if (!res) {
                        log.registerLog("xxx")("at %s -> %s", nnpos, nnpos-tmp);
                        //no collision, consider this to be bottom

                        auto oldpos = pos;

                        if (first) {
                            //even first tested location => most bottom, fall
                            log.registerLog("xxx")("fall-bottom");
                            pos = npos;
                            checkUnglue(true);
                        } else {
                            log.registerLog("xxx")("bottom at %s", y);
                            //walk to there...
                            npos.y += y;
                            pos = npos;
                        }

                        //check worm direction...
                        //disabled because: want worm to look to the real
                        //walking direction, this breaks when walking into caves
                        //where the worm gets stuck
                        //checkRotation2(oldpos);

                        //check ground normal... not good :)
                        //maybe physics should check the normal properly
                        nnpos = pos;
                        if (world.collideGeometry(nnpos, radius+cNormalCheck))
                            checkGroundAngle(nnpos-npos);

                        //jup, did walk
                        mIsWalking = true;

                        return;
                    }

                    first = false;
                }

                //if nothing was done, the worm (or the cow :) just can't walk
                mIsWalking = false;
            }
        }
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

class WindyForce : ConstantForce {
    Vector2f getAccelFor(PhysicObject o, float deltaT) {
        return accel * o.windInfluence;
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
                o.checkRotation();
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

                me.checkRotation();

                if (me.onImpact)
                    me.onImpact(other);
                //xxx: also, should it be possible to glue objects here?
            }
        }

        //check against geometry
        foreach (PhysicObject me; mObjects) {
            //no need to check then? (maybe)
            //xxx if landscape changed => need to check
            if (me.isGlued)
                continue;

            Vector2f normalsum = Vector2f(0);

            foreach (PhysicGeometry gm; mGeometryObjects) {
                Vector2f npos = me.pos;
                if (gm.collide(npos, me.radius)) {
                    Vector2f direction = npos - me.pos;

                    //hm, collide() should return the normal, maybe
                    Vector2f normal = direction.normal;

                    //seems to happen in in extreme situations only?
                    if (normal.isNaN()) {
                        continue;
                    }

                    normalsum += direction;

                    if (me.onImpact)
                        me.onImpact(null);
                    //xxx: glue objects that don't fly fast enough
                }
            }

            auto rnormal = normalsum.normal();
            if (!rnormal.isNaN()) {
                me.checkGroundAngle(normalsum);

                //set new position ("should" fit)
                me.pos = me.pos + normalsum;

                //mirror velocity on surface
                Vector2f proj = rnormal * (me.velocity * rnormal);
                me.velocity -= proj * 2.0f;

                //bumped against surface -> loss of energy
                me.velocity *= me.elasticity;

                //we collided with geometry, but were not fast enough!
                //  => worm gets glued, hahaha.
                if (me.velocity.length <= me.glueForce) {
                    me.isGlued = true;
                    //velocity must be set to 0 (or change glue handling)
                    me.velocity = Vector2f(0);
                }

                me.checkRotation();

                //what about unglue??
                me.needUpdate();
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

    this() {
        mObjects = new List!(PhysicObject)(PhysicObject.objects_node.getListNodeOffset());
        mAllObjects = new List!(PhysicBase)(PhysicBase.allobjects_node.getListNodeOffset());
        mForceObjects = new List!(PhysicForce)(PhysicForce.forces_node.getListNodeOffset());
        mGeometryObjects = new List!(PhysicGeometry)(PhysicGeometry.geometries_node.getListNodeOffset());
        mLog = log.registerLog("physlog");
    }
}
