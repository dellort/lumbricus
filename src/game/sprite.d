module game.sprite;
import game.gobject;
import game.physic;
import game.animation;
import game.game;
import utils.vector2;
import utils.rect2;
import utils.configfile;
import utils.misc;
import utils.log;
import std.math : abs, PI;
import cmath = std.c.math;

//method how animations are chosen from object angles
enum Angle2AnimationMode {
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
private char[][] cA2AM2Str = ["simple", "twosided", "step3"];//, "noani360"];

struct SpriteAnimationInfo {
    Angle2AnimationMode ani2angle;
    Animation[] animations;

    void reset() {
        *this = (*this).init;
    }

    Animation animationFromAngle(float angle) {

        Animation getFromCAngles(int[] angles) {
            return animations[pickNearestAngle(angles, angle)];
        }

        switch (ani2angle) {
            case Angle2AnimationMode.Simple: {
                return animations ? animations[0] : null;
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

        foreach (inout Animation a; res.animations) {
            if (a) {
                a = a.getBackwards();
            }
        }

        return res;
    }

    void loadFrom(GameEngine engine, ConfigNode sc) {

        void addMirrors() {
            Animation[] nanimations;
            foreach (Animation a; animations) {
                nanimations ~= a ? a.getMirroredY() : null;
            }
            animations ~= nanimations;
        }

        ani2angle = cast(Angle2AnimationMode)
            sc.selectValueFrom("angle2animations", cA2AM2Str, 0);

        switch (ani2angle) {
            case Angle2AnimationMode.Simple, Angle2AnimationMode.Twosided: {
                //only one animation to load
                animations = [engine.findAnimation(sc["animations"])];
                addMirrors();
                break;
            }
            case Angle2AnimationMode.Step3: {
                char[] head = sc["animations"];
                static names = [cast(char[])"down", "norm", "up"];
                foreach (s; names) {
                    animations ~= engine.findAnimation(head ~ s);
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
        StateTransition st, bool reverse)
    {
        if (reverse) {
            return &st.animation;
        } else {
            return &st.animation_back;
        }
    }

    Animation getCurrentAnimation() {
        SpriteAnimationInfo* info;

        if (!currentTransition) {
            info = getAnimationInfoForState(currentState);
        } else {
            //condition checks if reverse transition
            info = getAnimationInfoForTransition(currentTransition,
                 currentTransition.from is currentState);
        }

        float angle = physics.lookey;
        return info.animationFromAngle(angle);
    }

    //update the animation to the current state and physics status
    void updateAnimation() {
        Animation anim = getCurrentAnimation();

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
        if (!scenerect.intersects(Rect2i(graphic.pos,graphic.pos+graphic.size)))
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
        //so?
    }

    protected void physDie() {
        //assume that's what we want
        if (!active)
            return;
        die();
    }

    //called when object should die
    //this implementation actually makes it dying
    //xxx: maybe add a state transition, which could be used by worm.d... hm...
    protected void die() {
        active = false;
        physics.dead = true;
        //engine.mLog("die: %s", type.name);
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
            currentTransition = null;
            engine.mLog("state transition end");
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
        graphic.setAnimation(getCurrentAnimation());
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
    void setState(StaticStateInfo nstate) {
        assert(nstate !is null);

        if (currentState is nstate)
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
        engine.physicworld.add(physics);

        graphic.setOnNoAnimation(&animationEnd);
        graphic.scene = engine.scene;
        graphic.zorder = GameZOrder.Objects;

        outOfLevel.scene = engine.scene;
        outOfLevel.zorder = GameZOrder.Objects;
        outOfLevel.paused = true;
        outOfLevel.setAnimation(type.outOfRegionArrow);
    }
}



//state infos (per sprite class, thus it's static)
class StaticStateInfo {
    char[] name;
    CollisionType collide;
    POSP physic_properties;

    StateTransition[StaticStateInfo] transitions;

    SpriteAnimationInfo animation;
}

//describe an animation which is played when switching to another state
class StateTransition {
    bool disablePhysics; //no physics while playing animation
    SpriteAnimationInfo animation, animation_back;

    //to detect if an animation must be played reverse
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

    Animation outOfRegionArrow;

    StaticStateInfo findState(char[] name) {
        StaticStateInfo* state = name in states;
        if (!state) {
            //xxx better error handling
            throw new Exception("state "~name~" not found");
        }
        return *state;
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
        outOfRegionArrow = engine.findAnimation("out_of_level_arrow");
    }

    void loadFromConfig(ConfigNode config) {
        POSP[char[]] posps;

        //load animation config files
        engine.loadAnimations(config.find("require_animations"));

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

            //load animations
            ssi.animation.loadFrom(engine, sc);

        } //foreach state to load

        StaticStateInfo* init = config["initstate"] in states;
        if (init && *init)
            initState = *init;

        //at least the constructor created a default state
        assert(initState !is null);
        assert(states.length > 0);

        //load/assign state transitions
        foreach (ConfigNode tc; config.getSubNode("state_transitions")) {
            auto trans = new StateTransition();
            auto sto = findState(tc["to"]);
            auto sfrom = findState(tc["from"]);

            trans.disablePhysics = tc.getBoolValue("disable_physics", false);

            trans.animation.loadFrom(engine, tc);

            trans.from = sfrom;
            trans.to = sto;
            sfrom.transitions[sto] = trans;

            if (tc.getBoolValue("works_reverse", false)) {
                sto.transitions[sfrom] = trans;
                //create backward animations
                trans.animation_back = trans.animation.make_reverse();
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
