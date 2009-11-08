module game.weapon.weapon;

import game.gobject;
import game.animation;
import framework.framework;
import common.resset;
import physics.world;
import game.game;
import game.gfxset;
import game.sprite;
import game.weapon.types;
import utils.misc;
import utils.vector2;
import utils.time;
import utils.factory;
import utils.reflection;
import utils.serialize;
import utils.configfile;
import utils.log;

import tango.util.Convert : to;

import game.gamepublic;

alias StaticFactory!("WeaponClasses", WeaponClass, GfxSet, ConfigNode)
    WeaponClassFactory;

alias StaticFactory!("WeaponSelectors", WeaponSelector, WeaponClass,
    GObjectSprite) WeaponSelectorFactory;

alias void delegate(Shooter sh) ShooterCallback;

//wtf? why not make FireInfo a class?
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
    protected GfxSet mGfx;

    //generally read-only fields
    char[] name; //weapon name, translateable string
    int value = 0;  //see config file
    char[] category = "none"; //category-id for this weapon
    bool isAirstrike = false; //needed to exlude it from cave levels
    bool allowSecondary = false;  //allow selecting and firing a second
                                  //weapon while active
    bool dontEndRound = false;
    bool deselectAfterFire = false;
    Time cooldown = Time.Null;

    //for the weapon selection; only needed on client-side
    Surface icon;

    FireMode fireMode;

    //argument to WeaponSelectorFactory
    char[] onSelect;

    //weapon-holding animations
    char[] animation;

    GfxSet gfx() {
        return mGfx;
    }

    this(GfxSet gfx, ConfigNode node) {
        mGfx = gfx;
        assert(gfx !is null);

        name = node.name;
        value = node.getIntValue("value", value);
        category = node.getStringValue("category", category);
        isAirstrike = node.getBoolValue("airstrike", isAirstrike);
        allowSecondary = node.getBoolValue("allow_secondary", allowSecondary);
        dontEndRound = node.getBoolValue("dont_end_round", dontEndRound);
        deselectAfterFire = node.getBoolValue("deselect", deselectAfterFire);
        cooldown = node.getValue("cooldown", cooldown);

        icon = gfx.resources.get!(Surface)(node["icon"]);

        auto fire = node.findNode("firemode");
        if (fire) {
            fireMode.loadFromConfig(fire);
        }

        //load the animations
        animation = node["animation"];

        onSelect = node.getValue!(char[])("on_select", "");
        if (onSelect.length) {
            if (!WeaponSelectorFactory.exists(onSelect))
                throw new Exception("not in WeaponSelectorFactory: "~onSelect);
        }

        //load projectiles
        foreach (ConfigNode pr; node.getSubNode("projectiles")) {
            //if (pr.name in projectiles)
            //    throw new Exception("projectile already exists: "~pr.name);
            //instantiate a sprite class
            //xxx error handling?
            auto spriteclass = gfx.instantiateSpriteClass(pr["type"], pr.name);
            //projectiles[pr.name] = spriteclass;

            spriteclass.loadFromConfig(pr);
        }
    }

    //xxx class
    this (ReflectCtor c) {
    }

    //called when the sprite selected_by selects this weapon
    //this is needed when you want to have somewhat more control over the how
    //  a weapon is _prepared_ to fire
    //may return null
    //xxx: and actually, the hardcoded FireMode thing sucks a bit
    WeaponSelector createSelector(GObjectSprite selected_by) {
        if (!onSelect.length)
            return null;
        return WeaponSelectorFactory.instantiate(onSelect, this, selected_by);
    }

    //just a factory
    //users call fire() on them to actually activate them
    //  go == entity which fires it (its physical properties will be used)
    abstract Shooter createShooter(GObjectSprite go, GameEngine engine);

    bool canUse(GameEngine engine) {
        return !isAirstrike || engine.level.airstrikeAllow;
    }
}

//some weapons need to do stuff while they're selected (girder construction)
//this really should be in Shooter, but Shooter is only created right before
//  the weapon is fired, and much code relies on this; too messy to change
//note that this is not created by a "double factory"; you can use the passed
//  WeaponClass to store data
//as far as I see, a worm never can select two weapons at the same time
abstract class WeaponSelector {
    private {
        bool mIsSelected;
    }

    this(WeaponClass wc, GObjectSprite owner) {
    }

    this (ReflectCtor c) {
    }

    final bool isSelected() {
        return mIsSelected;
    }

    //only to be used by the worm weapon control code
    final void isSelected(bool s) {
        if (mIsSelected == s)
            return;
        mIsSelected = s;
        if (s) {
            onSelect();
        } else {
            onUnselect();
        }
    }

    //called when the weapon is unselected
    //note that the weapon can be unselected while it's still active
    //e.g. the rope is always unselected after shooting it
    protected void onUnselect() {
    }

    //reselect (because unselection comes often; e.g. a worm will unselect a
    //  weapon temporarily while it's walking)
    //select() is also called some time after construction of this object
    protected void onSelect() {
    }
}

//for Shooter.fire(FireInfo)
struct FireInfo {
    Vector2f dir = Vector2f.nan; //normalized throw direction
    Vector2f surfNormal = Vector2f(-1, 0);   //impact surface normal
    float strength = 1.0f; //as allowed in the weapon config
    Time timer;     //selected time, in the range dictated by the weapon
    Vector2f pos;     //position of shooter
    float shootbyRadius = 0.0f;
    WeaponTarget pointto; //if weapon can point to somewhere
}

struct WeaponTarget {
    Vector2f pos = Vector2f.nan;
    GObjectSprite sprite;

    Vector2f currentPos() {
        return (sprite && !sprite.physics.pos.isNaN())
            ? sprite.physics.pos : pos;
    }

    void opAssign(Vector2f p) {
        pos = p;
        sprite = null;
    }

    bool valid() {
        return !currentPos.isNaN();
    }
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

    //if non-null, what was created by WeaponClass.createSelector()
    //this is set right after the constructor has been run
    //(xxx: move to ctor... also, use utils.factory to create shooters)
    WeaponSelector selector;

    protected this(WeaponClass base, GObjectSprite a_owner, GameEngine engine) {
        super(engine, false);
        assert(base !is null);
        mClass = base;
        owner = a_owner;
        createdBy = a_owner;
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
        active = false;
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

    //if this returns false, the direction cannot be changed
    bool canReadjust() {
        return true;
    }

    //used by a worm to notify that the worm was interrupted while firing
    //for some weapons, this won't do anything, i.e. air strikes, earth quakes...
    //after this, isFiring() will return false (mostly...)
    void interruptFiring(bool outOfAmmo = false) {
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

//number and types of weapons a team has available
class WeaponSet {
    GameEngine engine;
    private {
        Entry[] mEntries;
    }

    struct Entry {
        //for the public: all fields readonly (writing getters would be bloat)
        WeaponClass weapon;
        uint quantity; //cINF means infinite
        const cINF = typeof(quantity).max;
        Time lastFire;

        bool infinite() {
            return quantity == cINF;
        }

        char[] quantityToString() {
            if (infinite)
                return "inf";
            return to!(char[])(quantity);
        }
    }

    //config = item from "weapon_sets"
    this (GameEngine aengine, ConfigNode config, bool crateSet = false) {
        this(aengine);
        foreach (ConfigNode node; config.getSubNode("weapon_list")) {
            WeaponClass w;
            uint quantity;
            char[] wname = node.name;
            try {
                //may throw ClassNotRegisteredException
                w = engine.gfx.findWeaponClass(wname);
                assert(!!w);
            } catch (ClassNotRegisteredException e) {
                registerLog("game.controller")
                    ("Error in weapon set '"~wname~"': "~e.msg);
            }
            if (node.value == "inf") {
                quantity = Entry.cINF;
            } else {
                quantity = node.getCurValue!(int)();
            }
            if (crateSet) {
                //only drop weapons that are not infinite already,
                //  and that can be used in the current world
                if (quantity == Entry.cINF || !w.canUse(engine))
                    quantity = 0;
            }
            addWeapon(w, quantity);
        }
    }

    //create empty set
    this(GameEngine aengine) {
        assert(!!aengine);
        engine = aengine;
    }

    this (ReflectCtor c) {
    }

    private void onChange() {
        //xxx probably not quite kosher, it's a rather random hack
        engine.callbacks.weaponsChanged(this);
    }

    void saveToConfig(ConfigNode config) {
        auto node = config.getSubNode("weapon_list");
        node.clear();
        foreach (Entry e; mEntries) {
            node.setStringValue(e.weapon.name, e.quantityToString);
        }
    }

    void iterate(void delegate(Entry e) dg) {
        foreach (e; mEntries)
            dg(e);
    }

    //linear search, but this isn't called that often and item count is low
    private Entry* do_find(WeaponClass w, bool add) {
        foreach (ref e; mEntries) {
            if (e.weapon is w)
                return &e;
        }
        if (!add)
            return null;
        assert(!!w);
        Entry e;
        e.weapon = w;
        mEntries ~= e;
        return &mEntries[$-1];
    }

    Entry find(WeaponClass w) {
        Entry* p = do_find(w, false);
        return p ? *p : Entry(w, 0);
    }

    //add weapons form other set to this set
    void addSet(WeaponSet other) {
        assert(!!other);
        foreach (Entry e; other.mEntries) {
            addWeapon(e.weapon, e.quantity);
        }
    }

    //can pass Entry.cINF to make weapon infinite
    void addWeapon(WeaponClass w, uint quantity = 1) {
        if (!w || quantity < 1)
            return;
        Entry* e = do_find(w, true);
        if (!e.infinite()) {
            if (quantity == Entry.cINF) {
                e.quantity = Entry.cINF;
            } else {
                e.quantity += quantity;
            }
        }
        onChange();
    }

    //decrease weapon by one - return if success
    bool decreaseWeapon(WeaponClass w) {
        Entry* e = do_find(w, false);
        if (!e)
            return false;
        assert(e.quantity != 0); //unallowed state
        if (!e.infinite())
            e.quantity -= 1;
        if (e.quantity == 0) {
            //remove from array by moving the last array element into its place
            size_t idx = e - mEntries.ptr;
            assert(idx < mEntries.length);
            mEntries[idx] = mEntries[$-1];
            mEntries = mEntries[0..$-1];
        }
        onChange();
        return true;
    }

    bool firedWeapon(WeaponClass w) {
        Entry* e = do_find(w, false);
        if (!e)
            return false;
        //note: e.quantity may be 0 (decreaseWeapon is called before)
        e.lastFire = engine.gameTime.current;
        onChange();
        return true;
    }

    //returns true if w currently can't be fired due to cooldown
    //(returns false in all other cases)
    bool coolingDown(WeaponClass w) {
        Entry* e = do_find(w, false);
        if (!e)
            return false;
        return (e.lastFire != Time.Null
            && engine.gameTime.current <= e.lastFire + w.cooldown);
    }

    //choose a random weapon based on this weapon set
    //returns null if none was found
    //xxx: Implement different drop probabilities (by value/current count)
    WeaponClass chooseRandomForCrate() {
        if (mEntries.length > 0) {
            uint r = engine.rnd.next(0, mEntries.length);
            return mEntries[r].weapon;
        } else {
            return null;
        }
    }
}
