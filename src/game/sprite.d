module game.sprite;

import framework.framework;
import game.gobject;
import game.animation;
import game.game;
import game.gamepublic;
import game.sequence;
import game.gfxset;
import game.particles;
import net.marshal : Hasher;
import physics.world;

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

//factory to instantiate sprite classes, this is a small wtf
alias StaticFactory!("Sprites", GOSpriteClass, GfxSet, char[])
    SpriteClassFactory;

//version = RotateDebug;

//object which represents a PhysicObject and an animation on the screen
//also provides loading from ConfigFiles and state managment
class GObjectSprite : GameObject {
    protected static LogStruct!("game.sprite") log;

    protected GOSpriteClass mType;

    PhysicObject physics;
    //attention: can be null if object inactive
    //if it gets active again it's recreated again LOL
    Sequence graphic;
    SequenceState currentAnimation;

    private {
        //transient for savegames, Particle created from StaticStateInfo.particle
        //all state associated with this variable is non-deterministic and must not
        //  have any influence on the rest of the game state
        //xxx: move to Sequence, as soon as this is being rewritten
        ParticleEmitter mParticleEmitter;

        StaticStateInfo mCurrentState; //must not be null

        bool mIsUnderWater, mWaterUpdated;
        bool mWasActivated;
    }

    //xxx: replace by activate(position)?
    void activate(Vector2f pos) {
        if (physics.dead || mWasActivated)
            return;
        mWasActivated = true;
        setPos(pos);
        active = true;
    }

    bool activity() {
        return active && !physics.isGlued;
    }

    GOSpriteClass type() {
        return mType;
    }

    StaticStateInfo currentState() {
        assert(!!mCurrentState);
        return mCurrentState;
    }
    private void currentState(StaticStateInfo n) {
        mCurrentState = n;
    }

    //update the animation to the current state
    //can be overridden
    protected void setCurrentAnimation() {
        if (!graphic)
            return;

        if (mIsUnderWater && currentState.animationWater) {
            graphic.setState(currentState.animationWater);
        } else {
            SequenceState nstate = currentState.animation;
            if (mType.teamAnimation) {
                auto m = engine.controller.memberFromGameObject(this, true);
                if (m) {
                    nstate = currentState.teamAnim[
                        TeamTheme.cTeamColors[m.team.color.colorIndex]];
                }
            }
            graphic.setState(nstate);
        }
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
        mParticleEmitter.active = active();
        mParticleEmitter.current = currentState.particle;
        mParticleEmitter.pos = physics.pos;
        mParticleEmitter.velocity = physics.velocity;
        mParticleEmitter.update(engine.callbacks.particleEngine);
    }

    protected void physImpact(PhysicBase other, Vector2f normal) {
    }

    //normal always points away from other object
    void doImpact(PhysicBase other, Vector2f normal) {
        physImpact(other, normal);
    }

    protected void physDamage(float amount, int cause) {
    }

    protected void physDie() {
        //assume that's what we want
        if (!active)
            return;
        die();
    }

    void exterminate() {
        if (!currentState.deathZoneImmune) {
            //_always_ die completely (or are there exceptions?)
            log("exterminate in deathzone: {}", type.name);
            die();
        }
    }

    //called when object should die
    //this implementation kills it immediately
    protected void die() {
        active = false;
        physics.dead = true;
        log("really die: {}", type.name);
    }

    //hmm... I'm sure there's a reason die() is protected
    //remove this function to see who needs public access
    void pleasedie() {
        die();
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

    //force position
    void setPos(Vector2f pos) {
        physics.setPos(pos, false);
        if (graphic)
            fillAnimUpdate();
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
    }

    //never returns null
    StaticStateInfo findState(char[] name) {
        return type.findState(name);
    }

    override protected void updateActive() {
        //xxx: doesn't deal with physics!
        if (graphic) {
            graphic.remove();
            graphic = null;
        }
        if (active) {
            auto member = engine.controller ?
                engine.controller.memberFromGameObject(this, true) : null;
            auto owner = member ? member.team : null;
            graphic = new Sequence(engine, owner ? owner.teamColor : null);
            graphic.zorder = GameZOrder.Objects;
            engine.scene.add(graphic);
            physics.checkRotation();
            setCurrentAnimation();
            updateAnimation();
        }
        updateParticles();
    }

    //called by GameEngine on each frame if it's really under water
    //xxx: TriggerEnter/TriggerExit was more beautiful, so maybe bring it back
    final void isUnderWater() {
        mWaterUpdated = true;

        if (mIsUnderWater)
            return;
        mIsUnderWater = true;
        waterStateChange(true);
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

    protected this(GameEngine engine, GOSpriteClass type) {
        super(engine, false);

        assert(type !is null);
        mType = type;

        physics = new PhysicObject();
        physics.backlink = this;
        physics.lifepower = type.initialHp;

        engine.physicworld.add(physics);

        physics.onDie = &physDie;
        physics.onDamage = &physDamage;

        setStateForced(type.initState);
    }

    this (ReflectCtor c) {
        super(c);
        c.types().registerMethod(this, &physDie, "physDie");
        c.types().registerMethod(this, &physDamage, "physDamage");
        c.transient(this, &mParticleEmitter);
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

    void loadFromConfig(ConfigNode sc, ConfigNode physNode, GOSpriteClass owner)
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
            if (owner.teamAnimation) {
                foreach (col; TeamTheme.cTeamColors) {
                    teamAnim[col] =
                        owner.findSequenceState(sc["animation"] ~ "_" ~ col);
                }
            }
        }
        if (sc["animation_water"].length > 0) {
            animationWater = owner.findSequenceState(sc["animation_water"]);
        }

        if (!animation) {
            owner.log("WARNING: no animation for state '{}'", name);
        }

        onEndTmp = sc["on_animation_end"];
        onDrownTmp = sc.getStringValue("drownstate", "drowning");

        auto particlename = sc["particle"];
        if (particlename.length) {
            //isn't this funny
            particle = owner.gfx.resources
                .get!(ParticleType)(particlename);
        }
    }

    void fixup(GOSpriteClass owner) {
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
class GOSpriteClass {
    GfxSet gfx;
    char[] name;

    //SequenceObject sequenceObject;
    char[] sequencePrefix;
    bool teamAnimation = false;

    StaticStateInfo[char[]] states;
    StaticStateInfo initState;

    float initialHp = float.infinity;

    protected static LogStruct!("game.spriteclass") log;

    //xxx class
    this (ReflectCtor c) {
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

    GObjectSprite createSprite(GameEngine engine) {
        return new GObjectSprite(engine, this);
    }

    this (GfxSet gfx, char[] regname) {
        this.gfx = gfx;
        name = regname;

        gfx.registerSpriteClass(regname, this);

        //create a default state to have at least one state at all
        auto ssi = createStateInfo("defaultstate");
        states[ssi.name] = ssi;
        initState = ssi;
    }

    void loadFromConfig(ConfigNode config) {
        //load collision map
        gfx.addCollideConf(config.getSubNode("collisions"));

        //sequenceObject = engine.gfx.resources.resource!(SequenceObject)
          //  (config["sequence_object"]).get;
        //explanation see worm.conf
        sequencePrefix = config["sequence_object"];

        initialHp = config.getFloatValue("initial_hp", initialHp);
        teamAnimation = config.getValue("team_animation", teamAnimation);

        //load states
        //physic stuff is loaded when it's referenced in a state description
        foreach (ConfigNode sc; config.getSubNode("states")) {
            auto ssi = createStateInfo(sc.name);
            ssi.loadFromConfig(sc, config.getSubNode("physics"), this);
            states[ssi.name] = ssi;

            //make the first state the init state (possibly overriden by
            //"initstate" later)
            if (!initState)
                initState = ssi;
        } //foreach state to load

        //resolve forward refs
        foreach (s; states) {
            s.fixup(this);
        }

        StaticStateInfo* init = config["initstate"] in states;
        if (init && *init)
            initState = *init;

        //at least the constructor created a default state
        assert(initState !is null);
        assert(states.length > 0);
    }

    //for derived classes: return your StateInfo class here
    protected StaticStateInfo createStateInfo(char[] a_name) {
        return new StaticStateInfo(a_name);
    }

    SequenceState findSequenceState(char[] pseudo_name,
        bool allow_not_found = false)
    {
        return gfx.sequenceStates.findState(sequencePrefix ~ '_' ~
            pseudo_name, allow_not_found);
    }

    static this() {
        SpriteClassFactory.register!(typeof(this))("sprite_mc");
    }
}
