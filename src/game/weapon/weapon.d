module game.weapon.weapon;

import game.gobject;
import game.animation;
import framework.framework;
import framework.resset;
import physics.world;
import game.game;
import game.sprite;
import game.weapon.types;
import utils.misc;
import utils.vector2;
import utils.time;
import utils.factory;
import utils.reflection;
import utils.configfile;

import game.gamepublic;

static class WeaponClassFactory
    : StaticFactory!(WeaponClass, GameEngine, ConfigNode)
{
}

alias void delegate(Shooter sh) ShooterCallback;

class WrapFireInfo { //wee so Java like
    FireInfo info;
    this (ReflectCtor c) {
    }
    this () {
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
    int value = 0;  //see config file
    char[] category = "none"; //category-id for this weapon
    bool isAirstrike = false; //needed to exlude it from cave levels
    bool allowSecondary = false;  //allow selecting and firing a second
                                  //weapon while active
    bool dontEndRound = false;

    //for the weapon selection; only needed on client-side
    Resource!(Surface) icon;

    FireMode fireMode;

    //weapon-holding animations
    char[][WeaponWormAnimations.max+1] animations;

    //cached hack
    WeaponHandle handle;

    GameEngine engine() {
        return mEngine;
    }

    this(GameEngine engine, ConfigNode node) {
        mEngine = engine;
        assert(mEngine !is null);

        name = node.name;
        value = node.getIntValue("value", value);
        category = node.getStringValue("category", category);
        isAirstrike = node.getBoolValue("airstrike", isAirstrike);
        allowSecondary = node.getBoolValue("allow_secondary", allowSecondary);
        dontEndRound = node.getBoolValue("dont_end_round", dontEndRound);

        icon = engine.gfx.resources.resource!(Surface)(node["icon"]);

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

        handle = new WeaponHandle();
        handle.name = name;
        handle.icon = icon;
        handle.value = value;
        handle.category = category;
    }

    //xxx class
    this (ReflectCtor c) {
    }

    //just a factory
    //users call fire() on them to actually activate them
    //  go == entity which fires it (its physical properties will be used)
    abstract Shooter createShooter(GObjectSprite go);
}

//for Shooter.fire(FireInfo)
struct FireInfo {
    Vector2f dir = Vector2f.nan; //normalized throw direction
    Vector2f surfNormal = Vector2f(-1, 0);   //impact surface normal
    float strength = 1.0f; //as allowed in the weapon config
    Time timer;     //selected time, in the range dictated by the weapon
    Vector2f pos;     //position of shooter
    float shootbyRadius = 0.0f;
    Vector2f pointto = Vector2f.nan; //if weapon can point to somewhere
}

//simulate the firing of a weapon; i.e. create projectiles and so on
//also simulates whatever is going on for special weapons (i.e. earth quakes)
//always created by WeaponClass.createShooter()
//practically a factory for projectiles *g* (mostly, but not necessarily)
//projectiles can work completely independend from this class
abstract class Shooter : GameObject {
    protected WeaponClass mClass;
    protected GObjectSprite owner;
    private bool mWorking;   //only for finishCb event

    //shooters should call this to reduce owner's ammo by 1
    ShooterCallback ammoCb, finishCb;

    protected this(WeaponClass base, GObjectSprite a_owner, GameEngine engine) {
        super(engine, false);
        assert(base !is null);
        mClass = base;
        owner = a_owner;
    }

    this (ReflectCtor c) {
        super(c);
    }

    protected void reduceAmmo() {
        if (ammoCb)
            ammoCb(this);
    }

    protected void finished() {
        if (!mWorking)
            return;
        mWorking = false;
        if (finishCb)
            finishCb(this);
    }

    bool delayedAction() {
        return activity;
    }

    public WeaponClass weapon() {
        return mClass;
    }

    //fire (i.e. activate) weapon
    final void fire(FireInfo info) {
        assert(!activity);
        mWorking = true;
        doFire(info);
    }

    //fire again (i.e. trigger special actions, like deactivating)
    final bool refire() {
        assert(activity);
        return doRefire();
    }

    abstract protected void doFire(FireInfo info);

    protected bool doRefire() {
        return false;
    }

    //required for nasty weapons like guns which keep you from doing useful
    //things like running away
    bool isFixed() {
        return isFiring();
    }

    //often the worm can change shooting direction while the weapon still fires
    void readjust(Vector2f dir) {
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
        return activity;
    }
}
