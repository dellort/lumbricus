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

    private Animation mCurrentAnimation;
    private StaticStateInfo mCurrentAnimationState;
    private float mCurrentAnimationAngle;

    //this function does its own caching and can be overriden to pick custom
    //animations
    Animation getCurrentAnimation() {
        float angle = physics.lookey;

        if (mCurrentAnimationState !is currentState
            || mCurrentAnimationAngle != angle)
        {
            mCurrentAnimation = currentState.animation.animationFromAngle(angle);
            mCurrentAnimationState = currentState;
            mCurrentAnimationAngle = angle;
        }
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
    void setPos(Vector2i pos) {
        physics.pos = toVector2f(pos);
        physUpdate();
    }

    //do as less as necessary to force a new state
    void setStateForced(StaticStateInfo nstate) {
        assert(nstate !is null);

        currentState = nstate;
        physics.collision = nstate.collide;
        physics.posp = nstate.physic_properties;
        graphic.setAnimation(getCurrentAnimation());
    }

    //do a (possibly) soft transition to the new state
    //explictely no-op if same state as currently is set.
    void setState(StaticStateInfo nstate) {
        assert(nstate !is null);

        if (currentState is nstate)
            return;

        controller.mLog("state %s -> %s", currentState.name, nstate.name);

        currentState = nstate;
        physics.collision = nstate.collide;
        physics.posp = nstate.physic_properties;

        updateAnimation();
    }

    //never returns null
    StaticStateInfo findState(char[] name) {
        StaticStateInfo* state = name in type.states;
        assert(state !is null); //xxx better error handling
        return *state;
    }

    this (GameController controller, GOSpriteClass type) {
        super(controller);

        assert(type !is null);
        this.type = type;

        physics = new PhysicObject();
        graphic = new Animator();

        setStateForced(type.initState);

        physics.onUpdate = &physUpdate;
        physics.onImpact = &physImpact;
        physics.onDie = &physDie;

        controller.physicworld.add(physics);

        graphic.setScene(controller.scene, GameZOrder.Objects);
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

    void loadFrom(GameController controller, ConfigNode sc) {

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
                animations = [controller.findAnimation(sc["animations"])];
                addMirrors();
                break;
            }
            case Angle2AnimationMode.Step3: {
                char[] head = sc["animations"];
                static names = [cast(char[])"down", "norm", "up"];
                foreach (s; names) {
                    animations ~= controller.findAnimation(head ~ s);
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

    SpriteAnimationInfo animation;
}

//loads "collisions"-nodes and adds them to the collision map
//loads the required animation file
//loads static physic properties (in a POSP struct)
//load static parts of the "states"-nodes
class GOSpriteClass {
    GameController controller;
    ConfigNode config;

    StaticStateInfo[char[]] states;
    StaticStateInfo initState;

    this (GameController controller, ConfigNode config) {
        POSP[char[]] posps;

        this.controller = controller;
        this.config = config;

        //load the stuff...

        //load animation config files
        controller.loadAnimations(config.find("require_animations"));

        //load collision map
        controller.loadCollisions(config.getSubNode("collisions"));

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
            ssi.collide = controller.findCollisionID(sc["collide"], true);

            //physic stuff, already loaded physic-types are not cached
            auto phys = config.getSubNode("physics").findNode(sc["physic"]);
            assert(phys !is null); //xxx better error handling :-)
            loadPOSP(phys, ssi.physic_properties);

            //load animations
            ssi.animation.loadFrom(controller, sc);

        } //foreach state to load

        StaticStateInfo* init = config["initstate"] in states;
        if (init)
            initState = *init;
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

float realmod(float a, float b) {
    return cmath.fmodf(cmath.fmodf(a, b) + b, b);
}

//return the index of the angle in "angles" which is closest to "angle"
//for unknown reasons, angles[] is in degrees, while angle is in radians
private uint pickNearestAngle(int[] angles, float angle) {
    //whatever
    float angle_dist(float a, float b) {
        return abs(realmod(a, PI*2) - realmod(b, PI*2));
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
