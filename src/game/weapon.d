module game.weapon;

import game.gobject;
import game.animation;
import game.common;
import game.physic;
import game.game;
import game.sprite;
import utils.misc;
import utils.vector2;
import utils.mylist;
import utils.time;

package Factory!(WeaponClass, GameEngine, ConfigNode) gWeaponClassFactory;

static this() {
    gWeaponClassFactory = new typeof(gWeaponClassFactory);
}

enum WeaponWormAnimations {
    Arm,  //worm gets armed (or unarmed: animation played backwards)
    Hold, //worm holds the weapon (xxx: hardcoded to stupidness, see weapons.conf)
    Fire, //animation played while worm is shooting
    //hm, not set in the configfile; backwards animation of .Arm
    UnArm,
}
//WeaponWormAnimations -> string
const char[][] cWWA2Str = ["arm", "hold", "fire"];

//abstract weapon type; only contains generic infos about a weapon
//this includes how stuff is fired (for the code which does worm controll)
//(argument against making classes like i.e. WeaponThrowable: no multiple
// inheritance *g*; and how would you have a single fire() method then)
abstract class WeaponClass {
    protected GameEngine mEngine;

    //generally read-only fields
    char[] name; //weapon name, translateable string
    int value;  //see config file

    //NOTE: should this be moved into Shooter?
    //      (more flexible, but you had to deal with state changes)
    bool canThrow; //firing from worms direction
    bool throwAnyDirection; //false=left or right, true=360 degrees of freedom
    bool variableThrowStrength; //chooseable throw strength
    float throwStrength; //force (or whatever) if variable strength is on
    bool canPoint; //by mouse, i.e. target-searching weapon
    bool hasTimer; //user can select a timer
    Time timerFrom; //minimal time chooseable, only used if hasTimer==true
    Time timerTo;   //maximal time
    Time relaxtime;

    //xxx maybe fix this by a better animation subsystem or so
    //(because SpriteAnimationInfo was a hack for sprite.d)
    SpriteAnimationInfo*[WeaponWormAnimations.max+1] animations;

    GameEngine engine() {
        return mEngine;
    }

    this(GameEngine engine, ConfigNode node) {
        mEngine = engine;
        assert(mEngine !is null);

        name = node.name;
        value = node.getIntValue("value", 0);
        auto fire = node.findNode("firemode");
        if (fire) {
            canThrow = fire.valueIs("mode", "throw");
            throwAnyDirection = fire.valueIs("direction", "any");
            variableThrowStrength = fire.valueIs("strength_mode", "variable");
            throwStrength = fire.getFloatValue("strength_value", 0);
            hasTimer = fire.getBoolValue("timer");
            if (hasTimer) {
                //if you need finer values than seconds, hack this
                int[] vals = fire.getValueArray!(int)("timerrange");
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
            relaxtime = timeSecs(fire.getIntValue("relaxtime", 0));
            canPoint = fire.getBoolValue("canpoint", false);
        }

        foreach (inout SpriteAnimationInfo* ani; animations) {
            ani = allocSpriteAnimationInfo();
        }

        //load the transition animations
        auto anis = node.getSubNode("animation");
        foreach (int i, char[] name; cWWA2Str) {
            auto sub = anis.findNode(name);
            if (sub) {
                animations[i].loadFrom(engine, sub);
            }
        }
        //if (animations[WeaponWormAnimations.Arm]) {
            animations[WeaponWormAnimations.UnArm]
                = allocSpriteAnimationInfo;
            *animations[WeaponWormAnimations.UnArm]
                = animations[WeaponWormAnimations.Arm].make_reverse();
        //}
    }

    //just a factory
    //users call fire() on them to actually activate them
    abstract Shooter createShooter();
}

//for Shooter.fire(FireInfo)
struct FireInfo {
    PhysicObject shootby; //maybe need shooter position, size and velocity
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

    protected this(WeaponClass base, GameEngine engine) {
        super(engine, false);
        assert(base !is null);
        mClass = base;
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
