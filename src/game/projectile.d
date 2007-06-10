module game.projectile;

import game.gobject;
import game.animation;
import game.common;
import game.physic;
import game.game;
import game.sprite;
import game.weapon;
import utils.misc;
import utils.vector2;
import utils.mylist;
import utils.time;
import utils.configfile;

private class ProjectileWeapon : WeaponClass {
    //GOSpriteClass[char[]] projectiles;
    SpawnParams onFire;

    this(GameEngine aengine, ConfigNode node) {
        super(aengine, node);

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

            loadPOSPFromConfig(pr.getSubNode("physics"), st.physic_properties);
            st.animation.loadFrom(engine, pr.getSubNode("animation"));

            //allow non-ProjectileSpriteClass objects, why not
            auto pclass = cast(ProjectileSpriteClass)spriteclass;
            if (pclass) {
                pclass.loadProjectileStuff(pr);
            }
        }

        parseSpawn(onFire, node.getSubNode("onfire"));
    }


    ProjectileThrower createShooter() {
        return new ProjectileThrower(this, mEngine);
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

    this(ProjectileWeapon base, GameEngine engine) {
        super(base, engine);
        pweapon = base;
    }

    override void simulate(float deltaT) {
        super.simulate(deltaT);

        //care about spawning!
        while (spawnCount > 0
            && engine.currentTime - lastSpawn > spawnParams.delay)
        {
            spawnCount--;
            lastSpawn = engine.currentTime;

            GObjectSprite sprite = engine.createSprite(spawnParams.projectile);
            auto n = spawnParams.count - (spawnCount + 1); //rgh
            spawnAdjustSprite(n, spawnParams, fireInfo, sprite);
        }
        if (spawnCount == 0) {
            active = false;
        }
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
    }
}

private class ProjectileSprite : GObjectSprite {
    ProjectileSpriteClass myclass;
    Time birthTime;
    //only used if mylcass.dieByTime && !myclass.useFixedDeathTime
    Time deathTimer;

    Time dieTime() {
        if (myclass.dieByTime) {
            if (!myclass.useFixedDieTime)
                return birthTime + deathTimer;
            else
                return birthTime + myclass.fixedDieTime;
        } else {
            return timeNever();
        }
    }

    override void simulate(float deltaT) {
        super.simulate(deltaT);

        if (engine.currentTime > dieTime) {
            die();
        }
    }

    override protected void physImpact(PhysicBase other) {
        super.physImpact(other);

        //Hint: in future, physImpact should deliver the collision cookie
        //(aka "action" in the config file)
        //then the banana bomb can decide if it expldoes or falls into the water
        if (myclass.dieByImpact) {
            die();
        }
    }

    override protected void die() {
        //various actions possible when dying
        //spawning
        if (myclass.spawnOnDeath) {
            FireInfo info;
            //whatever seems useful...
            info.dir = physics.velocity.normal;
            info.strength = 0;//physics.velocity.length; //xxx confusing units :-)
            info.shootby = physics;

            //xxx: if you want the spawn-delay to be considered, there'd be two
            // ways: create a GameObject which does this (or do it in
            // this.simulate), or use the Shooter class
            for (int n = 0; n < myclass.spawnOnDeath.count; n++) {
                GObjectSprite sprite =
                    engine.createSprite(myclass.spawnOnDeath.projectile);
                spawnAdjustSprite(n, *myclass.spawnOnDeath, info, sprite);
            }
        }
        //an explosion
        if (myclass.explosionOnDeath > 0) {
            engine.explosionAt(physics.pos, myclass.explosionOnDeath);
        }
        //actually die (byebye)
        super.die();
    }

    this(GameEngine engine, GOSpriteClass type) {
        super(engine, type);

        assert(type !is null);
        myclass = cast(typeof(myclass))type;
        assert(myclass !is null);
        birthTime = engine.currentTime;
    }
}

//guided missile and some other missile-like weapons
//not implemented, just there to set the target
abstract class TargetProjectileSprite : ProjectileSprite {
    Vector2f target;
    this(GameEngine engine, GOSpriteClass type) {
        super(engine, type);
    }
}

//information about how to spawn something
//from the "onfire" or "death.spawn" config sections in weapons.conf
struct SpawnParams {
    char[] projectile;
    float spawndist;  //distance between shooter and new projectile
    int count;        //number of projectiles to spawn
    Time delay;       //delay between spawns
    bool random;      //randomly place new projectiles
}

bool parseSpawn(inout SpawnParams params, ConfigNode config) {
    params.projectile = config.getStringValue("projectile");
    params.count = config.getIntValue("count", 1);
    params.spawndist = config.getFloatValue("spawndist", 1.0f);
    params.delay = timeSecs(config.getIntValue("delay", 0));
    params.random = config.getBoolValue("random", false);
    return true;
}

//when a new projectile "sprite" was created, init it in all necessary ways
// n = n-th projectile in a batch (0 <= n < params.count)
// params = see typeof(params)
// about = how it was thrown
// sprite = new projectile sprite, which will be initialized and set active now
private void spawnAdjustSprite(int n, SpawnParams params, FireInfo about,
    GObjectSprite sprite)
{
    assert(about.shootby !is null);
    assert(n >= 0 && n < params.count);

    //place it
    float dist = about.shootby.posp.radius + sprite.physics.posp.radius;
    dist += params.spawndist;

    if (!params.random) {
        sprite.setPos(about.shootby.pos + about.dir*dist);
    } else {
        sprite.setPos(about.shootby.pos+Vector2f(genrand_real1()*4-2,-2));
    }

    //velocity of new object
    sprite.physics.velocity = about.dir*about.strength;

    //pass required parameters
    auto ps = cast(ProjectileSprite)sprite;
    if (ps) {
        ps.deathTimer = about.timer;
    }
    auto tps = cast(TargetProjectileSprite)sprite;
    if (tps) {
        tps.target = about.pointto;
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
    bool dieByImpact;

    bool dieByTime;
    bool useFixedDieTime;
    Time fixedDieTime;

    //non-null if to spawn anything on death
    SpawnParams* spawnOnDeath;

    //0 for no explosion, else this is the damage strength
    float explosionOnDeath;

    override ProjectileSprite createSprite() {
        return new ProjectileSprite(engine, this);
    }

    //config = a subnode in the weapons.conf which describes a single projectile
    void loadProjectileStuff(ConfigNode config) {
        auto deathreason = config.getSubNode("death_howcome");
        dieByImpact = deathreason.getBoolValue("diebyimpact");
        dieByTime = deathreason.getBoolValue("diebytime");
        if (dieByTime) {
            if (deathreason.valueIs("lifetime", "$LIFETIME$")) {
                useFixedDieTime = false;
            } else {
                useFixedDieTime = true;
                //currently in seconds
                fixedDieTime = timeSecs(deathreason.getIntValue("lifetime"));
            }
        }
        auto spawn = config.getPath("death.spawn");
        if (spawn) {
            spawnOnDeath = new SpawnParams;
            if (!parseSpawn(*spawnOnDeath, spawn)) {
                spawnOnDeath = null;
            }
        }
        auto expl = config.getPath("death.explosion", true);
        explosionOnDeath = expl.getFloatValue("damage", 0);
    }


    this(GameEngine e, char[] r) {
        super(e, r);
    }
}

