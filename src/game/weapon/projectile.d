module game.weapon.projectile;

import framework.framework;
import game.animation;
import physics.world;
import game.action;
import game.game;
import game.gobject;
import game.sprite;
import game.sequence;
import game.weapon.weapon;
import game.weapon.actions;
import std.math;
import str = std.string;
import utils.misc;
import utils.vector2;
import utils.mylist;
import utils.time;
import utils.configfile;
import utils.log;
import utils.random;
import utils.factory;

private class ActionWeapon : WeaponClass {
    ActionClass onFire;

    this(GameEngine aengine, ConfigNode node) {
        super(aengine, node);
        onFire = actionFromConfig(aengine, node.getSubNode("onfire"));
        if (!onFire) {
            //xxx error handling...
            throw new Exception("Action-based weapon needs onfire action");
        }
    }

    ActionShooter createShooter(GObjectSprite go) {
        return new ActionShooter(this, go, mEngine);
    }

    static this() {
        WeaponClassFactory.register!(typeof(this))("action");
    }
}

//standard projectile shooter for projectiles which are started from the worm
//(as opposed to air strikes etc.)
private class ActionShooter : Shooter {
    private {
        ActionWeapon myclass;
        Action mFireAction;
    }
    protected FireInfo fireInfo;

    this(ActionWeapon base, GObjectSprite a_owner, GameEngine engine) {
        super(base, a_owner, engine);
        myclass = base;
    }

    bool activity() {
        return !!mFireAction;
    }

    void fireFinish(Action sender) {
        mFireAction = null;
    }

    protected MyBox fireReadParam(char[] id) {
        switch (id) {
            case "fireinfo":
                return MyBox.Box(&fireInfo);
            case "owner_game":
                return MyBox.Box!(GameObject)(owner);
            default:
                return MyBox();
        }
    }

    void fireRound(Action sender) {
        //if the outer fire action is a list, called every loop, else once
        //before firing
    }

    void fire(FireInfo info) {
        if (mFireAction) {
            //try to interrupt
            interruptFiring();
            //if still active: no.
            if (mFireAction)
                return;
        }

        fireInfo = info;
        fireInfo.pos = owner.physics.pos;
        fireInfo.shootbyRadius = owner.physics.posp.radius;
        //create firing action
        mFireAction = myclass.onFire.createInstance(engine);
        mFireAction.onFinish = &fireFinish;
        //set parameters and let action do the rest
        //parameter stuff is a big xxx

        //xxx this is hacky
        auto al = cast(ActionList)mFireAction;
        if (al) {
            al.onStartLoop = &fireRound;
        } else {
            //no list? so just one-time call when mFireAction is run
            mFireAction.onExecute = &fireRound;
        }

        auto ctx = new ActionContext(&fireReadParam);
        mFireAction.execute(ctx);

        //wut?
        /+
        //if it has an extra firing, let the owner update it
        //(cf. Worm.getAnimationForState())
        if (owner && weapon.animations[WeaponWormAnimations.Fire].defined) {
            owner.updateAnimation();
        }
        +/
    }

    override void interruptFiring() {
        mFireAction.abort();
    }
}

private class ProjectileSprite : GObjectSprite {
    ProjectileSpriteClass myclass;
    Time birthTime;
    //only used if myclass.dieByTime && !myclass.useFixedDeathTime
    Time detonateTimer;
    Time glueTime;   //time when projectile got glued
    bool gluedCache; //last value of physics.isGlued
    Vector2f target;
    private bool mTimerDone = false;
    private FireInfo mFireInfo;

    Time detonateTime() {
        if (!myclass.useFixedDetonateTime)
            return birthTime + detonateTimer;
        else
            return birthTime + myclass.fixedDetonateTime;
    }

    override bool activity() {
        //most weapons are always "active", so the exceptions have to
        //explicitely specify when they're actually "inactive"
        //this includes non-exploding mines
        return active && !(physics.isGlued && myclass.inactiveWhenGlued);
    }

    override void simulate(float deltaT) {
        super.simulate(deltaT);

        if (engine.gameTime.current > detonateTime) {
            //start glued checking when projectile wants to blow
            if (physics.isGlued) {
                if (!gluedCache) {
                    //projectile got glued
                    gluedCache = true;
                    glueTime = engine.gameTime.current;
                }
            } else {
                //projectile is not glued
                glueTime = engine.gameTime.current;
                gluedCache = false;
            }
            //this will do 0 >= 0 for projectiles not needing glue
            if (engine.gameTime.current - glueTime >= myclass.minimumGluedTime) {
                if (!mTimerDone) {
                    doEvent("ontimer");
                    mTimerDone = true;
                }
            }
        }
    }

    override protected void physImpact(PhysicBase other, Vector2f normal) {
        super.physImpact(other, normal);
    }

    //fill the FireInfo struct with current data
    private void updateFireInfo() {
        mFireInfo.dir = physics.velocity.normal;
        mFireInfo.strength = physics.velocity.length; //xxx confusing units :-)
        mFireInfo.pointto = target;   //keep target for spawned projectiles
        mFireInfo.pos = physics.pos;
        mFireInfo.shootbyRadius = physics.posp.radius;
        mFireInfo.surfNormal = mLastImpactNormal;
    }

    override protected void die() {
        //actually die (byebye)
        super.die();
    }

    protected MyBox readParam(char[] id) {
        switch (id) {
            case "fireinfo":
                //get current FireInfo data (physics)
                updateFireInfo();
                return MyBox.Box(&mFireInfo);
            default:
                return super.readParam(id);
        }
    }

    this(GameEngine engine, ProjectileSpriteClass type) {
        super(engine, type);

        assert(type !is null);
        myclass = type;
        assert(myclass !is null);
        birthTime = engine.gameTime.current;
    }
}

enum InitVelocity {
    parent,
    backfire,
    fixed,
}

//information about how to spawn something
//from the "onfire" or "death.spawn" config sections in weapons.conf
struct SpawnParams {
    char[] projectile;
    float spawndist = 2; //distance between shooter and new projectile
    int count = 1;       //number of projectiles to spawn
    int random = 0;      //angle in which to spread projectiles randomly
    bool airstrike;      //shoot from the air
    InitVelocity initVelocity;//how the initial projectile velocity is generated
    /*bool keepVelocity = true; //if true, use strength/dir from FireInfo
                              //else use values below
    bool backFire = false;  //spawn projectiles away from surface
                            //overrides  */
    Vector2f direction;  //intial moving direction, affects spawn point
    float strength = 0;  //initial moving speed into above direction

    bool loadFromConfig(ConfigNode config) {
        projectile = config.getStringValue("projectile", projectile);
        count = config.getIntValue("count", count);
        spawndist = config.getFloatValue("spawndist", spawndist);
        random = config.getIntValue("random", random);
        airstrike = config.getBoolValue("airstrike", airstrike);
        //keepVelocity = config.getBoolValue("keep_velocity", keepVelocity);
        char[] vel = config.getStringValue("initial_velocity", "parent");
        switch (vel) {
            case "backfire":
                initVelocity = InitVelocity.backfire;
                break;
            case "fixed":
                initVelocity = InitVelocity.fixed;
                break;
            default:
                initVelocity = InitVelocity.parent;
        }
        float[] dirv = config.getValueArray!(float)("direction", [0, -1]);
        direction = Vector2f(dirv[0], dirv[1]);
        strength = config.getFloatValue("strength_value", strength);
        return true;
    }
}

//when a new projectile "sprite" was created, init it in all necessary ways
// n = n-th projectile in a batch (0 <= n < params.count)
// params = see typeof(params)
// about = how it was thrown
// sprite = new projectile sprite, which will be initialized and set active now
// shootby = maybe need shooter position, size and velocity
// shootby_object = for tracking who-shot-which
void spawnsprite(GameEngine engine, int n, SpawnParams params,
    FireInfo about, GameObject shootbyObject)
{
    //assert(shootby !is null);
    assert(n >= 0 && n < params.count);

    GObjectSprite sprite = engine.createSprite(params.projectile);
    sprite.createdBy = shootbyObject;

    switch (params.initVelocity) {
        case InitVelocity.fixed:
            //use values from config file, not from FireInfo
            about.dir = params.direction;
            about.strength = params.strength;
            break;
        case InitVelocity.backfire:
            //use configured strength, but throw projectiles back along
            //surface normal
            about.dir = about.surfNormal;
            about.strength = params.strength;
            break;
        default:
            //use strength/direction from FireInfo
    }

    if (!params.airstrike) {
        //place it
        //1.5 is a fuzzy value to prevent that the objects are "too near"
        float dist = (about.shootbyRadius + sprite.physics.posp.radius) * 1.5f;
        dist += params.spawndist;

        if (params.random) {
            //random rotation angle for dir vector, in rads
            float theta = (engine.rnd.nextDouble()-0.5f)*params.random*PI/180.0f;
            about.dir = about.dir.rotated(theta);
        }

        sprite.setPos(about.pos + about.dir*dist);
    } else {
        Vector2f pos;
        float width = params.spawndist * (params.count-1);
        //center around pointed
        pos.x = about.pointto.x - width/2 + params.spawndist * n;
        pos.y = sprite.engine.level.airstrikeY;
        sprite.setPos(pos);
        //patch for below *g*, direct into gravity direction
        about.dir = Vector2f(0, 1);
    }

    //velocity of new object
    //xxx sry for that, changing the sprite factory didn't seem worth it
    sprite.physics.setInitialVelocity(about.dir*about.strength);

    //pass required parameters
    auto ps = cast(ProjectileSprite)sprite;
    if (ps) {
        ps.detonateTimer = about.timer;
        ps.target = about.pointto;
    }

    //set fire to it
    sprite.active = true;
}

//action classes for spawning stuff
//xxx move somewhere else
class SpawnActionClass : ActionClass {
    SpawnParams sparams;

    void loadFromConfig(GameEngine eng, ConfigNode node) {
        sparams.loadFromConfig(node);
    }

    SpawnAction createInstance(GameEngine eng) {
        return new SpawnAction(this, eng);
    }

    static this() {
        ActionClassFactory.register!(typeof(this))("spawn");
    }
}

class SpawnAction : WeaponAction {
    private {
        SpawnActionClass myclass;
    }

    this(SpawnActionClass base, GameEngine eng) {
        super(base, eng);
        myclass = base;
    }

    override protected ActionRes initialStep() {
        super.initialStep();
        if (!mFireInfo.pos.isNaN) {
            //delay is not used, use ActionList looping for this
            for (int n = 0; n < myclass.sparams.count; n++) {
                spawnsprite(engine, n, myclass.sparams, *mFireInfo, mShootbyObj);
            }
        }
        return ActionRes.done;
    }
}

//xxx:
//maybe the "old" state mechanism from GOSpriteClass should still be made
//available (but how...? currently not needed anyway)
//you also can decide not to need state at all... then create a sprite class
//without any states: derive from it both the spriteclass having the state
//mechanism (at least needed for worm.d) and the WeaponSpriteClass from it...

//can load weapon config from configfile, see weapons.conf; it's a projectile
class ProjectileSpriteClass : GOSpriteClass {
    //r/o fields
    bool useFixedDetonateTime;
    Time fixedDetonateTime;
    Time minimumGluedTime;

    //when glued, consider it as inactive (so next round can start); i.e. mines
    bool inactiveWhenGlued;

    override ProjectileSprite createSprite() {
        return new ProjectileSprite(engine, this);
    }

    //config = a subnode in the weapons.conf which describes a single projectile
    override void loadFromConfig(ConfigNode config) {
        //missing super call is intended
        actions.loadFromConfig(engine, config.getSubNode("actions"));

        //hm, state stuff unused, so only that state
        initState.physic_properties = new POSP();
        initState.physic_properties.loadFromConfig(config.getSubNode("physics"));

        if (!config.hasValue("sequence_object")) {
            assert(false, "bla: "~config.name);
        }

        sequenceObject = engine.gfx.resources.resource!(SequenceObject)
            (config["sequence_object"]).get;
        initState.animation = sequenceObject.findState("normal");

        if (auto drownani = sequenceObject.findState("drown", true)) {
            auto drownstate = new StaticStateInfo();
            drownstate.name = "drowning";
            drownstate.animation = drownani;
            drownstate.physic_properties = initState.physic_properties;
            //must not modify physic_properties (instead copy them)
            drownstate.physic_properties = drownstate.physic_properties.copy();
            drownstate.physic_properties.radius = 1;
            drownstate.physic_properties.collisionID = "projectile_drown";
            states[drownstate.name] = drownstate;
        }

        auto detonateNode = config.getSubNode("detonate");
        minimumGluedTime = timeSecs(detonateNode.getFloatValue("gluetime",
            0));
        if (detonateNode.valueIs("lifetime", "$LIFETIME$")) {
            useFixedDetonateTime = false;
        } else {
            useFixedDetonateTime = true;
            //currently in seconds, xxx what about default value?
            fixedDetonateTime =
                timeSecs(detonateNode.getFloatValue("lifetime", 3.0f));
        }
        foreach (char[] name, char[] value; detonateNode) {
            //xxx sry
            if (value == "true" && name != "ondetonate") {
                detonateMap[name] = true;
            }
        }

        inactiveWhenGlued = config.getBoolValue("inactive_when_glued");
    }


    this(GameEngine e, char[] r) {
        super(e, r);
        actions = new ActionContainer();
    }

    static this() {
        SpriteClassFactory.register!(typeof(this))("projectile_mc");
    }
}

//------------------------------------------------------------------------

///Base class for constant sprite actions
class SpriteAction : TimedAction {
    protected {
        GObjectSprite mParent;
    }

    this(SpriteActionClass base, GameEngine eng) {
        super(base, eng);
    }

    override protected ActionRes doImmediate() {
        super.doImmediate();
        mParent = context.getPar!(GObjectSprite)("sprite");
        //obligatory parameters for WeaponAction
        assert(!!mParent);
        return ActionRes.moreWork;
    }
}

class SpriteActionClass : TimedActionClass {
    void loadFromConfig(GameEngine eng, ConfigNode node) {
        super.loadFromConfig(eng, node);
        if (!node.findValue("duration"))
            duration = timeHours(12378999);
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

class HomingAction : SpriteAction {
    private {
        HomingActionClass myclass;
        Vector2f oldAccel;
        ObjectForce objForce;
        ConstantForce homingForce;
    }

    this(HomingActionClass base, GameEngine eng) {
        super(base, eng);
        myclass = base;
    }

    protected ActionRes initDeferred() {
        assert(!!(cast(ProjectileSprite)mParent),
            "Homing action only valid for projectiles");
        homingForce = new ConstantForce();
        objForce = new ObjectForce(homingForce, mParent.physics);
        //backup acceleration and set gravity override
        oldAccel = mParent.physics.acceleration;
        mParent.physics.acceleration = -engine.physicworld.gravity;
        engine.physicworld.add(objForce);
        return ActionRes.moreWork;
    }

    protected void cleanupDeferred() {
        mParent.physics.acceleration = oldAccel;
        objForce.dead = true;
    }

    override void simulate(float deltaT) {
        super.simulate(deltaT);
        Vector2f totarget = (cast(ProjectileSprite)mParent).target
            - mParent.physics.pos;
        Vector2f cmpAccel = totarget.project_vector(
            mParent.physics.velocity);
        Vector2f cmpTurn = totarget.project_vector(
            mParent.physics.velocity.orthogonal);
        float velFactor = 1.0f / (1.0f +
            mParent.physics.velocity.length * myclass.velocityInfluence);
        cmpTurn *= velFactor;
        totarget = cmpAccel + cmpTurn;
        //mParent.physics.addForce(totarget.normal*myclass.force);
        homingForce.force = totarget.normal*myclass.force;
    }
}

class HomingActionClass : SpriteActionClass {
    float force;
    float maxvelocity;
    float velocityInfluence = 0.001f;

    void loadFromConfig(GameEngine eng, ConfigNode node) {
        super.loadFromConfig(eng, node);
        force = node.getIntValue("force",100);
        maxvelocity = node.getIntValue("max_velocity",500);
        velocityInfluence = node.getFloatValue("velocity_influence", 0.001f);
    }

    HomingAction createInstance(GameEngine eng) {
        return new HomingAction(this, eng);
    }

    static this() {
        ActionClassFactory.register!(typeof(this))("homing");
    }
}

//------------------------------------------------------------------------

//HUGE xxx: Can't use ExplosionAction here because of parameter mismatch :(
//this does _exactly_ the same
class ExplodeAction : SpriteAction {
    private {
        ExplodeActionClass myclass;
    }

    this(ExplodeActionClass base, GameEngine eng) {
        super(base, eng);
        myclass = base;
    }

    protected ActionRes initDeferred() {
        engine.explosionAt(mParent.physics.pos, myclass.damage,
            mParent);
        return ActionRes.done;
    }
}

class ExplodeActionClass : SpriteActionClass {
    float damage;

    void loadFromConfig(GameEngine eng, ConfigNode node) {
        super.loadFromConfig(eng, node);
        damage = node.getIntValue("damage",50);
    }

     ExplodeAction createInstance(GameEngine eng) {
        return new ExplodeAction(this, eng);
    }

    static this() {
        ActionClassFactory.register!(typeof(this))("explosion_pr");
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
        mParent.physics.setWalking(walk);
        return ActionRes.done;
    }
}

class WalkerActionClass : SpriteActionClass {
    void loadFromConfig(GameEngine eng, ConfigNode node) {
        super.loadFromConfig(eng, node);
    }

     WalkerAction createInstance(GameEngine eng) {
        return new WalkerAction(this, eng);
    }

    static this() {
        ActionClassFactory.register!(typeof(this))("walker");
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
        foreach (ref s; mSamples) {
            if (t - s.t <= myclass.triggerDelay) {
                ret += s.delta;
            }
        }
        return ret;
    }

    override void simulate(float deltaT) {
        super.simulate(deltaT);
        Vector2f p = mParent.physics.pos;
        addSample((mPosOld-p).length);
        mPosOld = p;
        if (integrate() < myclass.treshold) {
            //execute trigger event (which maybe blows the projectile)
            mParent.doEvent(myclass.eventId);
            done();
        }
    }
}

class StuckTriggerActionClass : SpriteActionClass {
    float radius;
    Time triggerDelay;   //time from triggering from firing
    float treshold = 5.0f;
    char[] collision, eventId;

    void loadFromConfig(GameEngine eng, ConfigNode node) {
        super.loadFromConfig(eng, node);
        triggerDelay = timeSecs(node.getFloatValue("trigger_delay",0.25f));
        treshold = node.getFloatValue("treshold",treshold);
        eventId = node.getStringValue("event","ontrigger");
    }

    StuckTriggerAction createInstance(GameEngine eng) {
        return new StuckTriggerAction(this, eng);
    }

    static this() {
        ActionClassFactory.register!(typeof(this))("stucktrigger");
    }
}
