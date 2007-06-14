module game.physic;
import game.common;
import utils.misc;
import utils.mylist;
import utils.time;
import utils.vector2;
import log = utils.log;
import str = std.string;
import conv = std.conv;
import utils.output;
import utils.configfile : ConfigNode;
import std.math : sqrt, PI, abs, copysign;

//if you need to check a normal when there's almost no collision (i.e. when worm
//  is sitting on ground), add this value to the radius
final float cNormalCheck = 5;

//constant from Stokes's drag
const cStokesConstant = 6*PI;

//the physics stuff uses an ID to test if collision between objects is wanted
//all physic objects (type PhysicBase) have an CollisionType
typedef uint CollisionType;

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

    CollisionType collision;

    //call when object should be notified with doUpdate() after all physics done
    void needUpdate() {
        mNeedUpdate = true;
    }

    void lifeTime(float secs) {
        mLifeTime = secs;
        mRemainLifeTime = secs;
    }

    public void delegate() onUpdate;
    public void delegate(PhysicBase other) onImpact;
    public void delegate() onDie;

    //feedback to other parts of the game
    protected void doUpdate() {
        if (onUpdate) {
            onUpdate();
        }
        //world.mLog("update: %s", this);
    }

    //fast check if object can collide with other object
    //(includes reverse check)
    bool canCollide(PhysicBase other) {
        return world.canCollide(collision, other.collision);
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

//PhysicalObjectStaticProperties
//challenge: find a better name
//contains all values which are considered not-changing physical properties of
//an object, i.e. they won't be changed by the simulation loop at all
//code to load from ConfigFile at the end of this file
struct POSP {
    float elasticity = 0.99f; //loss of energy when bumping against a surface
    float radius = 10; //pixels
    float mass = 10; //in Milli-Worms, 10 Milli-Worms = 1 Worm

    //percent of wind influence
    float windInfluence = 0.0f;
    //explosion influence
    float explosionInfluence = 1.0f;

    //fixate vector: how much an object can be moved in x/y directions
    //i.e. frozen worms will have fixate.x == 0
    //immobile objects will have fixate.length == 0
    //maybe should be 1 or 0, else funny things might happen
    Vector2f fixate = {1.0f,1.0f};

    //xxx maybe redefine to minimum velocity required to start simulaion again
    float glueForce = 0; //force required to move a glued worm away

    float walkingSpeed = 10; //pixels per seconds, or so
    float walkingClimb = 10; //pixels of height per 1-pixel which worm can climb

    //influence through damage (0 = invincible, 1 = normal)
    float damageable = 0.0f;
    float damageThreshold = 1.0f;

    //amount of force to take before taking fall damage
    float sustainableForce = 150;
    //force multiplier
    float fallDamageFactor = 0.1f;

    float mediumViscosity = 0.0f;
}

//simple physical object (has velocity, position, mass, radius, ...)
class PhysicObject : PhysicBase {
    private mixin ListNodeMixin objects_node;

    POSP posp;

    Vector2f pos; //pixels
    //in pixels per second, readonly for external code!
    Vector2f velocity = {0,0};

    void addVelocity(Vector2f v) {
        //erm... hehe.
        velocity += v;
    }

    bool isGlued;    //for sitting worms (can't be moved that easily)

    //used during simulation
    float walkingTime = 0; //time until next pixel will be walked on
    Vector2f walkTo; //direction
    private bool mWalkingMode;
    private bool mIsWalking;

    float lifepower = float.infinity;

    void applyDamage(float severity) {
        auto delta = -severity*posp.damageable;
        //world.mLog("damage: %s/%s", severity, delta);
        if (abs(delta) > posp.damageThreshold) {
            lifepower += delta;
            needUpdate();
            //die muaha
            //xxx rather not (WormSprite is died by GameController)
            //if (lifepower <= 0)
              //  dead = true;
        }
    }

    //sry
    int lifepowerInt() {
        return cast(int)(lifepower + 0.5f);
    }


    //constant force the object adds to itself
    //used for jetpack or flying weapons
    Vector2f selfForce = {0, 0};
    //hacky: force didn't really work for jetpack
    Vector2f selfAddVelocity = {0, 0};

    //direction when flying etc., just rotation of the object
    float rotation = 0;
    //last known angle to ground
    float ground_angle = 0;
    //last known surface normal
    Vector2f surface_normal;

    this() {
    }

    //the worm couldn't adhere to the rock surface anymore
    //called from the PhysicWorld simulation loop only
    private void doUnglue() {
        world.mLog("unglue object %s", this);
        //he flies away! arrrgh!
        isGlued = false;
        mWalkingMode = false;
        mIsWalking = false;
        needUpdate();
    }

    //push a worm into a direction (i.e. for jumping)
    void push(Vector2f force) {
        //xxx maybe make that better
        velocity += force;
        doUnglue();
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
            surface_normal = (dir/len);
            ground_angle = surface_normal.toAngle();
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
        return str.format("[%s: %s %s]", toHash(), pos, velocity);
    }

    public void remove() {
        super.remove();
        //objects_node.removeFromList();
        world.mObjects.remove(this);
    }

    void setWalking(Vector2f dir) {
        walkingTime = 0;
        walkTo = dir;
        //or switch off?
        //NOTE: restrict to X axis
        if (abs(dir.x) < 0.01) {
            mWalkingMode = false;
        } else {
            //will definitely try to walk, so look into walking direction
            checkRotation2(pos-dir);
            mWalkingMode = true;
        }
        mIsWalking = false;

        needUpdate();
    }

    //if object _attempts_ to walk
    bool isWalkingMode() {
        return mWalkingMode;
    }

    //if object is walking and actually walks!
    bool isWalking() {
        return mIsWalking;
    }

    // Trigger support ------------->

    public void delegate(char[] triggerId) onTriggerEnter;
    public void delegate(char[] triggerId) onTriggerExit;

    private bool[char[]] mTriggerStates, mLastTriggerStates;

    protected void doUpdate() {
        super.doUpdate();
        //update trigger states and trigger events
        foreach (char[] trigId, inout bool curTrigSt; mTriggerStates) {
            bool* last = (trigId in mLastTriggerStates);
            if (!last || *last != curTrigSt) {
                mLastTriggerStates[trigId] = curTrigSt;
                if (curTrigSt) {
                    if (onTriggerEnter)
                        onTriggerEnter(trigId);
                } else {
                    if (onTriggerExit)
                        onTriggerExit(trigId);
                }
            }
            curTrigSt = false;
        }
    }

    public bool triggerActive(char[] triggerId) {
        bool* trigSt = (triggerId in mLastTriggerStates);
        if (trigSt)
            return *trigSt;
        else
            return false;
    }

    protected void triggerCollide(char[] triggerId) {
        mTriggerStates[triggerId] = true;
    }

    // <------------- Trigger support

    override protected void simulate(float deltaT) {
        super.simulate(deltaT);
        //take care of walking, walkingSpeed > 0 marks walking enabled
        if (isWalkingMode()) {
            walkingTime -= deltaT;
            if (walkingTime <= 0) {
                walkingTime = 1.0 / posp.walkingSpeed; //time for one pixel
                //actually walk (or try to)

                //must stand on surface when walking
                if (!isGlued) {
                    world.mLog("no walk because not glued");
                    return;
                }

                //notice update before you forget it...
                needUpdate();

                Vector2f npos = pos + walkTo;

                //look where's bottom
                //NOTE: y1 > y2 means y1 is _blow_ y2
                bool first = true;
                for (float y = +posp.walkingClimb; y >= -posp.walkingClimb; y--)
                {

                    Vector2f nnpos = npos;
                    nnpos.y += y;
                    auto tmp = nnpos;
                    //log.registerLog("xxx")("%s %s", nnpos, pos);
                    bool res = world.collideGeometry(nnpos, posp.radius);

                    if (!res) {
                        world.mLog("walk at %s -> %s", nnpos, nnpos-tmp);
                        //no collision, consider this to be bottom

                        auto oldpos = pos;

                        if (first) {
                            //even first tested location => most bottom, fall
                            world.mLog("walk: fall-bottom");
                            pos = npos;
                            doUnglue();
                        } else {
                            world.mLog("walk: bottom at %s", y);
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
                        if (world.collideGeometry(nnpos, posp.radius+cNormalCheck))
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

//base template for changers that will update a value over time until a
//specified target is reached
//use this as mixin and implement updateStep(float deltaT) (strange D world...)
template PhysicTimedChanger(T) {
    //current value
    protected T mValue;
    //do a change over time to target value, changing with changePerSec/s
    T target;
    T changePerSec;
    //callback that is executed when the real value changes
    void delegate(T newValue) onValueChange;

    this(T startValue, void delegate(T newValue) valChange) {
        onValueChange = valChange;
        value = startValue;
    }

    void value(T v) {
        mValue = v;
        target = v;
        doValueChange();
    }
    T value() {
        return mValue;
    }

    private void doValueChange() {
        if (onValueChange)
            onValueChange(mValue);
    }

    protected void simulate(float deltaT) {
        super.simulate(deltaT);
        if (mValue != target) {
            //this is expensive, but only executed when the value is changing
            updateStep(deltaT);
            doValueChange();
        }
    }
}

class PhysicTimedChangerFloat : PhysicBase {
    mixin PhysicTimedChanger!(float);

    protected void updateStep(float deltaT) {
        float diff = target - mValue;
        mValue += copysign(changePerSec*deltaT,diff);
        float diffn = target - mValue;
        float sgn = diff*diffn;
        if (sgn < 0)
            mValue = target;
    }
}

class PhysicTimedChangerVector2f : PhysicBase {
    mixin PhysicTimedChanger!(Vector2f);

    protected void updateStep(float deltaT) {
        Vector2f diff = target - mValue;
        mValue.x += copysign(changePerSec.x*deltaT,diff.x);
        mValue.y += copysign(changePerSec.y*deltaT,diff.y);
        Vector2f diffn = target - mValue;
        Vector2f sgn = diff.mulEntries(diffn);
        if (sgn.x < 0)
            mValue.x = target.x;
        if (sgn.y < 0)
            mValue.y = target.y;
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
        return accel * o.posp.windInfluence;
    }
}

class ExplosiveForce : PhysicForce {
    float damage;
    Vector2f pos;

    this() {
        //one time
        lifeTime = 0;
    }

    private const cDamageToImpulse = 40.0f;
    private const cDamageToRadius = 2.0f;

    public float radius() {
        return damage*cDamageToRadius;
    }

    private float cDistDelta = 0.01f;
    Vector2f getAccelFor(PhysicObject o, float deltaT) {
        float impulse = damage*cDamageToImpulse;
        Vector2f v = (pos-o.pos);
        float dist = v.length;
        if (dist > cDistDelta) {
            float r = max(radius-dist,0f)/radius;
            o.applyDamage(r*damage);
            return -v.normal()*(impulse/deltaT)*r/o.posp.mass
                    * o.posp.explosionInfluence;
        } else {
            return Vector2f(0,0);
        }
    }
}

class GravityCenter : PhysicForce {
    float accel, radius;
    Vector2f pos;

    private float cDistDelta = 0.01f;
    Vector2f getAccelFor(PhysicObject o, float deltaT) {
        Vector2f v = (pos-o.pos);
        float dist = v.length;
        if (dist > cDistDelta) {
            float r = (max(radius-dist,0f)/radius);
            return v.normal()*accel*r;
        } else {
            return Vector2f(0,0);
        }
    }
}

//a geometric object which represent (almost) static parts of the map
//i.e. the deathzone (where worms go if they fly too far), the water, and solid
// border of the level (i.e. upper border in caves)
//also used for the bitmap part of the level
class PhysicGeometry : PhysicBase {
    private mixin ListNodeMixin geometries_node;

    //generation counter, increased on every change
    int generationNo = 0;
    private int lastKnownGen = -1;

    //if outside geometry, return false and don't change pos
    //if inside or touching, return true and set pos to a corrected pos
    //(which is the old pos, moved along the normal at that point in the object)
    abstract bool collide(inout Vector2f pos, float radius);

    public void remove() {
        super.remove();
        world.mGeometryObjects.remove(this);
    }
}

struct Plane {
    Vector2f mNormal = {1,0};
    float mDistance = 0; //distance of the plane from origin

    void define(Vector2f from, Vector2f to) {
        mNormal = (to - from).orthogonal.normal;
        mDistance = mNormal * from;
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

//a plane which divides space into two regions (inside and outside plane)
class PlaneGeometry : PhysicGeometry {
    Plane plane;

    this(Vector2f from, Vector2f to) {
        plane.define(from, to);
    }

    this() {
    }

    bool collide(inout Vector2f pos, float radius) {
        return plane.collide(pos, radius);
    }
}

//base class for trigger regions
//objects can be inside or outside and will trigger a callback when inside
//remember to set id for trigger handler
class PhysicTrigger : PhysicBase {
    private mixin ListNodeMixin triggers_node;

    //identifier for callback procedure
    char[] id = "trigid_undefined";

    //return true when object is inside, false otherwise
    abstract bool collide(Vector2f pos, float radius);

    public void remove() {
        super.remove();
        world.mTriggers.remove(this);
    }
}

//little copy+paste, sorry
class PlaneTrigger : PhysicTrigger {
    Plane plane;

    this(Vector2f from, Vector2f to) {
        plane.define(from, to);
    }

    this() {
    }

    bool collide(Vector2f pos, float radius) {
        return plane.collide(pos, radius);
    }
}

class PhysicWorld {
    private List!(PhysicBase) mAllObjects;
    private List!(PhysicForce) mForceObjects;
    private List!(PhysicGeometry) mGeometryObjects;
    package List!(PhysicObject) mObjects;
    package List!(PhysicTrigger) mTriggers;
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
    public void add(PhysicTrigger obj) {
        mTriggers.insert_tail(obj);
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
            foreach (PhysicForce f; mForceObjects) {
                o.velocity += f.getAccelFor(o, deltaT) * deltaT;
            }

            //xxx this with addVelocity can't be correct?
            o.velocity += o.selfAddVelocity + (o.selfForce * deltaT);

            //remove unwanted parts
            o.velocity = o.velocity.mulEntries(o.posp.fixate);

            //Stokes's drag
            o.velocity += ((o.posp.mediumViscosity*cStokesConstant*o.posp.radius)
                * -o.velocity)/o.posp.mass * deltaT;

            auto vel = o.velocity;

            if (o.isGlued) {
                //argh. so a velocity is compared to a "force"... sigh.
                //surface_normal is valid, as objects are always glued to the ground
                if (vel.length <= o.posp.glueForce && vel*o.surface_normal <= 0) {
                    //xxx: reset the velocity vector, because else, the object
                    //     will be unglued even it stands on the ground
                    //     this should be changed such that the object is only
                    //     unglued if it actually could be moved...
                    o.velocity = Vector2f(0);
                    //skip to next object, don't change position
                    continue;
                }
                o.doUnglue();
            }

            o.pos += vel * deltaT;
            o.needUpdate();
            o.checkRotation();
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
                float mindist = other.posp.radius + me.posp.radius;

                //check if they collide at all
                if (q_dist >= mindist*mindist)
                    continue;

                //no collision if unwanted
                if (!me.canCollide(other))
                    continue;

                //actually collide the stuff....

                //sitting worms are not safe
                //if it doesn't matter, they'll be glued again in the next frame
                me.doUnglue();
                other.doUnglue();

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

                float ma = me.posp.mass, mb = other.posp.mass;

                float dva = (vca * (ma - mb) + vcb * 2.0f * mb)
                            / (ma + mb) - vca;
                float dvb = (vcb * (mb - ma) + vca * 2.0f * ma)
                            / (ma + mb) - vcb;

                dva *= me.posp.elasticity;
                dvb *= other.posp.elasticity;

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
            //check triggers
            //check glued objects too, or else not checking would be
            //misinterpreted as not active
            foreach (PhysicTrigger tr; mTriggers) {
                if (tr.collide(me.pos, me.posp.radius)) {
                    me.triggerCollide(tr.id);
                }
            }

            //no need to check then? (maybe)
            //xxx if landscape changed => need to check
            Vector2f normalsum = Vector2f(0);

            bool forceCheck = false;
            foreach (PhysicGeometry gm; mGeometryObjects) {
                if (gm.lastKnownGen < gm.generationNo) {
                    //object has changed
                    forceCheck = true;
                    gm.lastKnownGen = gm.generationNo;
                }
            }

            if (me.isGlued && !forceCheck)
                continue;

            foreach (PhysicGeometry gm; mGeometryObjects) {
                Vector2f npos = me.pos;
                if (gm.collide(npos, me.posp.radius)) {
                    //kind of hack for LevelGeometry
                    //if the pos didn't change at all, but a collision was
                    //reported, assume the object is completely within the
                    //landscape...
                    //(xxx: uh, actually a dangerous hack)
                    if (npos == me.pos) {
                        //so pull it out along the velocity vector
                        npos -= me.velocity.normal*me.posp.radius*2;
                    }

                    Vector2f direction = npos - me.pos;
                    normalsum += direction;

                    if (me.onImpact && !me.isGlued)
                        me.onImpact(gm);
                    //xxx: glue objects that don't fly fast enough
                }
            }

            auto rnormal = normalsum.normal();
            if (!rnormal.isNaN()) {
                //don't check again for already glued objects
                if (!me.isGlued) {
                    me.checkGroundAngle(normalsum);

                    //set new position ("should" fit)
                    me.pos = me.pos + normalsum.mulEntries(me.posp.fixate);

                    //direction the worm is flying to
                    auto flydirection = me.velocity.normal;

                    //force directed against surface
                    //xxx in worms, only vertical speed counts
                    auto bump = -(flydirection * rnormal);

                    if (bump < 0)
                        bump = 0;

                    //use this for damage
                    me.applyDamage(max(me.velocity.length-me.posp.sustainableForce,0f)*bump*me.posp.fallDamageFactor);

                    //mirror velocity on surface
                    Vector2f proj = rnormal * (me.velocity * rnormal);
                    me.velocity -= proj * (1.0f + me.posp.elasticity);

                    //bumped against surface -> loss of energy
                    //me.velocity *= me.posp.elasticity;

                    //we collided with geometry, but were not fast enough!
                    //  => worm gets glued, hahaha.
                    //xxx maybe do the gluing somewhere else?
                    if (me.velocity.mulEntries(me.posp.fixate).length
                        <= me.posp.glueForce)
                    {
                        me.isGlued = true;
                        mLog("glue object %s", me);
                        //velocity must be set to 0 (or change glue handling)
                        //ok I did change glue handling.
                        me.velocity = Vector2f(0);
                    }

                    me.checkRotation();

                    //what about unglue??
                    me.needUpdate();
                }
            } else {
                if (me.isGlued) {
                    //no valid normal although glued -> terrain disappeared
                    me.doUnglue();
                    me.needUpdate();
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

    //handling of the collision map

    //for now, do it this strange way, rectangular array would be better, faster
    //and more sane, but: you don't know the upper bounds of the array yet
    private struct Collide {
        CollisionType a, b;
        //not needed for > DMD1.014 (but 1.014 is buggy on struct literals)
        static Collide opCall(CollisionType a, CollisionType b)
            {Collide c; c.a=a; c.b = b; return c;}
    }
    private int[Collide] mCollisionMap;
    private CollisionType mCollisionAlloc;

    CollisionType newCollisionType() {
        return ++mCollisionAlloc;
    }

    //a should colide with b, and b with a (commutative)
    //  cookie = returned by canCollide() on this collision
    //raises error if collision is already set
    void setCollide(CollisionType a, CollisionType b, int cookie) {
        if (canCollide(a, b)) {
            throw new Exception("no.");
        }
        mCollisionMap[Collide(a, b)] = cookie;
    }
    bool canCollide(CollisionType a, CollisionType b, out int cookie) {
        int* ptr = Collide(a, b) in mCollisionMap;
        if (!ptr)
            ptr = Collide(b, a) in mCollisionMap;
        if (ptr) {
            cookie = *ptr;
            return true;
        } else {
            return false;
        }
    }
    bool canCollide(CollisionType a, CollisionType b) {
        int tmp;
        return canCollide(a, b, tmp);
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

void loadPOSPFromConfig(ConfigNode node, inout POSP posp) {
    posp.elasticity = node.getFloatValue("elasticity", posp.elasticity);
    posp.radius = node.getFloatValue("radius", posp.radius);
    posp.mass = node.getFloatValue("mass", posp.mass);
    posp.windInfluence = node.getFloatValue("wind_influence",
        posp.windInfluence);
    posp.explosionInfluence = node.getFloatValue("explosion_influence",
        posp.explosionInfluence);
    posp.fixate = readVector(node.getStringValue("fixate", str.format("%s %s",
        posp.fixate.x, posp.fixate.y)));
    posp.glueForce = node.getFloatValue("glue_force", posp.glueForce);
    posp.walkingSpeed = node.getFloatValue("walking_speed", posp.walkingSpeed);
    posp.walkingClimb = node.getFloatValue("walking_climb", posp.walkingClimb);
    posp.damageable = node.getFloatValue("damageable", posp.damageable);
    posp.damageThreshold = node.getFloatValue("damage_threshold",
        posp.damageThreshold);
    posp.mediumViscosity = node.getFloatValue("medium_viscosity",
        posp.mediumViscosity);
}

//xxx duplicated from generator.d
private Vector2f readVector(char[] s) {
    char[][] items = str.split(s);
    if (items.length != 2) {
        throw new Exception("invalid point value");
    }
    Vector2f pt;
    pt.x = conv.toFloat(items[0]);
    pt.y = conv.toFloat(items[1]);
    return pt;
}
