module game.sprite;
import game.gobject;
import game.physic;
import game.animation;
import game.game;
import game.common;
import utils.vector2;
import utils.rect2;
import utils.configfile;
import utils.misc;
import utils.log;
import std.math : abs, PI;
import cmath = std.c.math;
import utils.factory;

//factory to instantiate sprite classes, this is a small wtf
package Factory!(GOSpriteClass, GameEngine, char[]) gSpriteClassFactory;

static this() {
    gSpriteClassFactory = new typeof(gSpriteClassFactory);
    gSpriteClassFactory.register!(GOSpriteClass)("sprite_mc");
}

package void registerSpriteClass(T : GOSpriteClass)(char[] name) {
    mSpriteClassFactory.register(T)(name);
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

    //animation played when doing state transition...
    StateTransition currentTransition;

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
        return cast(int)(realmod((-angle+PI/2*3)/PI*180.0f, 360));
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

    //called when current animation is finished
    protected void animationEnd(Animator sender) {
        if (currentTransition) {
            //end the transition
            if (currentTransition.disablePhysics) {
                physics.posp.fixate = currentState.physic_properties.fixate;
            }
            engine.mLog("state transition end (%s -> %s)",
                currentTransition.from.name, currentTransition.to.name);
            assert(currentState is currentTransition.to);
            currentTransition = null;
            updateAnimation();
            transitionEnd();
        }
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
    //and state transition will have been just started
    //must not call setState (alone danger for recursion forbids it)
    protected void stateTransition(StaticStateInfo from, StaticStateInfo to) {
    }

    //if the transition animation to the current state has finished
    //not called if the transition animation was canceled
    //when called, currentTransition should be null, and new animation was set
    protected void transitionEnd() {
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

        StateTransition* transp = nstate in currentState.transitions;
        StateTransition trans = transp ? *transp : null;

        engine.mLog("state %s -> %s%s", currentState.name, nstate.name,
            trans ? " (with transition)" : "");

        auto oldstate = currentState;
        currentState = nstate;
        physics.posp = nstate.physic_properties;

        currentTransition = trans;
        if (trans) {
            assert(oldstate is trans.from);
            assert(currentState is trans.to);
            if (trans.disablePhysics) {
                //don't allow any move
                physics.posp.fixate = Vector2f(0);
            }
        }

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
            updateAnimation();
        }
    }

    protected this (GameEngine engine, GOSpriteClass type) {
        super(engine, false);

        assert(type !is null);
        this.type = type;

        physics = new PhysicObject();

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

    StateTransition[StaticStateInfo] transitions;
    bool noleave; //don't leave this state

    AnimationResource animation;
}

//describe an animation which is played when switching to another state
class StateTransition {
    bool disablePhysics; //no physics while playing animation

    StaticStateInfo from, to;
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

        //load animation config files
        globals.resources.loadResources(config.find("require_resources"));

        //load collision map
        engine.loadCollisions(config.getSubNode("collisions"));

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
            loadPOSPFromConfig(phys, ssi.physic_properties,
                &engine.findCollisionID);

            ssi.noleave = sc.getBoolValue("noleave", false);

            if (sc["animation"].length > 0) {
                ssi.animation = globals.resources.resource!(AnimationResource)
                    (sc.getPathValue("animation"));
            }

            if (!ssi.animation) {
                engine.mLog("no animation for state '%s'", ssi.name);
            }

        } //foreach state to load

        StaticStateInfo* init = config["initstate"] in states;
        if (init && *init)
            initState = *init;

        //at least the constructor created a default state
        assert(initState !is null);
        assert(states.length > 0);

        //load/assign state transitions
        StateTransition newTransition(StaticStateInfo sfrom,
            StaticStateInfo sto, ConfigNode tc)
        {
            auto trans = new StateTransition();

            trans.disablePhysics = tc.getBoolValue("disable_physics", false);

            trans.from = sfrom;
            trans.to = sto;
            sfrom.transitions[sto] = trans;

            return trans;
        }
        foreach (ConfigNode tc; config.getSubNode("state_transitions")) {
            auto sto = findState(tc["to"]);
            if (tc.getBoolValue("from_any")) {
                foreach (StaticStateInfo s; states) {
                    if (s !is sto) {
                        newTransition(s, sto, tc);
                    }
                }
            } else {
                auto sfrom = findState(tc["from"]);
                newTransition(sto, sfrom, tc);

                if (tc.getBoolValue("works_reverse", false)) {
                    auto trans = newTransition(sfrom, sto, tc);
                    //create backward animations
                    //(removed)
                }
            }
        }
    }
}
