module game.action.spawn;

import game.action.base;
import game.action.wcontext;
import game.game;
import game.gobject;
import game.sprite;
import game.actionsprite;
import game.weapon.weapon;
import game.weapon.projectile;
import utils.configfile;
import utils.reflection;
import utils.vector2;
import utils.random;
import utils.randval;

import math = tango.math.Math;

enum InitVelocity {
    parent,
    backfire,
    fixed,
    randomAir,
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
    Vector2f direction ={0f, -1f};//intial moving direction, affects spawn point
    RandomFloat strength ={0f, 0f};  //initial moving speed into above direction
    char[] initState = "";  //override sprite initstate (careful with that)

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
            case "random_air":
                initVelocity = InitVelocity.randomAir;
                break;
            default:
                initVelocity = InitVelocity.parent;
        }
        direction = config.getValue("direction", direction);
        strength = config.getValue("strength_value", strength);
        initState = config.getStringValue("initstate", initState);
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
    FireInfo about, GameObject shootbyObject, ProjectileFeedback fb,
    bool doubleDamage)
{
    //assert(shootby !is null);
    assert(n >= 0 && n < params.count);

    GObjectSprite sprite = engine.createSprite(params.projectile);
    sprite.createdBy = shootbyObject;

    switch (params.initVelocity) {
        case InitVelocity.fixed:
            //use values from config file, not from FireInfo
            about.dir = params.direction;
            about.strength = params.strength.sample(engine.rnd);
            break;
        case InitVelocity.backfire:
            //use configured strength, but throw projectiles back along
            //surface normal
            about.dir = about.surfNormal;
            about.strength = params.strength.sample(engine.rnd);
            break;
        case InitVelocity.randomAir:
            about.strength = params.strength.sample(engine.rnd);
            //about.dir is unused
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
            float theta = (engine.rnd.nextDouble()-0.5f)*params.random
                *math.PI/180.0f;
            about.dir = about.dir.rotated(theta);
        }

        sprite.setPos(about.pos + about.dir*dist);
    } else {
        if (params.initVelocity == InitVelocity.randomAir) {
            //random positions over the whole landscape, random speed
            //  in approx. "down" direction
            Vector2f pos;
            pos.x = engine.level.landBounds.p1.x
                + engine.level.landBounds.size.x * engine.rnd.nextDouble();
            pos.y = 0;
            //Trace.formatln("{}", pos);
            sprite.setPos(pos);
            about.dir = Vector2f(engine.rnd.nextDouble3()*0.7f, 1).normal;
        } else {
            //classic airstrike in-a-row positioning, facing down
            Vector2f pos;
            float width = params.spawndist * (params.count-1);
            //center around pointed
            float x = about.pos.x;
            if (about.pointto.valid)
                x = about.pointto.currentPos.x;
            pos.x = x - width/2 + params.spawndist * n;
            pos.y = engine.level.airstrikeY;
            sprite.setPos(pos);
            //patch for below *g*, direct into gravity direction
            about.dir = Vector2f(0, 1);
        }
    }

    //velocity of new object
    //xxx sry for that, changing the sprite factory didn't seem worth it
    sprite.physics.setInitialVelocity(about.dir*about.strength);

    //pass required parameters
    if (auto ps = cast(ProjectileSprite)sprite) {
        ps.detonateTimer = about.timer;
        ps.target = about.pointto;
        ps.setFeedback(fb);
    }
    if (auto as = cast(ActionSprite)sprite) {
        as.doubleDamage = doubleDamage;
    }
    auto ssi = sprite.type.findState(params.initState, true);
    if (ssi)
        sprite.setStateForced(ssi);

    //set fire to it
    sprite.active = true;
}

//action classes for spawning stuff
//xxx move somewhere else
class SpawnActionClass : ActionClass {
    SpawnParams sparams;

    //xxx class
    this (ReflectCtor c) {
        super(c);
    }
    this (GameEngine eng, ConfigNode node) {
        sparams.loadFromConfig(node);
    }

    void execute(ActionContext ctx) {
        auto wx = cast(WeaponContext)ctx;
        if (!wx || wx.fireInfo.info.pos.isNaN)
            return;
        //use ActionList looping for delayed spawns
        for (int n = 0; n < sparams.count; n++) {
            spawnsprite(ctx.engine, n, sparams, wx.fireInfo.info,
                wx.createdBy, wx.feedback, wx.doubleDamage());
        }
    }

    static this() {
        ActionClassFactory.register!(typeof(this))("spawn");
    }
}
