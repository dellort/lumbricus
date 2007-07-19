module game.sprite;
import game.gobject;
import game.physic;
import game.animation;
import game.game;
import game.gamepublic;
import common.common;
import utils.vector2;
import utils.rect2;
import utils.configfile;
import utils.misc;
import utils.log;
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
    StaticStateInfo currentState; //must not be null

    PhysicObject physics;
    //attention: can be null if object inactive
    ServerGraphic graphic;

    AnimationResource currentAnimation;
    Time animationStarted;

    int param2;

    //return animations for states; this can be used to "patch" animations for
    //specific states (used for worm.d/weapons)
    protected AnimationResource getAnimationForState(StaticStateInfo info) {
        return info.animation;
    }

    //update the animation to the current state and physics status
    void updateAnimation() {
        if (!graphic)
            return;

        auto wanted_animation = getAnimationForState(currentState);

        //must not set animation all the time, because setAnimation() resets
        //the animation (maybe.... or maybe not)
        if (wanted_animation !is currentAnimation) {
            //xxx you have to decide: false or true as parameter?
            // true = force, false = wait until current animation done
            graphic.setNextAnimation(wanted_animation, false);
            animationStarted = engine.gameTime.current;
            currentAnimation = wanted_animation;
        }

        graphic.setPos(toVector2i(physics.pos));
        graphic.setVelocity(physics.velocity);
        graphic.setParams(angleToAnimation(physics.lookey), param2);
    }

    static int angleToAnimation(float angle) {
        //worm angles: start pointing upwards (dir.y = -1), then goes with the clock
        //(while physics angles start at (1, 0) and go against the clock)
        //(going with the clock as you see it on screen, with (0,0) in upper left)
        return realmod(cast(int)((-angle+PI/2*3)/PI*180.0f), 360);
    }

    protected void physUpdate() {
        updateAnimation();

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

    protected void physImpact(PhysicBase other) {
    }

    protected void physDie() {
        //assume that's what we want
        if (!active)
            return;
        die();
    }

    protected void physTriggerEnter(char[] trigId) {
        if (trigId == "waterplane") {
            waterStateChange(true);
        } else if (trigId == "deathzone") {
            //_always_ die completely (or are there exceptions?)
            engine.mLog("exterminate in deathzone: %s", type.name);
            die();
        }
    }

    protected void physTriggerExit(char[] trigId) {
        if (trigId == "waterplane") {
            waterStateChange(false);
        }
    }

    //called when object should die
    //this implementation kills it immediately
    protected void die() {
        active = false;
        physics.dead = true;
        engine.mLog("really die: %s", type.name);
    }

    public bool underWater() {
        return physics.triggerActive("waterplane");
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
        physics.pos = pos;
        physUpdate();
    }

    //do as less as necessary to force a new state
    void setStateForced(StaticStateInfo nstate) {
        assert(nstate !is null);

        currentState = nstate;
        physics.posp = nstate.physic_properties;
        updateAnimation();

        engine.mLog("force state: %s", nstate.name);
    }

    //when called: currentState is to
    //must not call setState (alone danger for recursion forbids it)
    protected void stateTransition(StaticStateInfo from, StaticStateInfo to) {
    }

    //do a (possibly) soft transition to the new state
    //explictely no-op if same state as currently is set.
    //can refuse state transition
    void setState(StaticStateInfo nstate) {
        assert(nstate !is null);

        if (currentState is nstate)
            return;

        if (currentState.noleave)
            return;

        engine.mLog("state %s -> %s", currentState.name, nstate.name);

        auto oldstate = currentState;
        currentState = nstate;
        physics.posp = nstate.physic_properties;

        updateAnimation();

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
            graphic = engine.createGraphic();
            graphic.setVisible(true);
            physics.checkRotation();
            updateAnimation();
        }
    }

    override void simulate(float deltaT) {
        super.simulate(deltaT);
        if (currentState.onAnimationEnd && currentAnimation) {
            if (engine.gameTime.current - animationStarted
                >= currentAnimation.get.getOneTimeDuration())
            {
                engine.mLog("state transition because of animation end");
                //time to change; the setState code will reset the animation
                setState(currentState.onAnimationEnd);
            }
        }
    }

    protected this (GameEngine engine, GOSpriteClass type) {
        super(engine, false);

        assert(type !is null);
        this.type = type;

        physics = new PhysicObject();
        physics.backlink = this;

        setStateForced(type.initState);

        physics.onUpdate = &physUpdate;
        physics.onImpact = &physImpact;
        physics.onDie = &physDie;
        physics.onTriggerEnter = &physTriggerEnter;
        physics.onTriggerExit =&physTriggerExit;
        engine.physicworld.add(physics);
    }
}



//state infos (per sprite class, thus it's static)
class StaticStateInfo {
    char[] name;
    POSP physic_properties;

    //automatic transition to this state if animation finished
    StaticStateInfo onAnimationEnd;
    bool noleave; //don't leave this state

    AnimationResource animation;
}

//loads "collisions"-nodes and adds them to the collision map
//loads the required animation file
//loads static physic properties (in a POSP struct)
//load static parts of the "states"-nodes
class GOSpriteClass {
    GameEngine engine;
    char[] name;

    StaticStateInfo[char[]] states;
    StaticStateInfo initState;

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
    }

    void loadFromConfig(ConfigNode config) {
        POSP[char[]] posps;

        struct FwRef {
            StaticStateInfo* patch;
            char[] name;
        }
        FwRef[] fwrefs;

        //load animation config files
        globals.resources.loadResources(config.find("require_resources"));

        //load collision map
        engine.physicworld.loadCollisions(config.getSubNode("collisions"));

        //load states
        //physic stuff is loaded when it's referenced in a state description
        foreach (ConfigNode sc; config.getSubNode("states")) {
            auto ssi = new StaticStateInfo();
            ssi.name = sc.name;
            states[ssi.name] = ssi;

            //make the first state the init state (possibly overriden by
            //"initstate" later)
            if (!initState)
                initState = ssi;

            //physic stuff, already loaded physic-types are not cached
            auto phys = config.getSubNode("physics").findNode(sc["physic"]);
            assert(phys !is null); //xxx better error handling :-)
            ssi.physic_properties.loadFromConfig(phys);

            ssi.noleave = sc.getBoolValue("noleave", false);

            if (sc["animation"].length > 0) {
                ssi.animation = globals.resources.resource!(AnimationResource)
                    (sc.getPathValue("animation"));
            }

            if (!ssi.animation) {
                engine.mLog("WARNING: no animation for state '%s'", ssi.name);
            }

            char[] onend = sc["on_animation_end"];
            if (onend.length) {
                FwRef r;
                r.name = onend;
                r.patch = &ssi.onAnimationEnd;
                fwrefs ~= r;
            }

        } //foreach state to load

        //resolve forward refs
        foreach (FwRef r; fwrefs) {
            *r.patch = findState(r.name);
        }

        StaticStateInfo* init = config["initstate"] in states;
        if (init && *init)
            initState = *init;

        //at least the constructor created a default state
        assert(initState !is null);
        assert(states.length > 0);
    }

    static this() {
        SpriteClassFactory.register!(typeof(this))("sprite_mc");
    }
}
