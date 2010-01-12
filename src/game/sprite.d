module game.sprite;

import framework.framework;
import game.events;
import game.game;
import game.gobject;
import game.sequence;
import game.temp : GameZOrder;
import game.gfxset;
import game.particles;
import net.marshal : Hasher;
import physics.world;

//temporary?
import game.controller_events;

import utils.vector2;
import utils.rect2;
import utils.configfile;
import utils.misc;
import utils.log;
import utils.math;
import tango.math.Math : abs, PI;
import utils.factory;
import utils.time;
import utils.mybox;
import utils.reflection;

private LogStruct!("game.sprite") log;

//factory to instantiate sprite classes, this is a small wtf
alias StaticFactory!("Sprites", SpriteClass, GfxSet, char[])
    SpriteClassFactory;

//version = RotateDebug;

class BasicSprite : GameObject {
    private {
        BasicSpriteClass type;
        //transient for savegames, Particle created from StaticStateInfo.particle
        //all state associated with this variable is non-deterministic and must not
        //  have any influence on the rest of the game state
        //xxx: move to Sequence, as soon as this is being rewritten
        ParticleEmitter mParticleEmitter;
        ParticleType mCurrentParticle;

        bool mIsUnderWater, mWaterUpdated;
        bool mWasActivated;
        bool mOldGlueState;

        Events mEvents;
    }

    PhysicObject physics;
    //attention: can be null if object inactive
    //if it gets active again it's recreated again LOL
    Sequence graphic;

    //hack for worm.d
    bool died_in_deathzone;

    mixin Methods!("physDie", "physDamage");

    this(GameEngine a_engine, BasicSpriteClass a_type) {
        super(a_engine, a_type.name);
        type = a_type;

        physics = new PhysicObject();
        physics.backlink = this;
        physics.lifepower = type.initialHp;

        engine.physicworld.add(physics);

        physics.onDie = &physDie;
        physics.onDamage = &physDamage;
    }

    this (ReflectCtor c) {
        super(c);
        c.transient(this, &mParticleEmitter);
    }

    final override Events classLocalEvents() {
        //mEvents is cached, because events are raised often, and getEvents
        //  does a relatively slow AA lookup
        if (!mEvents) {
            mEvents = type.getEvents(engine);
        }
        return mEvents;
    }

    void activate(Vector2f pos) {
        if (physics.dead || mWasActivated)
            return;
        mWasActivated = true;
        setPos(pos);
        internal_active = true;

        OnSpriteActivate.raise(cast(Sprite)this);
    }

    //force position
    void setPos(Vector2f pos) {
        physics.setPos(pos, false);
        if (graphic)
            fillAnimUpdate();
    }

    override protected void updateInternalActive() {
        //xxx: doesn't deal with physics!
        if (graphic) {
            graphic.remove();
            graphic = null;
        }
        if (internal_active) {
            auto member = engine.controller ?
                engine.controller.memberFromGameObject(this, true) : null;
            auto owner = member ? member.team : null;
            graphic = new Sequence(engine, owner ? owner.teamColor : null);
            graphic.zorder = GameZOrder.Objects;
            engine.scene.add(graphic);
            physics.checkRotation();
            updateAnimation();
        }
        updateParticles();
    }

    override bool activity() {
        return internal_active && !physics.isGlued;
    }

    protected void physImpact(PhysicBase other, Vector2f normal) {
    }

    //normal always points away from other object
    final void doImpact(PhysicBase other, Vector2f normal) {
        physImpact(other, normal);
    }

    protected void physDamage(float amount, DamageCause type, Object cause) {
        auto goCause = cast(GameObject)cause;
        assert(!cause || !!goCause, "damage by non-GameObject?");
        //goCause can be null (e.g. for fall damage)
        OnDamage.raise(cast(Sprite)this, goCause, type, amount);
    }

    protected void physDie() {
        //assume that's what we want
        if (!internal_active)
            return;
        die();
    }

    void exterminate() {
        //_always_ die completely (or are there exceptions?)
        log("exterminate in deathzone: {}", type.name);
        died_in_deathzone = true;
        die();
    }

    //called when object should die
    //this implementation kills it immediately
    protected void die() {
        internal_active = false;
        if (!physics.dead) {
            physics.dead = true;
            log("really die: {}", type.name);
            OnSpriteDie.raise(cast(Sprite)this);
        }
    }

    //hmm... I'm sure there's a reason die() is protected
    //remove this function to see who needs public access
    void pleasedie() {
        die();
    }

    //update animation to physics status etc.
    final void updateAnimation() {
        if (!graphic)
            return;

        fillAnimUpdate();

        graphic.simulate();
    }

    protected void fillAnimUpdate() {
        assert(!!graphic);
        graphic.position = physics.pos;
        graphic.velocity = physics.velocity;
        graphic.rotation_angle = physics.lookey_smooth;
        if (type.initialHp == float.infinity ||
            physics.lifepower == float.infinity ||
            type.initialHp == 0f)
        {
            graphic.lifePercent = 1.0f;
        } else {
            graphic.lifePercent = max(physics.lifepower / type.initialHp, 0f);
        }
    }

    private void updateParticles() {
        mParticleEmitter.active = internal_active();
        mParticleEmitter.current = mCurrentParticle;
        mParticleEmitter.pos = physics.pos;
        mParticleEmitter.velocity = physics.velocity;
        mParticleEmitter.update(engine.callbacks.particleEngine);
    }

    final void setParticle(ParticleType pt) {
        if (mCurrentParticle is pt)
            return;
        mCurrentParticle = pt;
        updateParticles();
    }

    override void simulate(float deltaT) {
        super.simulate(deltaT);

        bool glue = physics.isGlued;
        if (glue != mOldGlueState) {
            mOldGlueState = glue;
            OnSpriteGlueChanged.raise(cast(Sprite)this);
        }

        if (graphic)
            fillAnimUpdate();

        //xxx: added with sequence-messup
        if (graphic)
            graphic.simulate();

        updateParticles();
    }

    override void hash(Hasher hasher) {
        super.hash(hasher);
        hasher.hash(physics.pos);
        hasher.hash(physics.velocity);
    }

    override void debug_draw(Canvas c) {
        version (RotateDebug) {
            auto p = toVector2i(physics.pos);

            auto r = Vector2f.fromPolar(30, physics.rotation);
            c.drawLine(p, p + toVector2i(r), Color(1,0,0));

            auto n = Vector2f.fromPolar(30, physics.ground_angle);
            c.drawLine(p, p + toVector2i(n), Color(0,1,0));

            auto l = Vector2f.fromPolar(30, physics.lookey_smooth);
            c.drawLine(p, p + toVector2i(l), Color(0,0,1));
        }
    }
}

//object which represents a PhysicObject and an animation on the screen
//also provides loading from ConfigFiles and state managment
class Sprite : BasicSprite {
    protected static LogStruct!("game.sprite") log;

    protected SpriteClass mType;


    private {
        StaticStateInfo mCurrentState; //must not be null

        bool mIsUnderWater, mWaterUpdated;
        bool mWasActivated;
        bool mOldGlueState;
    }

    SpriteClass type() {
        return mType;
    }

    StaticStateInfo currentState() {
        assert(!!mCurrentState);
        return mCurrentState;
    }
    private void currentState(StaticStateInfo n) {
        mCurrentState = n;
    }

    override protected void updateInternalActive() {
        super.updateInternalActive();
        if (internal_active) {
            setCurrentAnimation();
        }
    }

    //update the animation to the current state
    //can be overridden
    protected void setCurrentAnimation() {
        if (!graphic)
            return;

        if (mIsUnderWater && currentState.animationWater) {
            graphic.setState(currentState.animationWater);
        } else {
            graphic.setState(currentState.animation);
        }
    }

    void exterminate() {
        if (!currentState.deathZoneImmune) {
            super.exterminate();
        }
    }

    protected void waterStateChange(bool under) {
        //do something that involves an object and a lot of water
        if (under) {
            auto st = currentState.onDrown;
            if (st) {
                setState(st);
            } else {
                if (currentState.animationWater) {
                    //object has special underwater animation -> don't die
                    setCurrentAnimation();
                    physics.posp = currentState.physicWater;
                } else {
                    //no drowning state -> die now
                    die();
                }
            }
        } else {
            if (!currentState.onDrown && currentState.animationWater) {
                setCurrentAnimation();
                physics.posp = currentState.physic_properties;
            }
        }
    }

    //do as less as necessary to force a new state
    void setStateForced(StaticStateInfo nstate) {
        assert(nstate !is null);

        currentState = nstate;
        physics.posp = nstate.physic_properties;
        //stop all induced forces (e.g. jetpack)
        if (!nstate.keepSelfForce)
            physics.selfForce = Vector2f(0);
        if (graphic) {
            setCurrentAnimation();
            updateAnimation();
        }

        log("force state: {}", nstate.name);

        waterStateChange(mIsUnderWater);
    }

    //when called: currentState is to
    //must not call setState (alone danger for recursion forbids it)
    protected void stateTransition(StaticStateInfo from, StaticStateInfo to) {
    }

    //do a (possibly) soft transition to the new state
    //explictely no-op if same state as currently is set.
    //can refuse state transition
    //  for_end = used internally (with state.onAnimationEnd)
    void setState(StaticStateInfo nstate, bool for_end = false) {
        assert(nstate !is null);

        if (currentState is nstate)
            return;

        if (currentState.noleave && !for_end)
            return;

        if (for_end) {
            assert(nstate is currentState.onAnimationEnd);
        }

        log("state {} -> {}", currentState.name, nstate.name);

        auto oldstate = currentState;
        currentState = nstate;
        physics.posp = nstate.physic_properties;
        //stop all induced forces (e.g. jetpack)
        if (!nstate.keepSelfForce)
            physics.selfForce = Vector2f(0);

        stateTransition(oldstate, currentState);
        //if this fails, maybe stateTransition called setState()?
        assert(currentState is nstate);

        if (graphic) {
            setCurrentAnimation();
            updateAnimation();
        }

        //and particles
        updateParticles();

        //update water state (to catch an underwater state transition)
        waterStateChange(mIsUnderWater);

        OnSpriteSetState.raise(this);
    }

    //never returns null
    StaticStateInfo findState(char[] name) {
        return type.findState(name);
    }

    //called by GameEngine on each frame if it's really under water
    //xxx: TriggerEnter/TriggerExit was more beautiful, so maybe bring it back
    final void setIsUnderWater() {
        mWaterUpdated = true;

        if (mIsUnderWater)
            return;
        mIsUnderWater = true;
        waterStateChange(true);
    }

    final bool isUnderWater() {
        return mIsUnderWater;
    }

    override void simulate(float deltaT) {
        super.simulate(deltaT);

        if (currentState.onAnimationEnd && graphic) {
            //as requested by d0c, timing is dependend from the animation
            if (graphic.readyflag) {
                log("state transition because of animation end");
                //time to change; the setState code will reset the animation
                setState(currentState.onAnimationEnd, true);
            }
        }

        if (!mWaterUpdated && mIsUnderWater) {
            mIsUnderWater = false;
            waterStateChange(false);
        }
        mWaterUpdated = false;

        setParticle(currentState.particle);
    }

    protected this(GameEngine engine, SpriteClass type) {
        super(engine, type);

        assert(type !is null);
        mType = type;


        setStateForced(type.initState);
    }

    this(ReflectCtor c) {
        super(c);
    }
}



//state infos (per sprite class, thus it's static)
class StaticStateInfo {
    private {
        char[] mName;
    }

    POSP physic_properties, physicWater;

    //automatic transition to this state if animation finished
    StaticStateInfo onAnimationEnd, onDrown;
    //don't leave this state (explictly excludes onAnimationEnd)
    bool noleave = false;
    bool keepSelfForce = false;//phys.selfForce will be reset unless this is set
    bool deathZoneImmune = false;  //don't die in deathzone

    SequenceState animation, animationWater;
    SequenceState[char[]] teamAnim;

    //if non-null, always ensure a single particle like this is created
    //this normally should be an invisible particle emitter
    ParticleType particle;

    private {
        //for forward references
        char[] onEndTmp;
        char[] onDrownTmp = "drowning";
    }

    //xxx class
    this (ReflectCtor c) {
        c.transient(this, &onEndTmp);
        c.transient(this, &onDrownTmp);
    }
    this (char[] a_name) {
        mName = a_name;
    }

    final char[] name() {
        return mName;
    }

    void loadFromConfig(ConfigNode sc, ConfigNode physNode, SpriteClass owner)
    {
        //physic stuff, already loaded physic-types are not cached
        //NOTE: if no "physic" value given, use state-name for physics
        auto phys = physNode.findNode(sc.getStringValue("physic", name));
        assert(phys !is null); //xxx better error handling :-)
        physic_properties = new POSP();
        physic_properties.loadFromConfig(phys);
        if (sc["physic_water"].length > 0) {
            //underwater physics
            auto physw = physNode.findNode(sc["physic_water"]);
            assert(physw !is null);
            physicWater = new POSP();
            physicWater.loadFromConfig(physw);
        }

        noleave = sc.getBoolValue("noleave", noleave);
        keepSelfForce = sc.getBoolValue("keep_selfforce", keepSelfForce);
        deathZoneImmune = sc.getBoolValue("deathzone_immune", deathZoneImmune);

        if (sc["animation"].length > 0) {
            animation = owner.findSequenceState(sc["animation"]);
            /+
            if (owner.teamAnimation) {
                foreach (col; TeamTheme.cTeamColors) {
                    teamAnim[col] =
                        owner.findSequenceState(sc["animation"] ~ "_" ~ col);
                }
            }
            +/
        }
        if (sc["animation_water"].length > 0) {
            animationWater = owner.findSequenceState(sc["animation_water"]);
        }

        if (!animation) {
            log("WARNING: no animation for state '{}'", name);
        }

        onEndTmp = sc["on_animation_end"];
        onDrownTmp = sc.getStringValue("drownstate", "drowning");

        auto particlename = sc["particle"];
        if (particlename.length) {
            //xxx move to Sequence (the "animation" should display particles)
            particle = owner.gfx.resources.get!(ParticleType)(particlename);
        }
    }

    void fixup(SpriteClass owner) {
        if (onEndTmp.length > 0) {
            onAnimationEnd = owner.findState(onEndTmp, true);
            onEndTmp = null;
        }
        if (onDrownTmp.length > 0) {
            onDrown = owner.findState(onDrownTmp, true);
        }
    }

    char[] toString() {
        return "[state: "~name~"]";
    }
}

//loads "collisions"-nodes and adds them to the collision map
//loads the required animation file
//loads static physic properties (in a POSP struct)
//load static parts of the "states"-nodes
class SpriteClass : BasicSpriteClass {
    StaticStateInfo[char[]] states;
    StaticStateInfo initState;

    this (GfxSet gfx, char[] regname) {
        super(gfx, regname);

        //create a default state to have at least one state at all
        auto ssi = createStateInfo("defaultstate");
        states[ssi.name] = ssi;
        initState = ssi;
    }

    //xxx class
    this (ReflectCtor c) {
        super(c);
    }

    StaticStateInfo findState(char[] name, bool canfail = false) {
        StaticStateInfo* state = name in states;
        if (!state && !canfail) {
            //xxx better error handling
            throw new Exception("state "~name~" not found");
        }
        if (state)
            return *state;
        else
            return null;
    }

    Sprite createSprite(GameEngine engine) {
        return new Sprite(engine, this);
    }

    override void loadFromConfig(ConfigNode config) {
        super.loadFromConfig(config);

        //some sprites don't have a "normal" state
        //the "normal" sprite is mostly needed for very simple projectiles only
        //actually, the complex sprites (worm) don't use initState at all or
        //  replace it with "initstate"...
        initState.animation = findSequenceState("normal", true);

        //load states
        //physic stuff is loaded when it's referenced in a state description
        foreach (ConfigNode sc; config.getSubNode("states")) {
            auto ssi = createStateInfo(sc.name);
            ssi.loadFromConfig(sc, config.getSubNode("physics"), this);
            states[ssi.name] = ssi;
        } //foreach state to load

        fixStates();

        char[] init_name = config.getValue!(char[])("initstate", "normal");
        StaticStateInfo* init = init_name in states;
        if (init)
            initState = *init;

        //at least the constructor created a default state
        assert(states.length > 0);
        assert(initState !is null);
    }

    //resolve forward refs
    protected void fixStates() {
        foreach (s; states) {
            s.fixup(this);
        }
    }

    //for derived classes: return your StateInfo class here
    protected StaticStateInfo createStateInfo(char[] a_name) {
        return new StaticStateInfo(a_name);
    }

    SequenceState findSequenceState(char[] name,
        bool allow_not_found = false)
    {
        //something in projectile.d seems to need this special case?
        if (!sequenceType) {
            if (allow_not_found)
                return null;
            assert(false, "bla.");
        }
        return sequenceType.findState(name, allow_not_found);
    }

    char[] toString() { return "SpriteClass["~name~"]"; }
}

class BasicSpriteClass {
    GfxSet gfx;
    char[] name;

    SequenceType sequenceType;

    float initialHp = float.infinity;

    this (GfxSet gfx, char[] regname) {
        this.gfx = gfx;
        name = regname;

        gfx.registerSpriteClass(name, cast(SpriteClass)this);
    }

    //xxx class
    this (ReflectCtor c) {
    }

    BasicSprite createSprite(GameEngine engine) {
        return new BasicSprite(engine, this);
    }

    void loadFromConfig(ConfigNode config) {
        //load collision map
        auto col = config.findNode("collisions");
        if (col)
            gfx.addCollideConf(col);

        sequenceType = gfx.resources.get!(SequenceType)
            (config["sequence_object"]);

        initialHp = config.getFloatValue("initial_hp", initialHp);
    }

    //must be called as the engine is "started"
    void initPerEngine(GameEngine engine) {
        assert(!(this in engine.perClassEvents), "double init? "~name);

        auto ev = new Events();
        ev.setScripting(engine.scripting, "eventhandlers_" ~ name);
        engine.perClassEvents[this] = ev;
    }

    //this is a small WTF: I thought I could put the Events instance into
    //  SpriteClass (because it exists only once per sprite class), but
    //  SpriteClass is independent from GameEngine (thus, no scripting!)
    //so, enjoy this horrible hack.
    //all Events instances get created on demand
    //NOTE that this function will be very slow (AA lookup)
    final Events getEvents(GameEngine engine) {
        //if this fails, maybe initPerEngine() wasn't called
        return engine.perClassEvents[this];
    }

    char[] toString() { return "BasicSpriteClass["~name~"]"; }
}
