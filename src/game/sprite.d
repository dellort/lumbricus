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
import utils.time;
import utils.mybox;

private LogStruct!("game.sprite") log;

//version = RotateDebug;

//object which represents a PhysicObject and an animation on the screen
//also provides loading from ConfigFiles
class Sprite : GameObject {
    private {
        //transient for savegames, Particle created from StaticStateInfo.particle
        //all state associated with this variable is non-deterministic and must not
        //  have any influence on the rest of the game state
        //xxx: move to Sequence, as soon as this is being rewritten
        ParticleEmitter mParticleEmitter;
        ParticleType mCurrentParticle;

        bool mWasActivated;
        bool mOldGlueState;
        bool mIsUnderWater, mWaterUpdated;
        bool mZeroHpCalled;
    }
    protected SpriteClass mType;

    PhysicObject physics;
    //attention: can be null if object inactive
    //if it gets active again it's recreated again LOL
    Sequence graphic;

    //if false, sprite is considered active if visible/alive
    //if true, sprite is considered active only if it's moving (== unglued)
    bool noActivityWhenGlued;

    this(GameEngine a_engine, SpriteClass a_type) {
        super(a_engine, a_type.name);
        mType = a_type;
        assert(!!mType);

        noActivityWhenGlued = type.initNoActivityWhenGlued;

        physics = new PhysicObject();
        physics.backlink = this;
        physics.lifepower = type.initialHp;

        physics.posp = type.initPhysic;

        physics.onDie = &physDie;
        physics.onDamage = &physDamage;

        setParticle(type.initParticle);
    }

    SpriteClass type() {
        return mType;
    }

    //if it's placed in the world (physics, animation)
    bool visible() {
        return internal_active;
    }

    void activate(Vector2f pos) {
        if (physics.dead || mWasActivated)
            return;
        mWasActivated = true;
        setPos(pos);
        internal_active = true;

        OnSpriteActivate.raise(this);
    }

    //force position
    void setPos(Vector2f pos) {
        physics.setPos(pos, false);
        if (graphic)
            fillAnimUpdate();
    }

    override protected void updateInternalActive() {
        if (graphic) {
            graphic.remove();
            graphic = null;
        }
        physics.remove = true;
        if (internal_active) {
            engine.physicworld.add(physics);
            auto member = engine.controller ?
                engine.controller.memberFromGameObject(this, true) : null;
            auto owner = member ? member.team : null;
            graphic = new Sequence(engine, owner ? owner.teamColor : null);
            graphic.zorder = GameZOrder.Objects;
            if (auto st = type.getInitSequenceState())
                graphic.setState(st);
            engine.scene.add(graphic);
            physics.checkRotation();
            updateAnimation();
        }
        updateParticles();
    }

    override bool activity() {
        return internal_active && !(physics.isGlued && noActivityWhenGlued);
    }

    protected void physImpact(PhysicBase other, Vector2f normal) {
        //it appears no code uses the "other" parameter
        OnSpriteImpact.raise(this, normal);
    }

    //normal always points away from other object
    final void doImpact(PhysicBase other, Vector2f normal) {
        physImpact(other, normal);
    }

    protected void physDamage(float amount, DamageCause type, Object cause) {
        auto goCause = cast(GameObject)cause;
        assert(!cause || !!goCause, "damage by non-GameObject?");
        //goCause can be null (e.g. for fall damage)
        OnDamage.raise(this, goCause, type, amount);
    }

    protected void physDie() {
        //assume that's what we want
        if (!internal_active)
            return;
        kill();
    }

    final void exterminate() {
        //_always_ die completely (or are there exceptions?)
        log("exterminate in deathzone: {}", type.name);
        kill();
    }

    override void onKill() {
        super.onKill();
        internal_active = false;
        if (!physics.dead) {
            physics.dead = true;
            log("really die: {}", type.name);
            OnSpriteDie.raise(this);
        }
    }

    //update animation to physics status etc.
    final void updateAnimation() {
        if (!graphic)
            return;

        fillAnimUpdate();

        //this is needed to fix a 1-frame error with worms - when you walk, the
        //  weapon gets deselected, and without this code, the weapon icon
        //  (normally used for weapons without animation) can be seen for a
        //  frame or so
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

    //called by GameEngine on each frame if it's really under water
    //xxx: TriggerEnter/TriggerExit was more beautiful, so maybe bring it back
    final void setIsUnderWater() {
        mWaterUpdated = true;

        if (mIsUnderWater)
            return;
        mIsUnderWater = true;
        waterStateChange();
    }

    final bool isUnderWater() {
        return mIsUnderWater;
    }

    protected void waterStateChange() {
        OnSpriteWaterState.raise(this);
    }

    override void simulate(float deltaT) {
        super.simulate(deltaT);

        bool glue = physics.isGlued;
        if (glue != mOldGlueState) {
            mOldGlueState = glue;
            OnSpriteGlueChanged.raise(this);
        }

        if (graphic)
            fillAnimUpdate();

        //xxx: added with sequence-messup
        if (graphic)
            graphic.simulate();

        if (!mWaterUpdated && mIsUnderWater) {
            mIsUnderWater = false;
            waterStateChange();
        }
        mWaterUpdated = false;

        if (physics.lifepower <= 0) {
            if (!mZeroHpCalled)
                OnSpriteZeroHp.raise(this);
            mZeroHpCalled = true;
        }

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

class SpriteClass {
    GfxSet gfx;
    char[] name;

    SequenceType sequenceType;
    //can be null (then sequenceType.normalState is used)
    //if non-null, sequenceType is ignored (remember that SequenceType just
    //  provides a namespace for sequenceStates anyway)
    //see getInitSequenceState()
    SequenceState sequenceState;

    //those are just "utility" properties to simplify initialization
    //in most cases, it's all what one needs
    float initialHp = float.infinity;
    POSP initPhysic;
    ParticleType initParticle;
    bool initNoActivityWhenGlued = false;

    this (GfxSet gfx, char[] regname) {
        this.gfx = gfx;
        name = regname;

        initPhysic = new POSP();
    }

    Sprite createSprite(GameEngine engine) {
        return new Sprite(engine, this);
    }

    //may return null
    SequenceState getInitSequenceState() {
        auto state = sequenceState;
        if (!state && sequenceType)
            state = sequenceType.normalState;
        return state;
    }
    SequenceType getInitSequenceType() {
        if (sequenceState && sequenceState.owner)
            return sequenceState.owner;
        return sequenceType;
    }

    void loadFromConfig(ConfigNode config) {
        //load collision map
        auto col = config.findNode("collisions");
        if (col)
            gfx.addCollideConf(col);

        sequenceType = gfx.resources.get!(SequenceType)
            (config["sequence_object"]);

        initialHp = config.getFloatValue("initial_hp", initialHp);
        initPhysic.loadFromConfig(config.getSubNode("init_physic"));
        char[] p = config["init_particle"];
        if (p.length)
            initParticle = gfx.resources.get!(ParticleType)(p);
    }

    char[] toString() { return "SpriteClass["~name~"]"; }
}

//------------

class StateSprite : Sprite {
    protected static LogStruct!("game.sprite") log;

    private {
        StaticStateInfo mCurrentState; //must not be null
    }

    override StateSpriteClass type() {
        return cast(StateSpriteClass)mType;
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

        if (isUnderWater && currentState.animationWater) {
            graphic.setState(currentState.animationWater);
        } else {
            graphic.setState(currentState.animation);
        }
    }

    override protected void waterStateChange() {
        super.waterStateChange();
        //do something that involves an object and a lot of water
        if (isUnderWater) {
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
                    kill();
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

        waterStateChange();
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
        waterStateChange();

        OnSpriteSetState.raise(this);
    }

    //never returns null
    StaticStateInfo findState(char[] name) {
        return type.findState(name);
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

        setParticle(currentState.particle);
    }

    protected this(GameEngine engine, StateSpriteClass type) {
        super(engine, type);

        setStateForced(type.initState);
    }
}



//state infos (per StateSprite class, thus it's static)
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

    this (char[] a_name) {
        mName = a_name;
    }

    final char[] name() {
        return mName;
    }

    void loadFromConfig(ConfigNode sc, ConfigNode physNode, StateSpriteClass owner)
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

    void fixup(StateSpriteClass owner) {
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
class StateSpriteClass : SpriteClass {
    StaticStateInfo[char[]] states;
    StaticStateInfo initState;

    this (GfxSet gfx, char[] regname) {
        super(gfx, regname);

        //force default to true for compatibility
        initNoActivityWhenGlued = true;

        //create a default state to have at least one state at all
        auto ssi = createStateInfo("defaultstate");
        states[ssi.name] = ssi;
        initState = ssi;
    }

    StaticStateInfo findState(char[] name, bool canfail = false) {
        StaticStateInfo* state = name in states;
        if (!state && !canfail) {
            //xxx better error handling
            throw new CustomException("state "~name~" not found");
        }
        if (state)
            return *state;
        else
            return null;
    }

    StateSprite createSprite(GameEngine engine) {
        return new StateSprite(engine, this);
    }

    override void loadFromConfig(ConfigNode config) {
        super.loadFromConfig(config);

        //some sprites don't have a "normal" state
        //the "normal" StateSprite is mostly needed for very simple projectiles only
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

    char[] toString() { return "StateSpriteClass["~name~"]"; }
}

