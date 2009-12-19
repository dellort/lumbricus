module game.action.spriteactions;

///Contains actions that can be executed from event handlers in ActionSprite
///and that will (normally) add some sort of constant effect
///
///In contrast to WeaponActions, those cannot be run in an onfire event
///(note that it works the other way round)

import framework.framework;
import physics.world;
import game.action.base;
import game.action.wcontext;
import game.action.common;
import game.actionsprite;
import game.game;
import game.gobject;
import game.sprite;
import game.sequence;
import game.wcontrol;
import game.temp;
import utils.misc;
import utils.vector2;
import utils.time;
import utils.configfile;
import utils.log;
import utils.random;
import utils.randval;
import utils.factory;
import utils.reflection;

import tango.math.Math : PI;
import tango.math.IEEE : isNaN;

static this() {
    regAction!(state, "state")("state");
    regAction!(gravityCenter, "duration, gravity = 0, radius = 100")
        ("gravitycenter");
    regAction!(proximitySensor, "duration, radius = 20, trigger_delay = 1s,"
        ~ "collision = proxsensor, event = ontrigger")("proximitysensor");
    regAction!(walker, "inverse_direction")("walker");
    regAction!(randomJump, "duration, jump_strength = 100 -100,"
        ~ "jumps_per_sec = 1")("random_jump");
    regAction!(stuckTrigger, "duration, trigger_delay = 250ms, treshold = 5,"
        ~ "multiple, event = ontrigger")("stucktrigger");
    regAction!(controlRotate, "duration, init_direction, rotate_speed = 3.1415,"
        ~ "thrust = 0")("control_rotate");
}

void state(WeaponContext wx, char[] state) {
    if (!wx.ownerSprite)
        return;
    auto ssi = wx.ownerSprite.type.findState(state);
    if (ssi)
        wx.ownerSprite.setState(ssi);
}

void gravityCenter(WeaponContext wx, Time duration, float gravity,
    float radius)
{
    auto as = cast(ActionSprite)wx.ownerSprite;
    if (!as)
        return;
    wx.putObj(new GravityCenterAction(as, duration, gravity, radius));
}

void proximitySensor(WeaponContext wx, Time duration, float radius,
    Time triggerDelay, char[] collision, char[] eventId)
{
    auto as = cast(ActionSprite)wx.ownerSprite;
    if (!as)
        return;
    wx.putObj(new ProximitySensorAction(as, duration, radius, triggerDelay,
        collision, eventId));
}

//makes the parent projectile walk in looking direction
//it will keep walking forever
void walker(WeaponContext wx, bool inverseDirection) {
    if (!wx.ownerSprite)
        return;
    Vector2f walk = Vector2f.fromPolar(1.0f, wx.ownerSprite.physics.lookey);
    walk.y = 0;
    walk = walk.normal;
    if (inverseDirection)
        walk.x = -walk.x;
    wx.ownerSprite.physics.setWalking(walk);
}

void randomJump(WeaponContext wx, Time duration, Vector2f jumpStrength,
    float jumpsPerSec)
{
    auto as = cast(ActionSprite)wx.ownerSprite;
    if (!as)
        return;
    wx.putObj(new RandomJumpAction(as, duration, jumpStrength, jumpsPerSec));
}

void stuckTrigger(WeaponContext wx, Time duration, Time triggerDelay,
    float treshold, bool multiple, char[] eventId)
{
    auto as = cast(ActionSprite)wx.ownerSprite;
    if (!as)
        return;
    wx.putObj(new StuckTriggerAction(as, duration, triggerDelay, treshold,
        multiple, eventId));
}

void controlRotate(WeaponContext wx, Time duration, float initDirection,
    float rotateSpeed, float thrust)
{
    auto as = cast(ActionSprite)wx.ownerSprite;
    if (!as)
        return;
    wx.putObj(new ControlRotateAction(as, duration, initDirection,
        rotateSpeed, thrust));
}



class SpriteAction : DelayedObj {
    protected {
        ActionSprite mParent;
    }

    this(ActionSprite parent, Time duration) {
        if (duration == Time.Null)
            duration = timeHours(9999);
        mParent = parent;
        super(parent.engine, duration);
    }

    this (ReflectCtor c) {
        super(c);
    }

    override void simulate(float deltaT) {
        super.simulate(deltaT);
        if (mParent.physics.dead)
            kill();
    }
}

class GravityCenterAction : SpriteAction {
    private {
        GravityCenter mGravForce;
    }

    this(ActionSprite parent, Time duration, float gravity, float radius) {
        super(parent, duration);
        mGravForce = new GravityCenter();
        mGravForce.accel = gravity;
        mGravForce.radius = radius;
        mGravForce.pos = mParent.physics.pos;
        engine.physicworld.add(mGravForce);
    }
    this (ReflectCtor c) {
        super(c);
    }

    override protected void updateActive() {
        if (!active)
            mGravForce.dead = true;
    }

    override void simulate(float deltaT) {
        super.simulate(deltaT);
        mGravForce.pos = mParent.physics.pos;
    }
}

class ProximitySensorAction : SpriteAction {
    private {
        ZoneTrigger mTrigger;
        PhysicZoneCircle mZone;
        Time mFireTime, mTriggerDelay;
        char[] mEventId;
    }

    this(ActionSprite parent, Time duration, float radius, Time triggerDelay,
        char[] collision, char[] eventId)
    {
        super(parent, duration);
        mEventId = eventId;
        mTriggerDelay = triggerDelay;
        mZone = new PhysicZoneCircle(mParent.physics.pos, radius);
        mTrigger = new ZoneTrigger(mZone);
        mTrigger.collision = engine.physicworld.collide.findCollisionID(
            collision);
        mTrigger.onTrigger = &trigTrigger;
        mFireTime = Time.Never;
        engine.physicworld.add(mTrigger);
    }

    this (ReflectCtor c) {
        super(c);
        c.types().registerMethod(this, &trigTrigger, "trigTrigger");
    }

    override protected void updateActive() {
        if (!active)
            mTrigger.dead = true;
    }

    private void trigTrigger(PhysicTrigger sender, PhysicObject other) {
        if (mFireTime == Time.Never) {
            mFireTime = engine.gameTime.current + mTriggerDelay;
        }
    }

    bool activity() {
        return mFireTime != Time.Never;
    }

    override void simulate(float deltaT) {
        super.simulate(deltaT);
        mZone.pos = mParent.physics.pos;
        if (engine.gameTime.current >= mFireTime) {
            //execute trigger event (which maybe blows the projectile)
            mParent.doEvent(mEventId);
            //xxx implement multi-activation sensors
            kill();
        }
    }
}

//makes the parent projectile jump randomly when glued
class RandomJumpAction : SpriteAction {
    private {
        Vector2f mJumpStrength;
        float mJumpsPerSec;
    }

    this(ActionSprite parent, Time duration, Vector2f jumpStrength,
        float jumpsPerSec)
    {
        super(parent, duration);
        mJumpStrength = jumpStrength;
        mJumpsPerSec = jumpsPerSec;
    }

    this (ReflectCtor c) {
        super(c);
    }

    override void simulate(float deltaT) {
        //xxx I think this is wrong (i.e. framerate-dependent)
        float p = mJumpsPerSec * deltaT;
        if (engine.rnd.nextDouble2() < p && mParent.physics.isGlued) {
            doJump();
        }
    }

    private void doJump() {
        auto look = Vector2f.fromPolar(1, mParent.physics.lookey);
        look.y = 0;
        look = look.normal(); //get sign *g*
        look.y = 1;
        mParent.physics.addImpulse(look.mulEntries(mJumpStrength));
    }
}

//will trigger an event when the parent projectile is no longer moving
//(independant of gluing)
class StuckTriggerAction : SpriteAction {
    private {
        struct DeltaSample {
            Time t;
            float delta = 0;
        }

        Vector2f mPosOld;
        DeltaSample[] mSamples;
        bool mActivated = false;
        Time mTriggerDelay;
        float mTreshold;
        bool mMultiple;
        char[] mEventId;
    }

    this(ActionSprite parent, Time duration, Time triggerDelay,
        float treshold, bool multiple, char[] eventId)
    {
        super(parent, duration);
        mPosOld = mParent.physics.pos;
        mTriggerDelay = triggerDelay;
        mTreshold = treshold;
        mMultiple = multiple;
        mEventId = eventId;
    }

    this (ReflectCtor c) {
        super(c);
    }

    //adds a position-change sample to the list (with timestamp)
    private void addSample(float delta) {
        Time t = engine.gameTime.current;
        foreach (ref s; mSamples) {
            if (t - s.t > mTriggerDelay) {
                //found invalid sample -> replace
                s.t = t;
                s.delta = delta;
                //one triggerDelay has passed
                mActivated = true;
                return;
            }
        }
        //no invalid sample found -> allocate new
        DeltaSample s;
        s.t = t;
        s.delta = delta;
        mSamples ~= s;
    }

    //sums position changes within trigger_delay interval
    //older samples are ignored
    private float integrate() {
        Time t = engine.gameTime.current;
        float ret = 0.0f;
        int c;
        foreach (ref s; mSamples) {
            if (t - s.t <= mTriggerDelay) {
                ret += s.delta;
                c++;
            }
        }
        return ret;
    }

    override void simulate(float deltaT) {
        super.simulate(deltaT);
        Vector2f p = mParent.physics.pos;
        addSample((mPosOld-p).length);
        mPosOld = p;
        if (integrate() < mTreshold && mActivated) {
            //execute trigger event (which maybe blows the projectile)
            mParent.doEvent(mEventId);
            if (mMultiple) {
                //reset
                mActivated = false;
                mSamples = null;
            } else {
                kill();
            }
        }
    }
}

class ControlRotateAction : SpriteAction, Controllable {
    private {
        WormControl mMember;
        Vector2f mMoveVector;
        float mDirection, mRotateSpeed, mThrust;
    }

    this(ActionSprite parent, Time duration, float initDirection,
        float rotateSpeed, float thrust)
    {
        super(parent, duration);
        mMember = engine.controller.controlFromGameObject(mParent, true);
        mMember.pushControllable(this);
        //if given, use direction from config, physics velocity otherwise
        if (!isNaN(initDirection))
            mDirection = initDirection;
        else
            mDirection = mParent.physics.velocity.toAngle();
        assert(mDirection == mDirection);
        mRotateSpeed = rotateSpeed;
        mThrust = thrust;
        setForce();
    }

    this (ReflectCtor c) {
        super(c);
    }

    override protected void updateActive() {
        if (!active) {
            mParent.physics.resetLook();
            mMember.releaseControllable(this);
        }
    }

    override void simulate(float deltaT) {
        mDirection += mMoveVector.x * mRotateSpeed * deltaT;
        setForce();
        super.simulate(deltaT);
    }

    private void setForce() {
        mParent.physics.selfForce = Vector2f.fromPolar(1.0f, mDirection)
            * mThrust;
    }

    //-- Controllable implementation

    bool fire(bool keyDown) {
        return false;
    }

    bool jump(JumpMode j) {
        return false;
    }

    bool move(Vector2f m) {
        mMoveVector = m;
        return true;
    }

    GObjectSprite getSprite() {
        return mParent;
    }

    //-- end Controllable
}
