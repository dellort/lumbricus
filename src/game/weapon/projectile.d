module game.weapon.projectile;

import framework.framework;
import physics.world;
import game.action.base;
import game.action.wcontext;
import game.actionsprite;
import game.game;
import game.gobject;
import game.sprite;
import game.sequence;
import game.gamepublic;
import game.particles : ParticleType;
import game.weapon.weapon;
import tango.math.Math;
import tango.util.Convert : to;
import utils.misc;
import utils.vector2;
import utils.time;
import utils.configfile;
import utils.log;
import utils.random;
import utils.factory;
import utils.reflection;
import utils.mybox;

interface ProjectileFeedback {
    void addRefire(ProjectileSprite s);

    void removeRefire(ProjectileSprite s);
}

class ProjectileSprite : ActionSprite {
    ProjectileSpriteClass myclass;
    //only used if myclass.dieByTime && !myclass.useFixedDeathTime
    Time detonateTimer;
    WeaponTarget target;

    private {
        Time stateTime;
        Time glueTime;   //time when projectile got glued
        bool gluedCache; //last value of physics.isGlued
        bool mTimerDone = false;
        ProjectileFeedback mFeedback;
        TextGraphic mTimeLabel;
    }

    Time detonateTimeState() {
        if (!currentState.useFixedDetonateTime)
            return stateTime + detonateTimer;
        else
            return stateTime + currentState.fixedDetonateTime;
    }

    override bool activity() {
        //most weapons are always "active", so the exceptions have to
        //explicitely specify when they're actually "inactive"
        //this includes non-exploding mines
        return active && !(physics.isGlued && currentState.inactiveWhenGlued);
    }

    override ProjectileStateInfo currentState() {
        return cast(ProjectileStateInfo)super.currentState();
    }

    override protected void stateTransition(StaticStateInfo from,
        StaticStateInfo to)
    {
        super.stateTransition(from, to);
        stateTime = engine.gameTime.current;
        mTimerDone = false;
        if (!enableEvents) {
            //if entering a no-events state, remove this class from refire list
            //xxx readding later not possible because shooter might have died
            //    by then
            if (mFeedback && type.canRefire)
                mFeedback.removeRefire(this);
        }
    }

    void setFeedback(ProjectileFeedback tr) {
        mFeedback = tr;
        if (tr && type.canRefire)
            tr.addRefire(this);
    }

    override void simulate(float deltaT) {
        super.simulate(deltaT);

        Time detDelta = detonateTimeState - engine.gameTime.current;
        if (detDelta < Time.Null) {
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
            if (engine.gameTime.current - glueTime >=
                currentState.minimumGluedTime)
            {
                if (!mTimerDone) {
                    mTimerDone = true;
                    doEvent("ontimer");
                }
            }
        }
        //show timer label when about to blow in <5s
        //lol, lots of conditions
        if (detDelta < timeSecs(5) && active && currentState.showTimer
            && enableEvents && currentState.minimumGluedTime == Time.Null)
        {
            if (!mTimeLabel) {
                mTimeLabel = new TextGraphic();
                mTimeLabel.attach = Vector2f(0.5f, 1.0f);
                engine.graphics.add(mTimeLabel);
            }
            mTimeLabel.pos = toVector2i(physics.pos) - Vector2i(0, 15);
            int remain = cast(int)(detDelta.secsf + 1.0f);
            //xxx: prevent allocating memory every frame
            if (remain <= 2)
                mTimeLabel.msgMarkup = "\\c(team_red)" ~ to!(char[])(remain);
            else
                mTimeLabel.msgMarkup = to!(char[])(remain);
        } else {
            if (mTimeLabel) {
                mTimeLabel.remove();
                mTimeLabel = null;
            }
        }
    }

    override protected void updateActive() {
        super.updateActive();
        if (!active && mTimeLabel) {
            mTimeLabel.remove();
            mTimeLabel = null;
        }
    }

    override protected void physImpact(PhysicBase other, Vector2f normal) {
        super.physImpact(other, normal);
    }

    //fill the FireInfo struct with current data
    override protected void updateFireInfo() {
        super.updateFireInfo();
        mFireInfo.info.pointto = target;   //keep target for spawned projectiles
    }

    override protected void die() {
        //remove from shooter's refire list
        if (mFeedback && type.canRefire)
            mFeedback.removeRefire(this);
        //actually die (byebye)
        super.die();
    }

    override WeaponContext createContext() {
        auto ctx = super.createContext();
        ctx.feedback = mFeedback;
        return ctx;
    }

    this(GameEngine engine, ProjectileSpriteClass type) {
        super(engine, type);

        assert(type !is null);
        myclass = type;
        assert(myclass !is null);
        stateTime = engine.gameTime.current;
    }

    this (ReflectCtor c) {
        super(c);
    }
}

class ProjectileStateInfo : ActionStateInfo {
    //r/o fields
    bool useFixedDetonateTime;
    //when glued, consider it as inactive (so next turn can start); i.e. mines
    bool inactiveWhenGlued;
    Time fixedDetonateTime = Time.Never;
    Time minimumGluedTime = timeSecs(0);
    bool showTimer;

    //xxx class
    this (ReflectCtor c) {
        super(c);
    }
    this () {
    }

    override void loadFromConfig(ConfigNode sc, ConfigNode physNode,
        GOSpriteClass owner)
    {
        super.loadFromConfig(sc, physNode, owner);

        loadDetonateConfig(sc);
    }

    private void loadDetonateConfig(ConfigNode sc) {
        auto detonateNode = sc.getSubNode("detonate");
        minimumGluedTime = detonateNode.getValue("gluetime", minimumGluedTime);
        inactiveWhenGlued = sc.getBoolValue("inactive_when_glued");
        fixedDetonateTime = detonateNode.getValue("lifetime",
            fixedDetonateTime);
        useFixedDetonateTime = fixedDetonateTime != Time.Infinite;
        showTimer = sc.getBoolValue("show_timer");
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
    override ProjectileSprite createSprite() {
        return new ProjectileSprite(engine, this);
    }

    //config = a subnode in the weapons.conf which describes a single projectile
    override void loadFromConfig(ConfigNode config) {
        bool stateful = config.getBoolValue("stateful", false);
        if (stateful)
            //treat like a normal sprite
            super.loadFromConfig(config);
        else {
            //missing super call is intended
            asLoadFromConfig(config);

            //hm, state stuff unused, so only that state
            initState.physic_properties = new POSP();
            initState.physic_properties.loadFromConfig(config.getSubNode("physics"));

            if (config.hasValue("sequence_object")) {
                //sequenceObject = engine.gfx.resources.resource!(SequenceObject)
                //    (config["sequence_object"]).get;
                sequencePrefix = config["sequence_object"];
                assert(sequencePrefix.length > 0, "bla: "~config.name);
                initState.animation = findSequenceState("normal");
            }

            if (auto drownani = findSequenceState("drown", true)) {
                auto drownstate = createStateInfo();
                drownstate.name = "drowning";
                drownstate.animation = drownani;
                //no events underwater
                drownstate.disableEvents = true;
                drownstate.physic_properties = initState.physic_properties;
                //must not modify physic_properties (instead copy them)
                drownstate.physic_properties = drownstate.physic_properties.copy();
                drownstate.physic_properties.radius = 1;
                drownstate.physic_properties.collisionID = "waterobj";
                drownstate.particle = engine.gfx.resources
                    .get!(ParticleType)("p_projectiledrown");
                states[drownstate.name] = drownstate;
            }

            (cast(ProjectileStateInfo)initState).loadDetonateConfig(config);

            //duplicated from sprite.d
            //having different loading code was the worst idea ever
            auto particlename = config["particle"];
            if (particlename.length) {
                //isn't this funny
                initState.particle = engine.gfx.resources
                    .get!(ParticleType)(particlename);
            }

            foreach (s; states) {
                s.fixup(this);
            }
        }  //if stateful
    }


    override protected ProjectileStateInfo createStateInfo() {
        return new ProjectileStateInfo();
    }

    this(GameEngine e, char[] r) {
        super(e, r);
    }

    //xxx class
    this (ReflectCtor c) {
        super(c);
    }

    static this() {
        SpriteClassFactory.register!(typeof(this))("projectile_mc");
        //cyclic dependency error...
        SpriteClassFactory.register!(ActionSpriteClass)("actionsprite_mc");
    }
}
