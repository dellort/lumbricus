module game.weapon.weapon;

import framework.framework; //: Surface
import game.events;
import game.core;
import game.sprite;
import game.weapon.types;
import utils.log;
import utils.misc;
import utils.time;
import utils.vector2;

//a crate is being blown up, and the crate contains this weapon
//  Sprite = the sprite for the crate
alias DeclareEvent!("weapon_crate_blowup", WeaponClass, Sprite)
    OnWeaponCrateBlowup;
//sprite firing the weapon, used weapon, refired
alias DeclareEvent!("shooter_fire", Shooter, bool) OnFireWeapon;

//abstract weapon type; only contains generic infos about a weapon
//this includes how stuff is fired (for the code which does worm controll)
//(argument against making classes like i.e. WeaponThrowable: no multiple
// inheritance *g*; and how would you have a single fire() method then)
abstract class WeaponClass : EventTarget {
    private GameCore mCore;

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
    int crateAmount = 1;

    //for the weapon selection; only needed on client-side
    Surface icon;

    FireMode fireMode;

    //weapon-holding animations
    char[] animation;

    GameCore engine() {
        return mCore;
    }

    this(GameCore a_core, char[] a_name) {
        assert(a_core !is null);
        super("weapon_" ~ a_name, a_core.events);
        mCore = a_core;
        name = a_name.dup;
    }

    //called when the sprite selected_by selects this weapon
    //this is needed when you want to have somewhat more control over the how
    //  a weapon is _prepared_ to fire
    //may return null (actually, it returns null in the most cases)
    //xxx: and actually, the hardcoded FireMode thing sucks a bit
    WeaponSelector createSelector(Sprite selected_by) {
        return null;
    }

    //just a factory
    //users call fire() on them to actually activate them
    //  go == entity which fires it (its physical properties will be used)
    abstract Shooter createShooter(Sprite go);

    bool canUse(GameCore engine) {
        return !isAirstrike || engine.level.airstrikeAllow;
    }

    override char[] toString() {
        return myformat("[Weapon {}]", name);
    }
}

//some weapons need to do stuff while they're selected (girder construction)
//this really should be in Shooter, but Shooter is only created right before
//  the weapon is fired, and much code relies on this; too messy to change (most
//  of the mess is in worm.d/wcontrol.d)
//note that this is not created by a "double factory"; you can use the passed
//  WeaponClass to store data
//as far as I see, a worm never can select two weapons at the same time
abstract class WeaponSelector {
    private {
        bool mIsSelected;
    }

    this(Sprite owner) {
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
    //onSelect() is also called some time after construction of this object
    protected void onSelect() {
    }

    //check if firing is possible
    //can also modify the FireInfo
    bool canFire(ref FireInfo info) {
        return true;
    }
}

//for Shooter.fire(FireInfo)
struct FireInfo {
    Vector2f dir = Vector2f(-1, 0); //normalized throw direction -- was nan
    Vector2f surfNormal = Vector2f(-1, 0);   //impact surface normal
    float strength = 1.0f; //as allowed in the weapon config
    int param;     //selected param, in the range dictated by the weapon
    Vector2f pos;     //position of shooter
    float shootbyRadius = 0.0f;
    WeaponTarget pointto; //if weapon can point to somewhere
}

struct WeaponTarget {
    Vector2f pos = Vector2f.nan;
    Sprite sprite;

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

//find the shooter from a game object; return null on failure
//this should always work for sprites created by weapons, except if there's a
//  bug in some weapon code (incorrect createdBy chain)
Shooter gameObjectFindShooter(GameObject o) {
    while (o) {
        if (auto sh = cast(Shooter)o)
            return sh;
        o = o.createdBy;
    }
    return null;
}

//simulate the firing of a weapon; i.e. create projectiles and so on
//also simulates whatever is going on for special weapons (i.e. earth quakes)
//always created by WeaponClass.createShooter()
//practically a factory for projectiles *g* (mostly, but not necessarily)
//projectiles can work completely independend from this class
abstract class Shooter : GameObject {
    private LogStruct!("shooter") log;

    protected WeaponClass mClass;
    Sprite owner;
    private bool mWorking;   //only for finishCb event

    //latest valid fire position etc.
    //valid at first doFire call, updated on readjust
    FireInfo fireinfo;

    void delegate(Shooter sh) finishCb;
    //shooters should call this to reduce owner's ammo by 1
    bool delegate(Shooter sh) ammoCb;
    //if non-null, what was created by WeaponClass.createSelector()
    //this is set right after the constructor has been run
    //(xxx: move to ctor... also, use utils.factory to create shooters)
    WeaponSelector selector;

    protected this(WeaponClass base, Sprite a_owner, GameCore engine) {
        super(engine, "shooter");
        assert(base !is null);
        mClass = base;
        owner = a_owner;
        createdBy = a_owner;
    }

    final bool reduceAmmo() {
        if (ammoCb)
            return ammoCb(this);
        return true;
    }

    final void finished() {
        if (!mWorking)
            return;
        log.trace("finished");
        mWorking = false;
        internal_active = false;
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
    final bool fire(FireInfo info) {
        assert(!activity);
        fireinfo = info;
        if (selector) {
            if (!selector.canFire(info))
                return false;
        }
        log.trace("fire");
        mWorking = true;
        doFire(info);
        return true;
    }

    //fire again (i.e. trigger special actions, like deactivating)
    final bool refire() {
        assert(activity);
        //xxx: I don't know how not-being-able-to-fire should be handled with
        //     WeaponSelector (see fire())
        return doRefire();
    }

    abstract protected void doFire(FireInfo info);

    protected bool doRefire() {
        log.trace("default refire");
        return false;
    }

    //required for nasty weapons like guns which keep you from doing useful
    //things like running away
    bool isFixed() {
        return isFiring();
    }

    //often the worm can change shooting direction while the weapon still fires
    final void readjust(Vector2f dir) {
        if (dir != fireinfo.dir) {
            doReadjust(dir);
        }
    }

    protected void doReadjust(Vector2f dir) {
        fireinfo.dir = dir;
        log.trace("readjust {}", dir);
    }

    //if this returns false, the direction cannot be changed
    bool canReadjust() {
        return true;
    }

    //used by a worm to notify that the worm was interrupted while firing
    //for some weapons, this won't do anything, i.e. air strikes, earth quakes...
    //after this, isFiring() will return false (mostly...)
    void interruptFiring() {
        //default implementation: make inactive
        internal_active = false;
    }

    //if this class still thinks the worm is i.e. shooting projectiles
    //weapons like earth quakes might still be active but return false
    //invariant: isFiring() => internal_active()
    bool isFiring() {
        //default implementation: link with activity
        return activity;
    }

    override void updateInternalActive() {
        super.updateInternalActive();
        log.trace("internal_active={}", internal_active);
    }

    override char[] toString() {
        return myformat("[Shooter {:x}]", cast(void*)this);
    }
}
