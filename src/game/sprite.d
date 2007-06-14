module game.sprite;
import game.gobject;
import game.physic;
import game.animation;
import game.game;
import game.common;
import game.resources;
import utils.vector2;
import utils.rect2;
import utils.configfile;
import utils.misc;
import utils.log;
import std.math : abs, PI;
import cmath = std.c.math;

//factory to instantiate sprite classes, this is a small wtf
package Factory!(GOSpriteClass, GameEngine, char[]) gSpriteClassFactory;

static this() {
    gSpriteClassFactory = new typeof(gSpriteClassFactory);
    gSpriteClassFactory.register!(GOSpriteClass)("sprite_mc");
}

package void registerSpriteClass(T : GOSpriteClass)(char[] name) {
    mSpriteClassFactory.register(T)(name);
}

//method how animations are chosen from object angles
enum Angle2AnimationMode {
    None,
    //One animation for all angles
    Simple,
    //Only one animation, but which is mirrored on the Y axis
    // => 2 possible states, looking into degrees 0 and 180
    Twosided,
    //Worm-like mapping of angles to animations
    //There are 6 45 degree rotated animations, 3 of them mirrored on the Y
    //axis, and the code will add "up", "down" and "norm" to the value of the
    //"animations" field (from the config file) to get the animation names.
    //No animations for directly looking up or down (on the Y axis).
    Step3,
    /+
    //Not an animation; instead, each frame shows a specific angle, starting
    //from 270 degrees
    Noani360,
    +/
}
//Angle2AnimationMode -> name-string (as used in config file)
private char[][] cA2AM2Str = ["none", "simple", "twosided", "step3"];//, "noani360"];

//whacky hacky
SpriteAnimationInfo* allocSpriteAnimationInfo() {
    return new SpriteAnimationInfo;
}

struct SpriteAnimationInfo {
    Angle2AnimationMode ani2angle;
    AnimationResource[] animations;

    bool noAnimation() {
        return ani2angle == Angle2AnimationMode.None;
    }

    void reset() {
        *this = (*this).init;
    }

    AnimationResource animationFromAngle(float angle) {

        AnimationResource getFromCAngles(int[] angles) {
            return animations[pickNearestAngle(angles, angle)];
        }

        switch (ani2angle) {
            case Angle2AnimationMode.None: {
                return null;
            }
            case Angle2AnimationMode.Simple: {
                return animations[0];
            }
            case Angle2AnimationMode.Twosided: {
                //Hint: array literals allocate memory
                static int[] angles = [180, 0];
                return getFromCAngles(angles);
            }
            case Angle2AnimationMode.Step3: {
                static int[] angles = [90+45,90+90,90+135,90-45,90-90,90-135];
                return getFromCAngles(angles);
            }
            default:
                assert(false);
        }
    }

    //return a backward animation
    SpriteAnimationInfo make_reverse() {
        SpriteAnimationInfo res;

        res = *this;
        res.animations = res.animations.dup;

        foreach (inout AnimationResource a; res.animations) {
            if (a) {
                a = globals.resources.createProcessedAnimation(a.id,
                    a.id~"_backwards",true,false);
            }
        }

        return res;
    }

    void loadFrom(GameEngine engine, ConfigNode sc) {

        void addMirrors() {
            AnimationResource[] nanimations;
            foreach (AnimationResource a; animations) {
                nanimations ~= a ? globals.resources.createProcessedAnimation(
                    a.id,a.id~"_mirrored",false,true) : null;
            }
            animations ~= nanimations;
        }

        ani2angle = cast(Angle2AnimationMode)
            sc.selectValueFrom("angle2animations", cA2AM2Str, 0);

        switch (ani2angle) {
            case Angle2AnimationMode.None: {
                //NOTE: but maybe still should check for accidental no-animation
                break;
            }
            case Angle2AnimationMode.Simple, Angle2AnimationMode.Twosided: {
                //only one animation to load
                animations = [globals.resources.anims(sc["animations"])];
                addMirrors();
                break;
            }
            case Angle2AnimationMode.Step3: {
                char[] head = sc["animations"];
                static names = [cast(char[])"down", "norm", "up"];
                foreach (s; names) {
                    animations ~= globals.resources.anims(head ~ s);
                }
                addMirrors();
                break;
            }
            default:
                assert(false);
        }
    }
}


//object which represents a PhysicObject and an animation on the screen
//also provides loading from ConfigFiles and state managment
class GObjectSprite : GameObject {
    GOSpriteClass type;
    StaticStateInfo currentState; //must not be null

    PhysicObject physics;
    Animator graphic;
    Animator outOfLevel;

    //animation played when doing state transition...
    StateTransition currentTransition;

    //return animations for states; this can be used to "patch" animations for
    //specific states (used for worm.d/weapons)
    protected SpriteAnimationInfo* getAnimationInfoForState(StaticStateInfo info)
    {
        return &info.animation;
    }
    protected SpriteAnimationInfo* getAnimationInfoForTransition(
        StateTransition st)
    {
        return &st.animation;
    }

    AnimationResource getCurrentAnimation() {
        SpriteAnimationInfo* info;

        if (!currentTransition) {
            info = getAnimationInfoForState(currentState);
        } else {
            info = getAnimationInfoForTransition(currentTransition);
        }

        float angle = physics.lookey;
        return info.animationFromAngle(angle);
    }

    //update the animation to the current state and physics status
    void updateAnimation() {
        AnimationResource r = getCurrentAnimation();
        Animation anim = null;
        if (r)
            anim = r.get();

        Vector2i anim_size = anim ? anim.size : Vector2i(0);
        graphic.pos = toVector2i(physics.pos) - anim_size/2;

        if (graphic.currentAnimation !is anim) {
            //xxx: or use setNextAnimation()? or make it configureable?
            graphic.setAnimation(anim);
        }
    }

    protected void physUpdate() {
        updateAnimation();

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
        physics.collision = nstate.collide;
        physics.posp = nstate.physic_properties;
        graphic.setAnimation(getCurrentAnimation().get());

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
        physics.collision = nstate.collide;
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
        graphic.active = active;
        if (!active)
            outOfLevel.active = false;
    }

    protected this (GameEngine engine, GOSpriteClass type) {
        super(engine, false);

        assert(type !is null);
        this.type = type;

        physics = new PhysicObject();
        graphic = new Animator();
        outOfLevel = new Animator();

        setStateForced(type.initState);

        physics.onUpdate = &physUpdate;
        physics.onImpact = &physImpact;
        physics.onDie = &physDie;
        physics.onTriggerEnter = &physTriggerEnter;
        physics.onTriggerExit =&physTriggerExit;
        engine.physicworld.add(physics);

        graphic.setOnNoAnimation(&animationEnd);
        graphic.scene = engine.scene;
        graphic.zorder = GameZOrder.Objects;

        outOfLevel.scene = engine.scene;
        outOfLevel.zorder = GameZOrder.Objects;
        outOfLevel.paused = true;
        outOfLevel.setAnimation(type.outOfRegionArrow.get());
    }
}



//state infos (per sprite class, thus it's static)
class StaticStateInfo {
    char[] name;
    CollisionType collide;
    POSP physic_properties;

    StateTransition[StaticStateInfo] transitions;
    bool noleave; //no leaving transitions

    SpriteAnimationInfo animation;
}

//describe an animation which is played when switching to another state
class StateTransition {
    bool disablePhysics; //no physics while playing animation
    SpriteAnimationInfo animation;

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

    AnimationResource outOfRegionArrow;

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

        //hardcoded and stupid, sorry
        outOfRegionArrow = globals.resources.anims("out_of_level_arrow");
    }

    void loadFromConfig(ConfigNode config) {
        POSP[char[]] posps;

        //load animation config files
        globals.resources.loadAnimations(config.find("require_animations"));

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

            //xxx: passes true for the second parameter, which means the ID
            //     is created if it doesn't exist; this is for forward
            //     referencing... it should be replaced by collision classes
            ssi.collide = engine.findCollisionID(sc["collide"], true);

            //physic stuff, already loaded physic-types are not cached
            auto phys = config.getSubNode("physics").findNode(sc["physic"]);
            assert(phys !is null); //xxx better error handling :-)
            loadPOSPFromConfig(phys, ssi.physic_properties);

            ssi.noleave = sc.getBoolValue("noleave", false);

            //load animations
            ssi.animation.loadFrom(engine, sc);

            if (ssi.animation.noAnimation) {
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

            trans.animation.loadFrom(engine, tc);

            if (trans.animation.noAnimation) {
                engine.mLog("no animation for transition '%s' -> '%s'",
                    sfrom.name, sto.name);
            }

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
                    trans.animation = trans.animation.make_reverse();
                }
            }
        }
    }
}

//return the index of the angle in "angles" which is closest to "angle"
//for unknown reasons, angles[] is in degrees, while angle is in radians
private uint pickNearestAngle(int[] angles, float angle) {
    //pick best angle (what's nearer)
    uint closest;
    float cur = float.max;
    foreach (int i, int x; angles) {
        auto d = angleDistance(angle,x/180.0f*PI);
        if (d < cur) {
            cur = d;
            closest = i;
        }
    }
    return closest;
}
