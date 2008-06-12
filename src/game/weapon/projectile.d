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

    void fireReadParam(ActionParams* sender, char[] id) {
        //called before a parameter is read
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
        ActionParams p;
          p["fireinfo"] = &fireInfo;
          p["owner_game"] = &owner;
        p.onBeforeRead = &fireReadParam;

        //xxx this is hacky
        auto al = cast(ActionList)mFireAction;
        if (al) {
            al.onStartLoop = &fireRound;
        } else {
            //no list? so just one-time call when mFireAction is run
            mFireAction.onExecute = &fireRound;
        }

        mFireAction.execute(p);

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

private enum DetonateReason {
    unknown,
    impact,
    timeout,
    sensor,
}

private class ProjectileSprite : GObjectSprite {
    ProjectileSpriteClass myclass;
    Time birthTime;
    //only used if mylcass.dieByTime && !myclass.useFixedDeathTime
    Time detonateTimer;
    Time glueTime;   //time when projectile got glued
    bool gluedCache; //last value of physics.isGlued
    Vector2f target;
    private Action mCreateAction;

    Time detonateTime() {
        if (myclass.detonateByTime) {
            if (!myclass.useFixedDetonateTime)
                return birthTime + detonateTimer;
            else
                return birthTime + myclass.fixedDetonateTime;
        } else {
            return timeNever();
        }
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
                engine.mLog("detonate by time");
                detonate(DetonateReason.timeout);
            }
        }
    }

    override protected void physImpact(PhysicBase other, Vector2f normal) {
        super.physImpact(other, normal);

        if (myclass.detonateByImpact > 0) {
            detonate(DetonateReason.impact, normal);
        }
        if (myclass.explosionOnImpact > 0) {
            engine.explosionAt(physics.pos, myclass.explosionOnImpact, this);
        }
    }

    //called when projectile goes off
    protected void detonate(DetonateReason reason,
        Vector2f surfNormal = Vector2f(0, -1))
    {
        //various actions possible when blowing up
        //spawning
        if (myclass.spawnOnDetonate &&
            (!myclass.spawnLimitReason || reason == myclass.spawnRequire))
        {
            FireInfo info;
            //whatever seems useful...
            info.dir = physics.velocity.normal;
            info.surfNormal = surfNormal;
            info.strength = physics.velocity.length; //xxx confusing units :-)
            info.pointto = target;   //keep target for spawned projectiles
            info.pos = physics.pos;
            info.shootbyRadius = physics.posp.radius;

            //xxx: if you want the spawn-delay to be considered, there'd be two
            // ways: create a GameObject which does this (or do it in
            // this.simulate), or use the Shooter class
            for (int n = 0; n < myclass.spawnOnDetonate.count; n++) {
                spawnsprite(engine, n, *myclass.spawnOnDetonate, info, this);
            }
        }
        //an explosion
        if (myclass.explosionOnDeath > 0) {
            engine.explosionAt(physics.pos, myclass.explosionOnDeath, this);
        }
        if (myclass.bitmapOnDeath.defined()) {
            auto p = toVector2i(physics.pos);
            auto res = myclass.bitmapOnDeath;
            p -= res.get.size / 2;
            engine.insertIntoLandscape(p, res);
        }

        if (myclass.quakeOnDeathStrength > 0) {
            engine.addEarthQuake(myclass.quakeOnDeathStrength,
                myclass.quakeOnDeathDegrade);
        }

        //effects are removed by die()
        die();
    }

    void runAction(char[] id) {
        auto ac = myclass.actions.action(id);
        if (ac) {
            auto a = ac.createInstance(engine);
            //ActionParams p;
            //  p["fireinfo"] = &fireInfo;
            //  p["owner_game"] = &owner;
        }
    }

    override protected void die() {
        //remove constant effects
        if (mCreateAction)
            mCreateAction.abort();

        //actually die (byebye)
        super.die();
    }

    this(GameEngine engine, ProjectileSpriteClass type) {
        super(engine, type);

        assert(type !is null);
        myclass = type;
        assert(myclass !is null);
        birthTime = engine.gameTime.current;

        auto ac = myclass.actions.action("oncreate");
        if (ac) {
            mCreateAction = ac.createInstance(engine);
            ActionParams p;
              p["projectile"] = &this;
            mCreateAction.execute(p);
        }
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
    bool detonateByImpact;

    bool detonateByTime;
    bool useFixedDetonateTime;
    Time fixedDetonateTime;
    Time minimumGluedTime;

    //when glued, consider it as inactive (so next round can start); i.e. mines
    bool inactiveWhenGlued;

    //non-null if to spawn anything on death
    SpawnParams* spawnOnDetonate;
    bool spawnLimitReason = false;
    DetonateReason spawnRequire;

    //nan for no explosion, else this is the damage strength
    float explosionOnDeath;
    float explosionOnImpact;

    Resource!(Surface) bitmapOnDeath;

    //nan if none
    float quakeOnDeathStrength;
    float quakeOnDeathDegrade;

    ActionContainer actions;

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
            drownstate.physic_properties.mediumViscosity = 5;
            drownstate.physic_properties.radius = 1;
            drownstate.physic_properties.collisionID = "projectile_drown";
            states[drownstate.name] = drownstate;
        }

        auto detonatereason = config.getSubNode("detonate_howcome");
        detonateByImpact = detonatereason.getBoolValue("byimpact");
        detonateByTime = detonatereason.getBoolValue("bytime");
        minimumGluedTime = timeSecs(detonatereason.getFloatValue("gluetime",
            0));
        if (detonateByTime) {
            if (detonatereason.valueIs("lifetime", "$LIFETIME$")) {
                useFixedDetonateTime = false;
            } else {
                useFixedDetonateTime = true;
                //currently in seconds
                fixedDetonateTime =
                    timeSecs(detonatereason.getFloatValue("lifetime"));
            }
        }

        inactiveWhenGlued = config.getBoolValue("inactive_when_glued");

        auto spawn = config.getPath("detonate.spawn");
        if (spawn) {
            spawnOnDetonate = new SpawnParams;
            if (!spawnOnDetonate.loadFromConfig(spawn)) {
                spawnOnDetonate = null;
            }
            char[] sp = spawn.getStringValue("require_reason");
            spawnLimitReason = true;
            switch (sp) {
                case "unknown":
                    spawnRequire = DetonateReason.unknown;
                    break;
                case "impact":
                    spawnRequire = DetonateReason.impact;
                    break;
                case "timeout":
                    spawnRequire = DetonateReason.timeout;
                    break;
                case "sensor":
                    spawnRequire = DetonateReason.sensor;
                    break;
                default:
                    spawnLimitReason = false;
                    break;
            }
        }
        auto expl = config.getPath("detonate.explosion", true);
        explosionOnDeath = expl.getFloatValue("damage", float.nan);
        explosionOnImpact = config.getFloatValue("explosion_on_impact", float.nan);

        if (auto bitmap = config.getPath("detonate.bitmap")) {
            bitmapOnDeath = engine.gfx.resources
                .resource!(Surface)(bitmap["source"]);
        }

        if (auto quake = config.getPath("detonate.earthquake")) {
            quakeOnDeathStrength = quake.getFloatValue("strength");
            quakeOnDeathDegrade = quake.getFloatValue("degrade");
        }
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

///Base class for constant projectile actions
class ProjectileAction : TimedAction {
    protected {
        ProjectileSprite mParent;
    }

    this(TimedActionClass base, GameEngine eng) {
        super(base, eng);
    }

    override protected ActionRes doImmediate() {
        super.doImmediate();
        mParent = *params.getPar!(ProjectileSprite)("projectile");
        //obligatory parameters for WeaponAction
        assert(!!mParent);
        return ActionRes.moreWork;
    }
}

class ProjectileActionClass : TimedActionClass {
    void loadFromConfig(GameEngine eng, ConfigNode node) {
        super.loadFromConfig(eng, node);
        if (!node.findValue("duration"))
            duration = timeNever();
    }
}

//------------------------------------------------------------------------

class GravityCenterAction : ProjectileAction {
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

class GravityCenterActionClass : ProjectileActionClass {
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

class HomingAction : ProjectileAction {
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
        homingForce = new ConstantForce();
        objForce = new ObjectForce();
        objForce.target = mParent.physics;
        objForce.force = homingForce;
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
        Vector2f totarget = mParent.target - mParent.physics.pos;
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

class HomingActionClass : ProjectileActionClass {
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
class ExplodeAction : ProjectileAction {
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

class ExplodeActionClass : TimedActionClass {
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

class ProximitySensorAction : ProjectileAction {
    private {
        ProximitySensorActionClass myclass;
        CircularTrigger mTrigger;
        Time mFireTime;
    }

    this(ProximitySensorActionClass base, GameEngine eng) {
        super(base, eng);
        myclass = base;
    }

    protected ActionRes initDeferred() {
        assert(mParent !is null);
        assert(mParent !is null);
        assert(mParent.physics !is null);
        assert(myclass !is null);
        assert(engine !is null);
        mTrigger = new CircularTrigger(mParent.physics.pos, myclass.radius);
        mTrigger.collision = engine.physicworld.findCollisionID(
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

    override void simulate(float deltaT) {
        super.simulate(deltaT);
        mTrigger.pos = mParent.physics.pos;
        if (engine.gameTime.current >= mFireTime) {
            //xxx implement different actions
            mParent.detonate(DetonateReason.sensor);
        }
    }
}

class ProximitySensorActionClass : ProjectileActionClass {
    float radius;
    Time triggerDelay;   //time from triggering from firing
    char[] collision;

    void loadFromConfig(GameEngine eng, ConfigNode node) {
        super.loadFromConfig(eng, node);
        radius = node.getFloatValue("radius",20);
        triggerDelay = timeSecs(node.getFloatValue("trigger_delay",1.0f));
        collision = node.getStringValue("collision","proxsensor");
    }

     ProximitySensorAction createInstance(GameEngine eng) {
        return new ProximitySensorAction(this, eng);
    }

    static this() {
        ActionClassFactory.register!(typeof(this))("proximitysensor");
    }
}
