module game.projectile;

import framework.framework;
import game.animation;
import physics.world;
import game.game;
import game.gobject;
import game.sprite;
import game.weapon;
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

private class ProjectileWeapon : WeaponClass {
    //GOSpriteClass[char[]] projectiles;
    SpawnParams onFire;
    //create projectiles in the air (according to point value)
    //(currently convenience only: only used for loading)
    bool isAirstrike;

    this(GameEngine aengine, ConfigNode node) {
        super(aengine, node);

        isAirstrike = node.getBoolValue("airstrike");
        if (isAirstrike) {
            onFire.airstrike = true;
            canPoint = true;
        }

        //load projectiles
        foreach (ConfigNode pr; node.getSubNode("projectiles")) {
            //if (pr.name in projectiles)
            //    throw new Exception("projectile already exists: "~pr.name);
            //instantiate a sprite class
            //xxx error handling?
            auto spriteclass = engine.instantiateSpriteClass(pr["type"], pr.name);
            //projectiles[pr.name] = spriteclass;

            //hm, state stuff unused, so only that state
            auto st = spriteclass.initState;

            st.physic_properties.loadFromConfig(pr.getSubNode("physics"));
            st.animation = engine.resources.resource!(Animation)
                (pr["animation"]);

            //allow non-ProjectileSpriteClass objects, why not
            auto pclass = cast(ProjectileSpriteClass)spriteclass;
            if (pclass) {
                pclass.loadProjectileStuff(pr);
            }
        }

        parseSpawn(onFire, node.getSubNode("onfire"));
    }

    ProjectileThrower createShooter(GObjectSprite go) {
        return new ProjectileThrower(this, go, mEngine);
    }

    static this() {
        WeaponClassFactory.register!(typeof(this))("projectile_mc");
    }
}

//standard projectile shooter for projectiles which are started from the worm
//(as opposed to air strikes etc.)
private class ProjectileThrower : Shooter {
    ProjectileWeapon pweapon;
    SpawnParams spawnParams;
    int spawnCount;      //how many projectiles still to shoot
    Time lastSpawn;
    FireInfo fireInfo;

    this(ProjectileWeapon base, GObjectSprite a_owner, GameEngine engine) {
        super(base, a_owner, engine);
        pweapon = base;
    }

    override void simulate(float deltaT) {
        super.simulate(deltaT);

        //care about spawning!
        while (spawnCount > 0
            && engine.gameTime.current - lastSpawn >= spawnParams.delay)
        {
            spawnCount--;
            lastSpawn = engine.gameTime.current;

            auto n = spawnParams.count - (spawnCount + 1); //rgh
            spawnsprite(engine, n, spawnParams, fireInfo, owner.physics, owner);
        }
        if (spawnCount == 0) {
            active = false;
        }
    }

    bool activity() {
        return active; //rly?
    }

    void fire(FireInfo info) {
        if (active) {
            //try to interrupt
            interruptFiring();
            //if still active: no.
            if (active)
                return;
        }

        fireInfo = info;
        spawnParams = pweapon.onFire;
        spawnCount = spawnParams.count;
        //set lastSpawn? doesn't seem to be needed
        //make active, so projectiles will be shot
        active = true;

        //if it has an extra firing, let the owner update it
        //(cf. Worm.getAnimationForState())
        if (owner && weapon.animations[WeaponWormAnimations.Fire].defined) {
            owner.updateAnimation();
        }
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
    ProjectileEffector[] effectors;
    Vector2f target;

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

        foreach (eff; effectors) {
            eff.simulate(deltaT);
        }

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

    override protected void physImpact(PhysicBase other) {
        super.physImpact(other);

        if (myclass.detonateByImpact > 0) {
            detonate(DetonateReason.impact);
        }
        if (myclass.explosionOnImpact > 0) {
            engine.explosionAt(physics.pos, myclass.explosionOnImpact, this);
        }
    }

    //called when projectile goes off
    protected void detonate(DetonateReason reason) {
        //various actions possible when blowing up
        //spawning
        if (myclass.spawnOnDetonate &&
            (!myclass.spawnLimitReason || reason == myclass.spawnRequire))
        {
            FireInfo info;
            //whatever seems useful...
            info.dir = physics.velocity.normal;
            info.strength = physics.velocity.length; //xxx confusing units :-)
            info.pointto = target;   //keep target for spawned projectiles

            //xxx: if you want the spawn-delay to be considered, there'd be two
            // ways: create a GameObject which does this (or do it in
            // this.simulate), or use the Shooter class
            for (int n = 0; n < myclass.spawnOnDetonate.count; n++) {
                spawnsprite(engine, n, *myclass.spawnOnDetonate, info, physics,
                    this);
            }
        }
        //an explosion
        if (myclass.explosionOnDeath > 0) {
            engine.explosionAt(physics.pos, myclass.explosionOnDeath, this);
        }

        //effects are removed by die()
        die();
    }

    override protected void die() {
        //remove constant effects
        foreach (eff; effectors) {
            eff.die();
        }

        //actually die (byebye)
        super.die();
    }

    this(GameEngine engine, ProjectileSpriteClass type) {
        super(engine, type);

        assert(type !is null);
        myclass = type;
        assert(myclass !is null);
        birthTime = engine.gameTime.current;

        foreach (effcls; myclass.effects) {
            auto peff = effcls.createEffector(this);
            peff.birthTime = birthTime;
            effectors ~= peff;
        }
    }
}

//information about how to spawn something
//from the "onfire" or "death.spawn" config sections in weapons.conf
struct SpawnParams {
    char[] projectile;
    float spawndist = 2; //distance between shooter and new projectile
    int count = 1;       //number of projectiles to spawn
    Time delay;          //delay between spawns
    int random = 0;      //angle in which to spread projectiles randomly
    bool airstrike;      //shoot from the air
    bool keepVelocity = true; //if true, use strength/dir from FireInfo
                              //else use values below
    Vector2f direction;  //intial moving direction, affects spawn point
    float strength = 0;  //initial moving speed into above direction
}

bool parseSpawn(inout SpawnParams params, ConfigNode config) {
    params.projectile = config.getStringValue("projectile", params.projectile);
    params.count = config.getIntValue("count", params.count);
    params.spawndist = config.getFloatValue("spawndist", params.spawndist);
    params.delay = timeSecs(config.getIntValue("delay", params.delay.secs));
    params.random = config.getIntValue("random", params.random);
    params.airstrike = config.getBoolValue("airstrike", params.airstrike);
    params.keepVelocity = config.getBoolValue("keep_velocity",
        params.keepVelocity);
    float[] dirv = config.getValueArray!(float)("direction", [0, -1]);
    params.direction = Vector2f(dirv[0], dirv[1]);
    params.strength = config.getFloatValue("strength_value", params.strength);
    return true;
}

//when a new projectile "sprite" was created, init it in all necessary ways
// n = n-th projectile in a batch (0 <= n < params.count)
// params = see typeof(params)
// about = how it was thrown
// sprite = new projectile sprite, which will be initialized and set active now
// shootby = maybe need shooter position, size and velocity
// shootby_object = for tracking who-shot-which
private void spawnsprite(GameEngine engine, int n, SpawnParams params,
    FireInfo about, PhysicObject shootby, GameObject shootby_object)
{
    assert(shootby !is null);
    assert(n >= 0 && n < params.count);

    GObjectSprite sprite = engine.createSprite(params.projectile);
    sprite.createdBy = shootby_object;

    if (!params.keepVelocity) {
        //don't use strength/direction from FireInfo
        about.dir = params.direction;
        about.strength = params.strength;
    }

    if (!params.airstrike) {
        //place it
        //1.5 is a fuzzy value to prevent that the objects are "too near"
        float dist = (shootby.posp.radius + sprite.physics.posp.radius) * 1.5f;
        dist += params.spawndist;

        if (params.random) {
            //random rotation angle for dir vector, in rads
            float theta = (genrand_real1()-0.5f)*params.random*PI/180.0f;
            about.dir = about.dir.rotated(theta);
        }

        sprite.setPos(shootby.pos + about.dir*dist);
    } else {
        Vector2f pos;
        float width = params.spawndist * (params.count-1);
        //center around pointed
        pos.x = about.pointto.x - width/2 + params.spawndist * n;
        pos.y = sprite.engine.skyline()+100;
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
    ProjectileEffectorClass[] effects;
    bool spawnLimitReason = false;
    DetonateReason spawnRequire;

    //nan for no explosion, else this is the damage strength
    float explosionOnDeath;
    float explosionOnImpact;

    override ProjectileSprite createSprite() {
        return new ProjectileSprite(engine, this);
    }

    //config = a subnode in the weapons.conf which describes a single projectile
    void loadProjectileStuff(ConfigNode config) {
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

        auto effectsNode = config.getSubNode("effects");
        foreach (ConfigNode n; effectsNode) {
            effects ~= ProjectileEffectorFactory.instantiate(n["name"],n);
        }

        auto spawn = config.getPath("detonate.spawn");
        if (spawn) {
            spawnOnDetonate = new SpawnParams;
            if (!parseSpawn(*spawnOnDetonate, spawn)) {
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
    }


    this(GameEngine e, char[] r) {
        super(e, r);
    }

    static this() {
        SpriteClassFactory.register!(typeof(this))("projectile_mc");
    }
}

//feature request for d0c: make effectors to be derived from GameObject
class ProjectileEffector {
    Time birthTime, startTime, delay;
    protected ProjectileSprite mParent;
    private ProjectileEffectorClass myclass;
    private bool mActive;

    //create effect
    this(ProjectileSprite parent, ProjectileEffectorClass type) {
        mParent = parent;
        myclass = type;
        birthTime = mParent.engine.gameTime.current;
        if (myclass.randomDelay)
            delay = timeMsecs(myclass.delay.msecs*genrand_real1());
        else
            delay = myclass.delay;
    }

    void active(bool ac) {
        if (ac != mActive) {
            activate(ac);
            mActive = ac;
        }
    }
    bool active() {
        return mActive;
    }

    Time dietime() {
        if (myclass.lifetime > timeMusecs(0)) {
            return birthTime + myclass.lifetime;
        } else {
            return timeNever();
        }
    }

    abstract void activate(bool ac);

    //do effect
    void simulate(float deltaT) {
        if (mParent.engine.gameTime.current - birthTime >= delay) {
            active = true;
            startTime = mParent.engine.gameTime.current + delay;
        }
        if (mParent.engine.gameTime.current > dietime) {
            die();
        }
    }

    //remove effect
    void die() {
        active = false;
    }
}

//feature request to d0c: make this derived from GameObject
//(would be good for having an .activity())
class ProjectileEffectorClass {
    Time lifetime, delay;
    bool randomDelay;

    this(ConfigNode node) {
        lifetime = timeSecs(node.getFloatValue("lifetime",0));
        delay = timeSecs(node.getFloatValue("delay",0.0f));
        randomDelay = node.getBoolValue("random_delay",false);
    }

    abstract ProjectileEffector createEffector(ProjectileSprite parent);
}

class ProjectileEffectorGravityCenter : ProjectileEffector {
    private ProjectileEffectorGravityCenterClass myclass;
    private GravityCenter mGravForce;

    this(ProjectileSprite parent, ProjectileEffectorGravityCenterClass type) {
        super(parent, type);
        myclass = type;
        mGravForce = new GravityCenter();
        mGravForce.accel = myclass.gravity;
        mGravForce.radius = myclass.radius;
        mGravForce.pos = mParent.physics.pos;
    }

    override void simulate(float deltaT) {
        super.simulate(deltaT);
        mGravForce.pos = mParent.physics.pos;
    }

    override void activate(bool ac) {
        if (ac) {
            mParent.engine.physicworld.add(mGravForce);
        } else {
            mGravForce.dead = true;
        }
    }
}

class ProjectileEffectorGravityCenterClass : ProjectileEffectorClass {
    float gravity, radius;

    this(ConfigNode node) {
        super(node);
        gravity = node.getFloatValue("gravity",0);
        radius = node.getFloatValue("radius",100);
    }

    override ProjectileEffectorGravityCenter createEffector(ProjectileSprite parent) {
        return new ProjectileEffectorGravityCenter(parent, this);
    }

    static this() {
        ProjectileEffectorFactory.register!(typeof(this))("gravitycenter");
    }
}

class ProjectileEffectorHoming : ProjectileEffector {
    private ProjectileEffectorHomingClass myclass;
    private Vector2f oldAccel;

    this(ProjectileSprite parent, ProjectileEffectorHomingClass type) {
        super(parent, type);
        myclass = type;
    }

    override void simulate(float deltaT) {
        super.simulate(deltaT);
        if (mActive) {
            Vector2f totarget = mParent.target - mParent.physics.pos;
            mParent.physics.addForce(totarget.normal*myclass.force);
        }
    }

    override void activate(bool ac) {
        if (ac) {
            //backup acceleration and set gravity override
            oldAccel = mParent.physics.acceleration;
            mParent.physics.acceleration = -mParent.engine.physicworld.gravity;
        } else {
            mParent.physics.acceleration = oldAccel;
        }
    }
}

class ProjectileEffectorHomingClass : ProjectileEffectorClass {
    float force;
    float maxvelocity;

    this(ConfigNode node) {
        super(node);
        force = node.getIntValue("force",100);
        maxvelocity = node.getIntValue("max_velocity",500);
    }

    override ProjectileEffectorHoming createEffector(ProjectileSprite parent) {
        return new ProjectileEffectorHoming(parent, this);
    }

    static this() {
        ProjectileEffectorFactory.register!(typeof(this))("homing");
    }
}

class ProjectileEffectorExplode : ProjectileEffector {
    private ProjectileEffectorExplodeClass myclass;
    private Time mLast;

    this(ProjectileSprite parent, ProjectileEffectorExplodeClass type) {
        super(parent, type);
        myclass = type;
    }

    override void simulate(float deltaT) {
        super.simulate(deltaT);
        if (mActive) {
            if (mParent.engine.gameTime.current - mLast > myclass.interval) {
                mLast += myclass.interval;
                mParent.engine.explosionAt(mParent.physics.pos, myclass.damage,
                    mParent);
            }
        }
    }

    override void activate(bool ac) {
        if (ac) {
            mLast = birthTime + delay - myclass.interval;
        } else {
        }
    }
}

class ProjectileEffectorExplodeClass : ProjectileEffectorClass {
    Time interval;
    float damage;

    this(ConfigNode node) {
        super(node);
        interval = timeSecs(node.getFloatValue("interval",1.0f));
        damage = node.getIntValue("damage",50);
    }

    override ProjectileEffectorExplode createEffector(ProjectileSprite parent) {
        return new ProjectileEffectorExplode(parent, this);
    }

    static this() {
        ProjectileEffectorFactory.register!(typeof(this))("explode");
    }
}

class ProjectileEffectorProximitySensor : ProjectileEffector {
    private ProjectileEffectorProximitySensorClass myclass;
    private CircularTrigger mTrigger;
    private Time mFireTime;

    this(ProjectileSprite parent, ProjectileEffectorProximitySensorClass type) {
        super(parent, type);
        myclass = type;
        mTrigger = new CircularTrigger(mParent.physics.pos, myclass.radius);
        mTrigger.collision = mParent.engine.physicworld.findCollisionID(
            myclass.collision, true);
        mTrigger.onTrigger = &trigTrigger;
        mFireTime = timeNever();
    }

    private void trigTrigger(PhysicTrigger sender, PhysicObject other) {
        if (mActive && mFireTime == timeNever()) {
            mFireTime = mParent.engine.gameTime.current + myclass.triggerDelay;
        }
    }

    override void simulate(float deltaT) {
        super.simulate(deltaT);
        mTrigger.pos = mParent.physics.pos;
        if (mActive) {
            if (mParent.engine.gameTime.current >= mFireTime) {
                //xxx implement different actions
                mParent.detonate(DetonateReason.sensor);
            }
        }
    }

    override void activate(bool ac) {
        if (ac) {
            mParent.engine.physicworld.add(mTrigger);
        } else {
            mTrigger.dead = true;
        }
    }
}

class ProjectileEffectorProximitySensorClass : ProjectileEffectorClass {
    float radius;
    Time triggerDelay;   //time from triggering from firing
    char[] collision;

    this(ConfigNode node) {
        super(node);
        radius = node.getFloatValue("radius",20);
        triggerDelay = timeSecs(node.getFloatValue("trigger_delay",1.0f));
        collision = node.getStringValue("collision","proxsensor");
    }

    override ProjectileEffectorProximitySensor createEffector(ProjectileSprite parent) {
        return new ProjectileEffectorProximitySensor(parent, this);
    }

    static this() {
        ProjectileEffectorFactory.register!(typeof(this))("proximitysensor");
    }
}

static class ProjectileEffectorFactory : StaticFactory!(
    ProjectileEffectorClass, ConfigNode) {
}
