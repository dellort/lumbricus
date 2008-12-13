module game.sprite;

import framework.framework;
import game.gobject;
import physics.world;
import game.animation;
import game.game;
import game.gamepublic;
import game.sequence;
import game.action;
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

//factory to instantiate sprite classes, this is a small wtf
static class SpriteClassFactory
    : StaticFactory!(GOSpriteClass, GameEngine, char[])
{
}

//object which represents a PhysicObject and an animation on the screen
//also provides loading from ConfigFiles and state managment
class GObjectSprite : GameObject {
    GOSpriteClass type;

    PhysicObject physics;
    //attention: can be null if object inactive
    //if it gets active again it's recreated again LOL
    Sequence graphic;
    SequenceState currentAnimation;
    protected SequenceUpdate seqUpdate;

    private StaticStateInfo mCurrentState; //must not be null
    private Action mCreateAction, mStateAction;

    private bool mIsUnderWater, mWaterUpdated;

    private Action[] mActiveActionsGlobal;
    private Action[] mActiveActionsState;

    protected Vector2f mLastImpactNormal = {0, -1};

    bool activity() {
        return active && !physics.isGlued;
    }

    StaticStateInfo currentState() {
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

        graphic.setState(currentState.animation);
    }

    //update animation to physics status etc.
    final void updateAnimation() {
        if (!graphic)
            return;

        fillAnimUpdate();

        graphic.update(seqUpdate);
    }

    protected SequenceUpdate createSequenceUpdate() {
        return new SequenceUpdate();
    }

    protected void fillAnimUpdate() {
        seqUpdate.position = toVector2i(physics.pos);
        seqUpdate.velocity = physics.velocity;
        seqUpdate.rotation_angle = physics.lookey;
    }

    protected void physUpdate() {
        updateAnimation();

        if (physics.lifepower <= 0)
            doEvent("onzerolife");

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
        mLastImpactNormal = normal;
        doEvent("onimpact");
        mLastImpactNormal = Vector2f(0, -1);
    }

    //normal always points away from other object
    void doImpact(PhysicBase other, Vector2f normal) {
        physImpact(other, normal);
    }

    protected void physDamage(float amout, int cause) {
        doEvent("ondamage");
    }

    protected void physDie() {
        //assume that's what we want
        if (!active)
            return;
        die();
    }

    void exterminate() {
        //_always_ die completely (or are there exceptions?)
        engine.mLog("exterminate in deathzone: %s", type.name);
        die();
    }

    //called when object should die
    //this implementation kills it immediately
    protected void die() {
        doEvent("ondie");

        active = false;
        physics.dead = true;
        engine.mLog("really die: %s", type.name);
    }

    protected void waterStateChange(bool under) {
        //do something that involves an object and a lot of water
        if (under) {
            auto st = type.findState("drowning", true);
            if (st) {
                setState(st);
            } else {
                //no drowning state -> die now
                die();
            }
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
    }

    //when called: currentState is to
    //must not call setState (alone danger for recursion forbids it)
    protected void stateTransition(StaticStateInfo from, StaticStateInfo to) {
        cleanStateActions();
        //run state-initialization event
        doEvent("oncreate", true);
    }

    private void cleanStateActions() {
        //cleanup old per-state actions still running
        foreach (a; mActiveActionsState) {
            if (a.active)
                a.abort();
        }
        mActiveActionsState = null;
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
            graphic = engine.graphics.createSequence(type.sequenceObject);
            physics.checkRotation();
            setCurrentAnimation();
            updateAnimation();
            //"oncreate" is the sprite or state initialize event
            doEvent("oncreate");
        } else {
            cleanStateActions();
            //cleanup old global actions still running (like oncreate)
            foreach (a; mActiveActionsGlobal) {
                if (a.active)
                    a.abort();
            }
            mActiveActionsGlobal = null;
        }
    }

    //called by GameEngine on each frame if it's really under water
    //xxx: TriggerEnter/TriggerExit was more beautiful, so maybe bring it back
    final void isUnderWater() {
        if (mIsUnderWater)
            return;

        mIsUnderWater = true;
        mWaterUpdated = true;
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
        if (!mWaterUpdated) {
            mIsUnderWater = false;
            waterStateChange(false);
        }
        mWaterUpdated = false;
    }

    protected MyBox readParam(char[] id) {
        switch (id) {
            case "sprite":
                return MyBox.Box(this);
            case "owner_game":
                return MyBox.Box(cast(GameObject)this);
            default:
                return MyBox();
        }
    }

    ///runs a sprite-specific event defined in the config file
    //xxx should be private, but is used by some actions
    void doEvent(char[] id, bool stateonly = false) {
        //logging: this is slow (esp. napalm)
        //engine.mLog("Projectile: Execute event "~id);

        //run a global or state-specific action by id, if defined
        void execAction(char[] id, bool state = false) {
            ActionClass ac;
            if (state) ac = currentState.actions.action(id);
            else ac = type.actions.action(id);
            if (ac) {
                //run action if found
                auto a = ac.createInstance(engine);
                auto ctx = new ActionContext(&readParam);
                //ctx.activityCheck = &activity;
                a.execute(ctx);
                if (a.active) {
                    //action still reports active after execute call, so add
                    //it to the active actions list to allow later cleanup
                    if (state) mActiveActionsState ~= a;
                    else mActiveActionsGlobal ~= a;
                }
            }
        }

        if (!stateonly)
            execAction(id, false);
        execAction(id, true);

        if (id == "ondetonate") {
            //reserved event that kills the sprite
            die();
            return;
        }
        if (id in type.detonateMap || id in currentState.detonateMap) {
            //current event should cause the projectile to detonate
            //xxx reserved identifier
            doEvent("ondetonate");
        }
    }

    protected this(GameEngine engine, GOSpriteClass type) {
        super(engine, false);

        assert(type !is null);
        this.type = type;

        seqUpdate = createSequenceUpdate();

        physics = new PhysicObject();
        physics.backlink = this;
        physics.lifepower = type.initialHp;

        engine.physicworld.add(physics);

        physics.onUpdate = &physUpdate;
        physics.onDie = &physDie;
        physics.onDamage = &physDamage;

        setStateForced(type.initState);
    }
}



//state infos (per sprite class, thus it's static)
class StaticStateInfo {
    char[] name;
    POSP physic_properties;

    //automatic transition to this state if animation finished
    StaticStateInfo onAnimationEnd;
    //don't leave this state (explictly excludes onAnimationEnd)
    bool noleave = false;
    bool keepSelfForce = false;//phys.selfForce will be reset unless this is set

    SequenceState animation;

    ActionContainer actions;

    bool[char[]] detonateMap;

    private {
        //for forward references
        char[] onEndTmp, actionsTmp;
    }

    this() {
        actions = new ActionContainer();
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

        if (sc["animation"].length > 0) {
            animation = owner.sequenceObject.findState(sc["animation"]);
        }

        if (!animation) {
            owner.engine.mLog("WARNING: no animation for state '%s'", name);
        }

        onEndTmp = sc["on_animation_end"];

        auto acnode = sc.findNode("actions");
        if (acnode) {
            //"actions" is a node containing action defs
            actions = new ActionContainer();
            actions.loadFromConfig(owner.engine, acnode);
        } else {
            //"actions" is a reference to another state
            actionsTmp = sc["actions"];
        }

        auto detonateNode = sc.getSubNode("detonate");
        foreach (char[] name, char[] value; detonateNode) {
            //xxx sry
            if (value == "true" && name != "ondetonate") {
                detonateMap[name] = true;
            }
        }
    }

    void fixup(GOSpriteClass owner) {
        if (actionsTmp.length > 0) {
            auto st = owner.findState(actionsTmp, true);
            if (st)
                actions = st.actions;
            actionsTmp = null;
        }
        if (onEndTmp.length > 0) {
            onAnimationEnd = owner.findState(onEndTmp, true);
            onEndTmp = null;
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

    SequenceObject sequenceObject;

    StaticStateInfo[char[]] states;
    StaticStateInfo initState;

    ActionContainer actions;

    bool[char[]] detonateMap;

    float initialHp = float.infinity;

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
        auto ssi = new StaticStateInfo();
        ssi.name = "defaultstate";
        states[ssi.name] = ssi;
        initState = ssi;

        actions = new ActionContainer();
    }

    void loadFromConfig(ConfigNode config) {
        //load collision map
        engine.physicworld.collide.loadCollisions(config.getSubNode("collisions"));

        sequenceObject = engine.gfx.resources.resource!(SequenceObject)
            (config["sequence_object"]).get;

        actions.loadFromConfig(engine, config.getSubNode("actions"));

        auto detonateNode = config.getSubNode("detonate");
        foreach (char[] name, char[] value; detonateNode) {
            //xxx sry
            if (value == "true" && name != "ondetonate") {
                detonateMap[name] = true;
            }
        }

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

    static this() {
        SpriteClassFactory.register!(typeof(this))("sprite_mc");
    }
}
