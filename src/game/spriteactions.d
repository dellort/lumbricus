module game.spriteactions;

///Contains actions that can be executed from event handlers in ActionSprite
///and that will (normally) add some sort of constant effect
///
///In contrast to WeaponActions, those cannot be run in an onfire event
///(note that it works the other way round)

import framework.framework;
import game.animation;
import physics.world;
import game.action;
import game.actionsprite;
import game.game;
import game.gobject;
import game.sprite;
import game.sequence;
import utils.misc;
import utils.vector2;
import utils.time;
import utils.configfile;
import utils.log;
import utils.random;
import utils.randval;
import utils.factory;

///Base class for constant sprite actions
class SpriteAction : TimedAction {
    protected {
        ActionSprite mParent;
    }

    this(SpriteActionClass base, GameEngine eng) {
        super(base, eng);
    }

    override protected ActionRes doImmediate() {
        super.doImmediate();
        mParent = context.getPar!(ActionSprite)("sprite");
        //obligatory parameters for SpriteAction
        assert(!!mParent);
        return ActionRes.moreWork;
    }
}

class SpriteActionClass : TimedActionClass {
    void loadFromConfig(GameEngine eng, ConfigNode node) {
        super.loadFromConfig(eng, node);
        if (!node.findValue("duration"))
            durationMs = RandomInt(1237899900);
    }
}

//------------------------------------------------------------------------

class SetStateAction : SpriteAction {
    private {
        SetStateActionClass myclass;
    }

    this(SetStateActionClass base, GameEngine eng) {
        super(base, eng);
        myclass = base;
    }

    protected ActionRes initDeferred() {
        auto ssi = mParent.type.findState(myclass.state);
        if (ssi)
            mParent.setState(ssi);
        return ActionRes.done;
    }
}

class SetStateActionClass : SpriteActionClass {
    char[] state;

    void loadFromConfig(GameEngine eng, ConfigNode node) {
        super.loadFromConfig(eng, node);
        state = node.getStringValue("state","");
    }

    SetStateAction createInstance(GameEngine eng) {
        return new SetStateAction(this, eng);
    }

    static this() {
        ActionClassFactory.register!(typeof(this))("state");
    }
}

//------------------------------------------------------------------------

class GravityCenterAction : SpriteAction {
    private {
        GravityCenterActionClass myclass;
        GravityCenter mGravForce;
    }

    this(GravityCenterActionClass base, GameEngine eng) {
        super(base, eng);
        myclass = base;
    }

    protected ActionRes initDeferred() {
        mGravForce = new GravityCenter();
        mGravForce.accel = myclass.gravity;
        mGravForce.radius = myclass.radius;
        mGravForce.pos = mParent.physics.pos;
        engine.physicworld.add(mGravForce);
        return ActionRes.moreWork;
    }

    protected void cleanupDeferred() {
        mGravForce.dead = true;
    }

    override void simulate(float deltaT) {
        super.simulate(deltaT);
        mGravForce.pos = mParent.physics.pos;
    }
}

class GravityCenterActionClass : SpriteActionClass {
    float gravity, radius;

    void loadFromConfig(GameEngine eng, ConfigNode node) {
        super.loadFromConfig(eng, node);
        gravity = node.getFloatValue("gravity",0);
        radius = node.getFloatValue("radius",100);
    }

    GravityCenterAction createInstance(GameEngine eng) {
        return new GravityCenterAction(this, eng);
    }

    static this() {
        ActionClassFactory.register!(typeof(this))("gravitycenter");
    }
}

//------------------------------------------------------------------------

class ProximitySensorAction : SpriteAction {
    private {
        ProximitySensorActionClass myclass;
        ZoneTrigger mTrigger;
        PhysicZoneCircle mZone;
        Time mFireTime;
    }

    this(ProximitySensorActionClass base, GameEngine eng) {
        super(base, eng);
        myclass = base;
    }

    protected ActionRes initDeferred() {
        mZone = new PhysicZoneCircle(mParent.physics.pos, myclass.radius);
        mTrigger = new ZoneTrigger(mZone);
        mTrigger.collision = engine.physicworld.collide.findCollisionID(
            myclass.collision);
        mTrigger.onTrigger = &trigTrigger;
        mFireTime = timeNever();
        engine.physicworld.add(mTrigger);
        return ActionRes.moreWork;
    }

    protected void cleanupDeferred() {
        mTrigger.dead = true;
    }

    private void trigTrigger(PhysicTrigger sender, PhysicObject other) {
        if (mFireTime == timeNever()) {
            mFireTime = engine.gameTime.current + myclass.triggerDelay;
        }
    }

    override protected bool customActivity() {
        return mFireTime != timeNever();
    }

    override void simulate(float deltaT) {
        super.simulate(deltaT);
        mZone.pos = mParent.physics.pos;
        if (engine.gameTime.current >= mFireTime) {
            //execute trigger event (which maybe blows the projectile)
            mParent.doEvent(myclass.eventId);
            //xxx implement multi-activation sensors
            done();
        }
    }
}

class ProximitySensorActionClass : SpriteActionClass {
    float radius;
    Time triggerDelay;   //time from triggering from firing
    char[] collision, eventId;

    void loadFromConfig(GameEngine eng, ConfigNode node) {
        super.loadFromConfig(eng, node);
        radius = node.getFloatValue("radius",20);
        triggerDelay = timeSecs(node.getFloatValue("trigger_delay",1.0f));
        collision = node.getStringValue("collision","proxsensor");
        eventId = node.getStringValue("event","ontrigger");
    }

     ProximitySensorAction createInstance(GameEngine eng) {
        return new ProximitySensorAction(this, eng);
    }

    static this() {
        ActionClassFactory.register!(typeof(this))("proximitysensor");
    }
}

//------------------------------------------------------------------------

//makes the parent projectile walk in looking direction
class WalkerAction : SpriteAction {
    private {
        WalkerActionClass myclass;
    }

    this(WalkerActionClass base, GameEngine eng) {
        super(base, eng);
        myclass = base;
    }

    protected ActionRes initDeferred() {
        Vector2f walk = Vector2f.fromPolar(1.0f, mParent.physics.lookey);
        walk.y = 0;
        walk = walk.normal;
        if (myclass.inverseDirection)
            walk.x = -walk.x;
        mParent.physics.setWalking(walk);
        return ActionRes.done;
    }
}

class WalkerActionClass : SpriteActionClass {
    bool inverseDirection = false;

    void loadFromConfig(GameEngine eng, ConfigNode node) {
        super.loadFromConfig(eng, node);
        inverseDirection = node.getBoolValue("inverse_direction",
            inverseDirection);
    }

    WalkerAction createInstance(GameEngine eng) {
        return new WalkerAction(this, eng);
    }

    static this() {
        ActionClassFactory.register!(typeof(this))("walker");
    }
}

//------------------------------------------------------------------------

//makes the parent projectile jump randomly when glued
class RandomJumpAction : SpriteAction {
    private {
        RandomJumpActionClass myclass;
    }

    this(RandomJumpActionClass base, GameEngine eng) {
        super(base, eng);
        myclass = base;
    }

    protected ActionRes initDeferred() {
        return ActionRes.moreWork;
    }

    override void simulate(float deltaT) {
        float p = myclass.jumpsPerSec * deltaT;
        if (engine.rnd.nextDouble2() < p && mParent.physics.isGlued) {
            doJump();
        }
    }

    private void doJump() {
        auto look = Vector2f.fromPolar(1, mParent.physics.lookey);
        look.y = 0;
        look = look.normal(); //get sign *g*
        look.y = 1;
        mParent.physics.addImpulse(look.mulEntries(myclass.jumpStrength));
    }
}

class RandomJumpActionClass : SpriteActionClass {
    Vector2f jumpStrength;
    float jumpsPerSec = 1.0f;   //probability of a jump, per second

    void loadFromConfig(GameEngine eng, ConfigNode node) {
        super.loadFromConfig(eng, node);
        float[] js = node.getValueArray!(float)("jump_strength",[100,-100]);
        jumpStrength = Vector2f(js[0],js[1]);
        jumpsPerSec = node.getFloatValue("jumps_per_sec",jumpsPerSec);
    }

    RandomJumpAction createInstance(GameEngine eng) {
        return new RandomJumpAction(this, eng);
    }

    static this() {
        ActionClassFactory.register!(typeof(this))("random_jump");
    }
}

//------------------------------------------------------------------------

//will trigger an event when the parent projectile is no longer moving
//(independant of gluing)
class StuckTriggerAction : SpriteAction {
    private {
        struct DeltaSample {
            Time t;
            float delta = 0;
        }

        StuckTriggerActionClass myclass;
        Vector2f mPosOld;
        DeltaSample[] mSamples;
        bool mActivated = false;
    }

    this(StuckTriggerActionClass base, GameEngine eng) {
        super(base, eng);
        myclass = base;
    }

    protected ActionRes initDeferred() {
        mPosOld = mParent.physics.pos;
        return ActionRes.moreWork;
    }

    protected void cleanupDeferred() {
    }

    //adds a position-change sample to the list (with timestamp)
    private void addSample(float delta) {
        Time t = engine.gameTime.current;
        foreach (ref s; mSamples) {
            if (t - s.t > myclass.triggerDelay) {
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
            if (t - s.t <= myclass.triggerDelay) {
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
        if (integrate() < myclass.treshold && mActivated) {
            //execute trigger event (which maybe blows the projectile)
            mParent.doEvent(myclass.eventId);
            if (myclass.multiple) {
                //reset
                mActivated = false;
                mSamples = null;
            } else {
                done();
            }
        }
    }
}

class StuckTriggerActionClass : SpriteActionClass {
    float radius;
    Time triggerDelay;   //time from triggering from firing
    float treshold = 5.0f;
    bool multiple = false;
    char[] collision, eventId;

    void loadFromConfig(GameEngine eng, ConfigNode node) {
        super.loadFromConfig(eng, node);
        triggerDelay = timeSecs(node.getFloatValue("trigger_delay",0.25f));
        treshold = node.getFloatValue("treshold",treshold);
        multiple = node.getBoolValue("multiple",multiple);
        eventId = node.getStringValue("event","ontrigger");
    }

    StuckTriggerAction createInstance(GameEngine eng) {
        return new StuckTriggerAction(this, eng);
    }

    static this() {
        ActionClassFactory.register!(typeof(this))("stucktrigger");
    }
}
