module game.weapon.projectile;

import framework.framework;
import physics.world;
import game.action.base;
import game.action.wcontext;
import game.actionsprite;
import game.game;
import game.gfxset;
import game.gobject;
import game.sprite;
import game.sequence;
import game.particles : ParticleType;
import game.weapon.weapon;
import gui.rendertext;
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
        FormattedText mTimeLabel;
    }

    Time detonateTimeState() {
        if (!currentState.useFixedDetonateTime)
            return stateTime + detonateTimer;
        else
            return stateTime + currentState.fixedDetonateTime;
    }

    override bool activity() {
        //most weapons are always "internal_active", so the exceptions have to
        //explicitely specify when they're actually "inactive"
        //this includes non-exploding mines
        return internal_active && !(physics.isGlued
            && currentState.inactiveWhenGlued);
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
        //conditions: 1s-5s, enabled in conf file and not using glue check
        if (detDelta < timeSecs(5) && detDelta > Time.Null && internal_active
            && currentState.showTimer && enableEvents
            && currentState.minimumGluedTime == Time.Null)
        {
            if (!mTimeLabel) {
                mTimeLabel = engine.gfx.textCreate();
                graphic.attachText = mTimeLabel;
            }
            int remain = cast(int)(detDelta.secsf + 0.99f);
            if (remain <= 2)
                mTimeLabel.setTextFmt(true, "\\c(team_red){}", remain);
            else
                mTimeLabel.setTextFmt(true, "{}", remain);
        } else {
            if (mTimeLabel) {
                //xxx: need cleaner way to remove attached text?
                if (graphic)
                    graphic.attachText = null;
                mTimeLabel = null;
            }
        }
    }

    override protected void updateInternalActive() {
        super.updateInternalActive();
        if (!internal_active && mTimeLabel) {
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
    this(char[] owner_name, char[] this_name) {
        super(owner_name, this_name);
    }

    override void loadFromConfig(ConfigNode sc, ConfigNode physNode,
        SpriteClass owner)
    {
        super.loadFromConfig(sc, physNode, owner);

        loadStuff(sc);
    }

    private void loadStuff(ConfigNode sc) {
        auto detonateNode = sc.getSubNode("detonate");
        minimumGluedTime = detonateNode.getValue("gluetime", minimumGluedTime);
        inactiveWhenGlued = sc.getBoolValue("inactive_when_glued");
        fixedDetonateTime = detonateNode.getValue("lifetime",
            fixedDetonateTime);
        useFixedDetonateTime = fixedDetonateTime != Time.Infinite;
        showTimer = sc.getBoolValue("show_timer");
    }
}

//can load weapon config from configfile, see weapons.conf; it's a projectile
class ProjectileSpriteClass : ActionSpriteClass {
    override ProjectileSprite createSprite(GameEngine engine) {
        return new ProjectileSprite(engine, this);
    }

    //config = a subnode in the weapons.conf which describes a single projectile
    override void loadFromConfig(ConfigNode config) {
        super.loadFromConfig(config);
        bool stateful = config.getBoolValue("stateful", false);
        if (!stateful) {
            //hm, state stuff unused, so only that state
            initState.physic_properties = new POSP();
            initState.physic_properties.loadFromConfig(config.getSubNode("physics"));

            if (auto drownani = findSequenceState("drown", true)) {
                auto drownstate = createStateInfo("drowning");
                drownstate.animation = drownani;
                //no events underwater
                drownstate.disableEvents = true;
                drownstate.physic_properties = initState.physic_properties;
                //must not modify physic_properties (instead copy them)
                drownstate.physic_properties = drownstate.physic_properties.copy();
                drownstate.physic_properties.radius = 1;
                drownstate.physic_properties.collisionID = "waterobj";
                drownstate.particle = gfx.resources
                    .get!(ParticleType)("p_projectiledrown");
                states[drownstate.name] = drownstate;

                //when sprite in defaultstate goes underwater
                initState.onDrown = drownstate;
                //and this because waterStateChange() is called too often
                //should be fixed in sprite.d
                drownstate.onDrown = drownstate;
            }

            castStrict!(ProjectileStateInfo)(initState).loadStuff(config);

            //duplicated from sprite.d
            //having different loading code was the worst idea ever
            auto particlename = config["particle"];
            if (particlename.length) {
                //isn't this funny
                initState.particle = gfx.resources
                    .get!(ParticleType)(particlename);
            }
        }  //if stateful
    }


    override protected ProjectileStateInfo createStateInfo(char[] a_name) {
        return new ProjectileStateInfo(name, a_name);
    }

    this(GfxSet e, char[] r) {
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
        SpriteClassFactory.register!(typeof(this))("sprite_mc");
    }
}
