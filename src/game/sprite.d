module game.sprite;

import framework.framework;
import game.gobject;
import game.animation;
import game.game;
import game.gamepublic;
import game.sequence;
import physics.world;

import utils.vector2;
import utils.rect2;
import utils.configfile;
import utils.misc;
import utils.log;
import utils.math;
import std.math : abs, PI;
import cmath = std.c.math;
import utils.factory;
import utils.time;
import utils.mybox;
import utils.reflection;

//factory to instantiate sprite classes, this is a small wtf
static class SpriteClassFactory
    : StaticFactory!(GOSpriteClass, GameEngine, char[])
{
}

//object which represents a PhysicObject and an animation on the screen
//also provides loading from ConfigFiles and state managment
class GObjectSprite : GameObject {
    protected GOSpriteClass mType;

    PhysicObject physics;
    //attention: can be null if object inactive
    //if it gets active again it's recreated again LOL
    Sequence graphic;
    SequenceState currentAnimation;
    protected SequenceUpdate seqUpdate;

    private StaticStateInfo mCurrentState; //must not be null

    private bool mIsUnderWater, mWaterUpdated;

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

        if (mIsUnderWater && currentState.animationWater)
            graphic.setState(currentState.animationWater);
        else
            graphic.setState(currentState.animation);
    }

    //update animation to physics status etc.
    final void updateAnimation() {
        if (!graphic)
            return;

        fillAnimUpdate();

        //graphic.update(seqUpdate);
        graphic.simulate();
    }

    //can be overriden by user, but he must set seqUpdate
    protected void createSequenceUpdate() {
        seqUpdate = new SequenceUpdate();
    }

    protected void fillAnimUpdate() {
        seqUpdate.position = toVector2i(physics.pos);
        seqUpdate.velocity = physics.velocity;
        seqUpdate.rotation_angle = physics.lookey;
        if (type.initialHp == float.infinity ||
            physics.lifepower == float.infinity)
            seqUpdate.lifePercent = 1.0f;
        else
            seqUpdate.lifePercent = max(physics.lifepower / type.initialHp, 0f);
    }

    protected void physUpdate() {
        updateAnimation();

        if (!mWaterUpdated && mIsUnderWater) {
            mIsUnderWater = false;
            waterStateChange(false);
        }
        mWaterUpdated = false;

        /+
        yyy move this code into the client's GUI
        this can't be here because this depends from what part of the level
        you look into
        //check if sprite is out of level
        //if so, draw nice out-of-level-graphic
        auto scenerect = Rect2i(0,0,graphic.scene.size.x,graphic.scene.size.y);
        if (!scenerect.intersects(Rect2i(graphic.pos,graphic.pos+graphic.size))
            && !underWater)
        {
            auto hsize = outOfLevel.size/2;
            //draw arrow 5 pixels before level border
            scenerect.extendBorder(-hsize-Vector2i(5));
            auto dest = graphic.pos+graphic.size/2;
            auto c = scenerect.clip(dest);
            outOfLevel.pos = c - hsize;
            //get the angle to the outside graphic
            //auto angle = -toVector2f(dest-c).normal.toAngle();
            auto angle = -physics.velocity.toAngle();
            //frame according to angle; starts at 270 degrees => add PI/2
            auto frames = outOfLevel.currentAnimation.frameCount;
            auto frame = cast(int)(realmod(angle+PI/2,PI*2)/(PI*2)*frames);
            outOfLevel.setFrame(frame);
            outOfLevel.active = active; //only make active if self active
        } else {
            outOfLevel.active = false;
        }
        +/
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
            engine.mLog("exterminate in deathzone: %s", type.name);
            die();
        }
    }

    //called when object should die
    //this implementation kills it immediately
    protected void die() {
        active = false;
        physics.dead = true;
        engine.mLog("really die: %s", type.name);
    }

    protected void waterStateChange(bool under) {
        //do something that involves an object and a lot of water
        if (under) {
            auto st = currentState.onDrown;
            if (st) {
                setState(st);
            } else {
                if (currentState.animationWater)
                    //object has special underwater animation -> don't die
                    setCurrentAnimation();
                else
                    //no drowning state -> die now
                    die();
            }
        } else {
            if (!currentState.onDrown && currentState.animationWater)
                setCurrentAnimation();
        }
    }

    //force position
    void setPos(Vector2f pos) {
        physics.setPos(pos, false);
        //physUpdate();
        physics.needUpdate();
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

        engine.mLog("force state: %s", nstate.name);

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

        engine.mLog("state %s -> %s", currentState.name, nstate.name);

        auto oldstate = currentState;
        currentState = nstate;
        physics.posp = nstate.physic_properties;
        //stop all induced forces (e.g. jetpack)
        if (!nstate.keepSelfForce)
            physics.selfForce = Vector2f(0);

        if (graphic) {
            setCurrentAnimation();
            updateAnimation();
        }

        stateTransition(oldstate, currentState);
        //if this fails, maybe stateTransition called setState()?
        assert(currentState is nstate);

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
            graphic = new Sequence(engine);
            graphic.setUpdater(seqUpdate);
            physics.checkRotation();
            setCurrentAnimation();
            updateAnimation();
        }
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
                engine.mLog("state transition because of animation end");
                //time to change; the setState code will reset the animation
                setState(currentState.onAnimationEnd, true);
            }
        }
        //xxx: added with sequence-messup
        if (graphic)
            graphic.simulate();
    }

    protected this(GameEngine engine, GOSpriteClass type) {
        super(engine, false);

        assert(type !is null);
        mType = type;

        createSequenceUpdate();

        physics = new PhysicObject();
        physics.backlink = this;
        physics.lifepower = type.initialHp;

        engine.physicworld.add(physics);

        physics.onUpdate = &physUpdate;
        physics.onDie = &physDie;
        physics.onDamage = &physDamage;

        setStateForced(type.initState);
    }

    this (ReflectCtor c) {
        super(c);
        c.types().registerMethod(this, &physUpdate, "physUpdate");
        c.types().registerMethod(this, &physDie, "physDie");
        c.types().registerMethod(this, &physDamage, "physDamage");
    }
}



//state infos (per sprite class, thus it's static)
class StaticStateInfo {
    char[] name;
    POSP physic_properties;

    //automatic transition to this state if animation finished
    StaticStateInfo onAnimationEnd, onDrown;
    //don't leave this state (explictly excludes onAnimationEnd)
    bool noleave = false;
    bool keepSelfForce = false;//phys.selfForce will be reset unless this is set
    bool deathZoneImmune = false;  //don't die in deathzone

    SequenceState animation, animationWater;

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
    this () {
    }

    void loadFromConfig(ConfigNode sc, ConfigNode physNode, GOSpriteClass owner)
    {
        name = sc.name;

        //physic stuff, already loaded physic-types are not cached
        //NOTE: if no "physic" value given, use state-name for physics
        auto phys = physNode.findNode(sc.getStringValue("physic", name));
        assert(phys !is null); //xxx better error handling :-)
        physic_properties = new POSP();
        physic_properties.loadFromConfig(phys);

        noleave = sc.getBoolValue("noleave", noleave);
        keepSelfForce = sc.getBoolValue("keep_selfforce", keepSelfForce);
        deathZoneImmune = sc.getBoolValue("deathzone_immune", deathZoneImmune);

        if (sc["animation"].length > 0) {
            animation = owner.findSequenceState(sc["animation"]);
        }
        if (sc["animation_water"].length > 0) {
            animationWater = owner.findSequenceState(sc["animation_water"]);
        }

        if (!animation) {
            owner.engine.mLog("WARNING: no animation for state '%s'", name);
        }

        onEndTmp = sc["on_animation_end"];
        onDrownTmp = sc.getStringValue("drownstate", "drowning");
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
}

//loads "collisions"-nodes and adds them to the collision map
//loads the required animation file
//loads static physic properties (in a POSP struct)
//load static parts of the "states"-nodes
class GOSpriteClass {
    GameEngine engine;
    char[] name;

    //SequenceObject sequenceObject;
    char[] sequencePrefix;

    StaticStateInfo[char[]] states;
    StaticStateInfo initState;

    float initialHp = float.infinity;

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

    GObjectSprite createSprite() {
        return new GObjectSprite(engine, this);
    }

    this (GameEngine engine, char[] regname) {
        this.engine = engine;
        name = regname;

        engine.registerSpriteClass(regname, this);

        //create a default state to have at least one state at all
        auto ssi = createStateInfo();
        ssi.name = "defaultstate";
        states[ssi.name] = ssi;
        initState = ssi;
    }

    void loadFromConfig(ConfigNode config) {
        //load collision map
        engine.physicworld.collide.loadCollisions(config.getSubNode("collisions"));

        //sequenceObject = engine.gfx.resources.resource!(SequenceObject)
          //  (config["sequence_object"]).get;
        //explanation see worm.conf
        sequencePrefix = config["sequence_object"];

        initialHp = config.getFloatValue("initial_hp", initialHp);

        //load states
        //physic stuff is loaded when it's referenced in a state description
        foreach (ConfigNode sc; config.getSubNode("states")) {
            auto ssi = createStateInfo();
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
    protected StaticStateInfo createStateInfo() {
        return new StaticStateInfo();
    }

    SequenceState findSequenceState(char[] pseudo_name,
        bool allow_not_found = false)
    {
        return engine.sequenceStates.findState(sequencePrefix ~ '_' ~
            pseudo_name, allow_not_found);
    }

    static this() {
        SpriteClassFactory.register!(typeof(this))("sprite_mc");
    }
}
