module game.weapon.weapon;

import game.gobject;
import game.animation;
import framework.framework;
import framework.resset;
import physics.world;
import game.game;
import game.sprite;
import utils.misc;
import utils.vector2;
import utils.mylist;
import utils.time;
import utils.factory;

static class WeaponClassFactory
    : StaticFactory!(WeaponClass, GameEngine, ConfigNode)
{
}

enum WeaponWormAnimations {
    Arm,  //worm gets armed (or unarmed: animation played backwards)
    Hold, //worm holds the weapon
    Fire, //animation played while worm is shooting
}
//WeaponWormAnimations -> string
const char[][] cWWA2Str = ["arm", "hold", "fire"];

enum PointMode {
    none,
    target,
    instant
}

struct FireMode {
    //needed by both client and server (server should verify with this data)
    bool canThrow; //firing from worms direction
    bool throwAnyDirection; //false=left or right, true=360 degrees of freedom
    bool variableThrowStrength; //chooseable throw strength
    //if variableThrowStrength is true, FireInfo.strength is interpolated
    //between From and To by a player chosen value (that fire strength thing)
    float throwStrengthFrom = 1;
    float throwStrengthTo = 1;
    PointMode point = PointMode.none; //by mouse, i.e. target-searching weapon
    bool hasTimer; //user can select a timer
    Time timerFrom; //minimal time chooseable, only used if hasTimer==true
    Time timerTo;   //maximal time
    Time relaxtime;


    void loadFromConfig(ConfigNode node) {
        canThrow = node.valueIs("mode", "throw");
        throwAnyDirection = node.valueIs("direction", "any");
        variableThrowStrength = node.valueIs("strength_mode", "variable");
        if (node.hasValue("strength_value")) {
            //for "compatibility" only
            throwStrengthFrom = throwStrengthTo =
                node.getFloatValue("strength_value");
        } else {
            throwStrengthFrom = node.getFloatValue("strength_from",
                throwStrengthFrom);
            throwStrengthTo = node.getFloatValue("strength_to",
                throwStrengthTo);
        }
        hasTimer = node.getBoolValue("timer");
        if (hasTimer) {
            //if you need finer values than seconds, hack this
            int[] vals = node.getValueArray!(int)("timerrange");
            if (vals.length == 2) {
                timerFrom = timeSecs(vals[0]);
                timerTo = timeSecs(vals[1]);
            } else if (vals.length == 1) {
                timerFrom = timeSecs(0);
                timerTo = timeSecs(vals[0]);
            } else {
                //xxx what about some kind of error reporting?
                hasTimer = false;
            }
        }
        relaxtime = timeSecs(node.getIntValue("relaxtime", 0));
        char[] pm = node.getStringValue("point");
        switch (pm) {
            case "target":
                point = PointMode.target;
                break;
            case "instant":
                point = PointMode.instant;
                break;
            default:
        }
    }
}

//abstract weapon type; only contains generic infos about a weapon
//this includes how stuff is fired (for the code which does worm controll)
//(argument against making classes like i.e. WeaponThrowable: no multiple
// inheritance *g*; and how would you have a single fire() method then)
abstract class WeaponClass {
    protected GameEngine mEngine;

    //generally read-only fields
    char[] name; //weapon name, translateable string
    int value;  //see config file
    char[] category; //category-id for this weapon

    //for the weapon selection; only needed on client-side
    Resource!(Surface) icon;

    FireMode fireMode;

    //weapon-holding animations
    char[][WeaponWormAnimations.max+1] animations;

    GameEngine engine() {
        return mEngine;
    }

    this(GameEngine engine, ConfigNode node) {
        mEngine = engine;
        assert(mEngine !is null);

        name = node.name;
        value = node.getIntValue("value", 0);
        category = node.getStringValue("category", "none");

        icon = engine.resources.resource!(Surface)(node["icon"]);

        auto fire = node.findNode("firemode");
        if (fire) {
            fireMode.loadFromConfig(fire);
        }

        //load the transition animations
        auto anis = node.getSubNode("animation");
        foreach (int i, char[] name; cWWA2Str) {
            auto val = anis.findValue(name);
            if (val) {
                animations[i] =val.value;
            }
        }

        //load projectiles
        foreach (ConfigNode pr; node.getSubNode("projectiles")) {
            //if (pr.name in projectiles)
            //    throw new Exception("projectile already exists: "~pr.name);
            //instantiate a sprite class
            //xxx error handling?
            auto spriteclass = engine.instantiateSpriteClass(pr["type"], pr.name);
            //projectiles[pr.name] = spriteclass;

            spriteclass.loadFromConfig(pr);
        }
    }

    //just a factory
    //users call fire() on them to actually activate them
    //  go == entity which fires it (its physical properties will be used)
    abstract Shooter createShooter(GObjectSprite go);
}

//for Shooter.fire(FireInfo)
struct FireInfo {
    Vector2f dir = Vector2f.nan; //normalized throw direction
    float strength = 1.0f; //as allowed in the weapon config
    Time timer;     //selected time, in the range dictated by the weapon
    Vector2f pointto = Vector2f.nan; //if weapon can point to somewhere
}

//simulate the firing of a weapon; i.e. create projectiles and so on
//also simulates whatever is going on for special weapons (i.e. earth quakes)
//always created by WeaponClass.createShooter()
//practically a factory for projectiles *g* (mostly, but not necessarily)
//projectiles can work completely independend from this class
class Shooter : GameObject {
    protected WeaponClass mClass;
    protected GObjectSprite owner;

    protected this(WeaponClass base, GObjectSprite a_owner, GameEngine engine) {
        super(engine, false);
        assert(base !is null);
        mClass = base;
        owner = a_owner;
    }

    public WeaponClass weapon() {
        return mClass;
    }

    abstract void fire(FireInfo info);

    //required for nasty weapons like guns which keep you from doing useful
    //things like running away
    bool isFixed() {
        return isFiring();
    }

    //often the worm can change shooting direction while the weapon still fires
    //if this returns true, calls to readjust() are allowed (??)
    bool canReAdjust() {
        return !isFiring();
    }

    void readjust(FireInfo info) {
    }

    //used by a worm to notify that the worm was interrupted while firing
    //for some weapons, this won't do anything, i.e. air strikes, earth quakes...
    //after this, isFiring() will return false (mostly...)
    void interruptFiring() {
        //default implementation: make inactive
        active = false;
    }

    //if this class still thinks the worm is i.e. shooting projectiles
    //weapons like earth quakes might still be active but return false
    //invariant: isFiring() => active()
    bool isFiring() {
        //default implementation: link with activity
        return active;
    }
}
