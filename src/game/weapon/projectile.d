module game.weapon.projectile;

import framework.framework;
import game.animation;
import physics.world;
import game.action;
import game.actionsprite;
import game.game;
import game.gobject;
import game.sprite;
import game.sequence;
import game.spriteactions;
import game.weapon.weapon;
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

private class ProjectileSprite : ActionSprite {
    ProjectileSpriteClass myclass;
    Time birthTime;
    //only used if myclass.dieByTime && !myclass.useFixedDeathTime
    Time detonateTimer;
    Time glueTime;   //time when projectile got glued
    bool gluedCache; //last value of physics.isGlued
    Vector2f target;
    private bool mTimerDone = false;

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
    override protected void updateFireInfo() {
        super.updateFireInfo();
        mFireInfo.pointto = target;   //keep target for spawned projectiles
    }

    override protected void die() {
        //actually die (byebye)
        super.die();
    }

    protected MyBox readParam(char[] id) {
        switch (id) {
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

//xxx:
//maybe the "old" state mechanism from GOSpriteClass should still be made
//available (but how...? currently not needed anyway)
//you also can decide not to need state at all... then create a sprite class
//without any states: derive from it both the spriteclass having the state
//mechanism (at least needed for worm.d) and the WeaponSpriteClass from it...

//can load weapon config from configfile, see weapons.conf; it's a projectile
class ProjectileSpriteClass : ActionSpriteClass {
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
            auto drownstate = createStateInfo();
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
    }

    static this() {
        SpriteClassFactory.register!(typeof(this))("projectile_mc");
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
