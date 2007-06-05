module game.sprite;
import game.gobject;
import game.physic;
import game.animation;
import game.game;
import utils.vector2;
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
}
//Angle2AnimationMode -> name-string (as used in config file)
private char[][] cA2AM2Str = ["simple", "twosided", "step3"];

//object which represents a PhysicObject and an animation on the screen
//also provides loading from ConfigFiles and state managment
class GObjectSprite : GameObject {
    GOSpriteClass type;
    StaticStateInfo currentState; //must not be null

    PhysicObject physics;
    Animator graphic;

    /+
    private Animation mCurrentAnimation;
    private StaticStateInfo mCurrentAnimationState;
    private float mCurrentAnimationAngle;
    +/

    //animation played when doing state transition...
    StateTransition currentTransition;

    //this function does its own caching and can be overriden to pick custom
    //animations
    Animation getCurrentAnimation() {
        SpriteAnimationInfo* info = &currentState.animation;

        if (currentTransition) {
            //condition checks if reverse transition
            if (currentTransition.to is currentState) {
                info = &currentTransition.animation;
            } else {
                info = &currentTransition.animation_back;
            }
        }

        float angle = physics.lookey;

        /+
        if (mCurrentAnimationState !is currentState
            || mCurrentAnimationAngle != angle)
        {
        +/
            auto
            mCurrentAnimation = info.animationFromAngle(angle);
        /+
            mCurrentAnimationState = currentState;
            mCurrentAnimationAngle = angle;
        }
        +/
        return mCurrentAnimation;
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
    }

    protected void physImpact(PhysicBase other) {
        //so?
    }

    protected void physDie() {
        //what to do? remove ourselves from the game?
        graphic.active = false;
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

    this (GameEngine engine, GOSpriteClass type) {
        super(engine);

        assert(type !is null);
        this.type = type;

        physics = new PhysicObject();
        graphic = new Animator();

        setStateForced(type.initState);

        physics.onUpdate = &physUpdate;
        physics.onImpact = &physImpact;
        physics.onDie = &physDie;
        engine.physicworld.add(physics);

        graphic.setOnNoAnimation(&animationEnd);
        graphic.setScene(engine.scene, GameZOrder.Objects);
    }
}

struct SpriteAnimationInfo {
    Angle2AnimationMode ani2angle;
    Animation[] animations;

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
    ConfigNode config;

    StaticStateInfo[char[]] states;
    StaticStateInfo initState;

    StaticStateInfo findState(char[] name) {
        StaticStateInfo* state = name in states;
        if (!state) {
            //xxx better error handling
            throw new Exception("state "~name~" not found");
        }
        return *state;
    }

    this (GameEngine engine, ConfigNode config) {
        POSP[char[]] posps;

        this.engine = engine;
        this.config = config;

        //load the stuff...

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
            loadPOSP(phys, ssi.physic_properties);

            //load animations
            ssi.animation.loadFrom(engine, sc);

        } //foreach state to load

        StaticStateInfo* init = config["initstate"] in states;
        if (init)
            initState = *init;

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
                trans.animation_back.ani2angle = trans.animation.ani2angle;
                auto anis = trans.animation.animations.dup;
                foreach (inout Animation a; anis) {
                    if (a) {
                        a = a.getBackwards();
                    }
                }
                trans.animation_back.animations = anis;
            }
        }
    }
}

//should be moved?
void loadPOSP(ConfigNode node, inout POSP posp) {
    //xxx: maybe replace by tuples, if that should be possible
    posp.elasticity = node.getFloatValue("elasticity", posp.elasticity);
    posp.radius = node.getFloatValue("radius", posp.radius);
    posp.mass = node.getFloatValue("mass", posp.mass);
    posp.windInfluence = node.getFloatValue("wind_influence",
        posp.windInfluence);
    posp.explosionInfluence = node.getFloatValue("explosion_influence",
        posp.explosionInfluence);
    posp.fixate = readVector(node.getStringValue("fixate", str.format("%s %s",
        posp.fixate.x, posp.fixate.y)));
    posp.glueForce = node.getFloatValue("glue_force", posp.glueForce);
    posp.walkingSpeed = node.getFloatValue("walking_speed", posp.walkingSpeed);
    posp.walkingClimb = node.getFloatValue("walking_climb", posp.walkingClimb);
}

//xxx duplicated from generator.d
private Vector2f readVector(char[] s) {
    char[][] items = str.split(s);
    if (items.length != 2) {
        throw new Exception("invalid point value");
    }
    Vector2f pt;
    pt.x = conv.toFloat(items[0]);
    pt.y = conv.toFloat(items[1]);
    return pt;
}

//return the index of the angle in "angles" which is closest to "angle"
//for unknown reasons, angles[] is in degrees, while angle is in radians
private uint pickNearestAngle(int[] angles, float angle) {
    //whatever
    float angle_dist(float a, float b) {
        //assume angles already are mod PI*2
        auto r = abs(a - b); //abs(realmod(a, PI*2) - realmod(b, PI*2));
        if (r > PI) {
            r = PI*2 - r;
        }
        return r;
    }

    //pick best angle (what's nearer)
    uint closest;
    float cur = float.max;
    foreach (int i, int x; angles) {
        auto d = angle_dist(angle,x/180.0f*PI);
        if (d < cur) {
            cur = d;
            closest = i;
        }
    }
    return closest;
}
