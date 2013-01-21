module game.weapon.weapon;

import common.animation;
import common.scene;
import framework.drawing;
import framework.surface;
import game.events;
import game.core;
import game.sprite;
import game.weapon.types;
import game.sequence;
import game.particles;
import game.temp;
import utils.log;
import utils.misc;
import utils.math;
import utils.time;
import utils.timesource;
import utils.vector2;
import utils.interpolate;

import std.math;

//a crate is being blown up, and the crate contains this weapon
//  Sprite = the sprite for the crate
alias DeclareEvent!("weapon_crate_blowup", WeaponClass, Sprite)
    OnWeaponCrateBlowup;
//sprite firing the weapon, used weapon, refired
alias DeclareEvent!("shooter_fire", WeaponClass, bool) OnFireWeapon;

//abstract weapon type; only contains generic infos about a weapon
//this includes how stuff is fired (for the code which does worm controll)
//(argument against making classes like i.e. WeaponThrowable: no multiple
// inheritance *g*; and how would you have a single fire() method then)
abstract class WeaponClass : EventTarget {
    private GameCore mCore;

    //generally read-only fields
    string name; //weapon name, translateable string
    int value = 0;  //see config file
    string category = "none"; //category-id for this weapon
    bool isAirstrike = false; //needed to exlude it from cave levels
    bool allowSecondary = false;  //allow selecting and firing a second
                                  //weapon while active
    bool dontEndRound = false;
    bool deselectAfterFire = false;
    Time cooldown = Time.Null;
    int crateAmount = 1;

    //for the weapon selection; only needed on client-side
    Surface icon;
    //particles are mostly for repeating sounds that play while the weapon is
    //  firing (e.g. minigun); it doesn't work well for one-shot weapons
    //  because the Shooter dies immediately
    ParticleType prepareParticle, fireParticle;

    FireMode fireMode;

    //weapon-holding animations
    string animation;

    GameCore engine() {
        return mCore;
    }

    this(GameCore a_core, string a_name) {
        assert(a_core !is null);
        super("weapon_" ~ a_name, a_core.events);
        mCore = a_core;
        name = a_name.idup;
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

    override string toString() {
        return myformat("[Weapon %s]", name);
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

    //setting this will clear any target tracking
    void currentPos(Vector2f p) {
        pos = p;
        sprite = null;
    }

    bool valid() {
        return !currentPos.isNaN();
    }
}

//feedback Shooter -> input controller (implemented by WormControl)
interface WeaponController {
    WeaponTarget getTarget();

    int getWeaponParam();

    //returns true if there is more ammo left
    bool reduceAmmo(WeaponClass weapon);

    //called directly after a shot started firing (checks passed)
    //used for statistics and cooldowns
    void firedWeapon(WeaponClass weapon, bool refire);

    //called some time after startFire() has been called, notifying the weapon
    //  has stopped all activities
    //xxx add bool success?
    void doneFiring(Shooter sh);

    void setPointMode(PointMode mode);
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

LogStruct!("shooter") gWeaponLog;

//simulates the whole lifetime of a weapon: selection, aiming, charging, firing
//interacts with owner sprite via sequence, and with controller via
//  WeaponController interface
//also simulates whatever is going on for special weapons (e.g. rope, jetpack)
//always created by WeaponClass.createShooter()
//practically a factory for projectiles *g* (mostly, but not necessarily)
//projectiles can work completely independend from this class
abstract class Shooter : GameObject {
    enum WeaponState {
        idle,          //ready, waiting for user input, selector working
        charge,        //space held down
        prepare,       //animation playing
        fire,          //creating projectiles etc.
        release,       //animation playing <- xxx unused
                       //                     (planned but not implemented)
    }

    private {
        alias gWeaponLog log;
        //null if not there, instantiated all the time it's needed
        RenderCrosshair mCrosshair;

        float mWeaponMove = 0;     //+1/0/-1
        float mWeaponAngle = 0;    //current aim
        float mFixedWeaponAngle = float.nan;
        int mThreewayMoving;

        bool mQueueAnimUpdate;
        //if true, the weapon is visible on the worm and can be fired
        bool mIsSelected;
        bool mRegularFinish;
        WeaponState mState;
        //used with WwpWeaponDisplay.fire(&fireStart, ...)
        //if the sequence is interrupted, fireStart will never be called, and
        //  our code will be stuck forever waiting
        //polling actually makes it easier to detect this condition (the real
        //  problem is the stupid Sequence<->weapon code interface, which was
        //  always a hack)
        //test: select axe, fire, and walk with the worm while the prepare
        //  animation is playing -> should be able to fire after that
        bool mWaitFireStart;

        ParticleEmitter mParticleEmitter;
        ParticleType mCurrentParticle;

        enum Time cWeaponLoadTime = timeMsecs(1500);
    }
    protected {
        WeaponClass mClass;
        Time mLastStateChange;
        WeaponController wcontrol;
    }

    //for displaying animations
    Sprite owner;

    //latest valid fire position etc.
    //valid at first doFire call, updated on readjust
    FireInfo fireinfo;

    //if non-null, what was created by WeaponClass.createSelector()
    //xxx created in the ctor, the difference between shooter and selector
    //    is now a bit ... fuzzy
    WeaponSelector selector;

    protected this(WeaponClass base, Sprite a_owner) {
        assert(!!a_owner);
        assert(!!base);
        super(a_owner.engine, "shooter");
        mClass = base;
        owner = a_owner;
        createdBy = a_owner;
        selector = weapon.createSelector(owner);
        mLastStateChange = engine.gameTime.current;
        internal_active = true;
        log.trace("create %s", this);
    }

    //can't use controlFromGameObject because of dependency hell
    final void setControl(WeaponController control) {
        wcontrol = control;
    }

    //call to take 1 ammo
    //returns true if there is still more ammo left
    final bool reduceAmmo() {
        if (wcontrol)
            return wcontrol.reduceAmmo(mClass);
        return true;
    }

    //call to report firing ended, to ready the weapon for the next shot
    //implementations should always call this if they want to stop activity
    //  (either successful or cancelled)
    final void finished() {
        if (mState != WeaponState.fire)
            return;
        log.trace("finished");
        mRegularFinish = true;
        setState(WeaponState.idle);
        if (wcontrol)
            wcontrol.doneFiring(this);
    }

    public WeaponClass weapon() {
        return mClass;
    }

    //start firing (i.e. fire key pressed by user)
    //returns true if the keypress was processed
    final bool startFire(bool keyUp = false) {
        if (mState == WeaponState.fire && !keyUp) {
            //refire
            log.trace("fire pressed while working");
            return initiateFire();
        } else if (mState == WeaponState.idle && mIsSelected && !keyUp) {
            //start firing
            if (weapon.fireMode.variableThrowStrength()) {
                //charge up fire strength
                log.trace("start charge");
                setState(WeaponState.charge);
                //"true" just means the keypress was taken; we don't know about
                //  firing success here
                return true;
            } else {
                //fire instantly with default strength
                log.trace("fire fixed strength");
                fireinfo.strength = weapon.fireMode.throwStrengthFrom;
                return initiateFire();
            }
        } else if (mState == WeaponState.charge && mIsSelected && keyUp) {
            //fire key released, really fire variable-strength weapon
            log.trace("fire variable strength (after charge)");

            auto strength = currentFireStrength();
            auto fm = weapon.fireMode;
            fireinfo.strength = fm.throwStrengthFrom + strength
                * (fm.throwStrengthTo - fm.throwStrengthFrom);
            return initiateFire();
        }
        return false;
    }

    //hack for parachute, to fire while weapon is not selected
    //xxx could also add a flag that allows firing in air or something
    final protected bool instantFireInternal() {
        if (mState != WeaponState.idle)
            return false;
        //fire instantly with default strength
        fireinfo.strength = weapon.fireMode.throwStrengthFrom;
        return initiateFire();
    }

    //get weapon specific interface to animation code - may return null
    //xxx this is a hack insofar, that it is WWP specific and doesn't use a
    //  "generic" way of communicating with the animation code; but we need some
    //  way to reach the functions specialized for weapon display (see rant in
    //  sequence.d)
    private WwpWeaponDisplay weaponAniState() {
        if (!owner || !owner.graphic)
            return null;
        return cast(WwpWeaponDisplay)owner.graphic.stateDisplay();
    }

    //copy+paste, lol
    protected void updateParticles() {
        mParticleEmitter.active = true;
        mParticleEmitter.current = mCurrentParticle;
        mParticleEmitter.pos = owner.physics.pos;
        mParticleEmitter.velocity = owner.physics.velocity;
        mParticleEmitter.update(engine.particleWorld);
    }

    final void setParticle(ParticleType pt) {
        if (mCurrentParticle is pt)
            return;
        mCurrentParticle = pt;
        updateParticles();
    }

    //return the fire strength value, always between 0.0 and 1.0
    private float currentFireStrength() {
        if (mState != WeaponState.charge)
            return 0;
        auto diff = engine.gameTime.current - mLastStateChange;
        float s = cast(double)diff.msecs / cWeaponLoadTime.msecs;
        return clampRangeC(s, 0.0f, 1.0f);
    }

    //prepare firing (for weapon animation)
    //this will cause the animation code (lolwtf) to eventually call fireStart()
    private bool initiateFire() {
        //if in state WeaponState.idle/charge, start firing
        //if in state WeaponState.fire, do a refire
        if (mState == WeaponState.idle || mState == WeaponState.charge) {
            setState(WeaponState.prepare);
        } else {
            assert(mState == WeaponState.fire);
            setParticle(mClass.prepareParticle);
        }
        auto ani = weaponAniState();
        bool ok = false;
        if (ani) {
            //normal case
            bool refire = (mState == WeaponState.fire);
            mWaitFireStart = true;
            //calls fireStart immediately if there is no prepare animation
            ok = ani.fire(&fireStart, refire);
        }
        if (!ok) {
            //normally shouldn't happen, except if animation is wrong
            //also happens if the worm is in rope/jetpack state, and refires
            fireStart();
        }
        //xxx assume always success (it's simply impossible to get the return
        //  value of fireWeapon here; it's defered to fireStart())
        return true;
    }

    //called by the animation code when actual firing should be started (after
    //  prepare animation [e.g. shotgun reload] has been played)
    private void fireStart() {
        mWaitFireStart = false;
        //sanity tests
        //fire or refire
        if (mState != WeaponState.prepare && mState != WeaponState.fire)
            return;
        //strength set in fire()
        if (fireinfo.strength != fireinfo.strength)
            return;
        //actually fire
        bool refire = (mState == WeaponState.fire);
        bool res;
        if (!refire) {
            res = fireWeapon();
            //failed but we are in state prepare, return to idle
            if (!res)
                setState(WeaponState.idle);
        } else {
            //state remains fire, even if this call fails
            res = doRefire();
            if (wcontrol)
                wcontrol.firedWeapon(weapon, true);
        }
        //when does this happen at all?
        //this should never happen; instead it should be prevented by fire()
        if (!res)
            log.warn("Couldn't fire weapon!");
    }

    //-PI/2..+PI/2, actual angle depends from whether worm looks left or right
    float weaponAngle() {
        if (mFixedWeaponAngle == mFixedWeaponAngle)
            return mFixedWeaponAngle;
        return mWeaponAngle;
    }

    void weaponAngle(float a) {
        mWeaponAngle = a;
    }

    private void updateWeaponAngle(float move) {
        float old = weaponAngle;
        //xxx why is worm movement a float anyway?
        int moveInt = (move>float.epsilon) ? 1 : (move<-float.epsilon ? -1 : 0);
        mFixedWeaponAngle = float.nan;
        switch (weapon.fireMode.direction) {
            case ThrowDirection.fixed:
                //no movement
                mFixedWeaponAngle = 0;
                break;
            case ThrowDirection.any:
            case ThrowDirection.limit90:
                //free moving, directly connected to keys
                if (moveInt != 0) {
                    mWeaponAngle += moveInt * engine.gameTime.difference.secsf
                        * PI/2;
                }
                if (weapon.fireMode.direction == ThrowDirection.limit90) {
                    //limited to 90°
                    mWeaponAngle = clampRangeC(mWeaponAngle,
                        cast(float)-PI/4, cast(float)PI/4);
                } else {
                    //full 180°
                    mWeaponAngle = clampRangeC(mWeaponAngle,
                        cast(float)-PI/2, cast(float)PI/2);
                }
                break;
            case ThrowDirection.threeway:
                //three fixed directions, selected by keys
                if (moveInt != mThreewayMoving) {
                    if (moveInt > 0) {
                        if (mWeaponAngle < -float.epsilon)
                            mWeaponAngle = 0;
                        else
                            mWeaponAngle = 1.0f;
                    } else if (moveInt < 0) {
                        if (mWeaponAngle > float.epsilon)
                            mWeaponAngle = 0;
                        else
                            mWeaponAngle = -1.0f;
                    }
                }
                //always verify the limits, e.g. on weapon change
                if (mWeaponAngle > float.epsilon)
                    mWeaponAngle = PI/6;
                else if (mWeaponAngle < -float.epsilon)
                    mWeaponAngle = -PI/6;
                else
                    mWeaponAngle = 0;
                break;
            default:
                assert(false);
        }
        mThreewayMoving = moveInt;
        if (auto wani = weaponAniState()) {
            wani.angle = weaponAngle();
        }
    }

    protected float weaponAngleSide() {
        return fullAngleFromSideAngle(owner.physics.lookey, weaponAngle);
    }

    //real weapon angle (normalized direction)
    protected Vector2f weaponDir() {
        return Vector2f.fromPolar(1.0f, weaponAngleSide);
    }

    //weaponDir with horizontal firing angle (only considers lookey)
    //xxx unused
    protected Vector2f weaponDirHor() {
        return dirFromSideAngle(owner.physics.lookey, 0);
    }

    //fill fireinfo and actually fire the weapon (which, in most cases, means
    //  some script code gets executed)
    private bool fireWeapon(bool fixedDir = false) {
        log.trace("fire: %s", weapon.name);
        assert(mState == WeaponState.prepare);

        if (fixedDir)
            fireinfo.dir = weaponDirHor();
        else
            fireinfo.dir = weaponDir();
        //possibly add worm speed (but we don't want to lose dir if str == 0)
        if (fireinfo.strength > float.epsilon
            && owner.physics.velocity.quad_length > float.epsilon)
        {
            Vector2f fDir = fireinfo.dir*fireinfo.strength
                + owner.physics.velocity;
            float s = fDir.length;
            //worm speed and strength might add up to exactly 0 (nan check)
            if (s > float.epsilon) {
                fireinfo.strength = s;
                fireinfo.dir = fDir/s;
            }
        }
        int p = 0;
        if (wcontrol)
            p = wcontrol.getWeaponParam();
        fireinfo.param = weapon.fireMode.actualParam(p);
        if (wcontrol)
            fireinfo.pointto = wcontrol.getTarget;
        else
            fireinfo.pointto.currentPos = owner.physics.pos;

        if (selector) {
            if (!selector.canFire(fireinfo))
                return false;
        }

        //doFire doesn't fail (no way back here, all checks passed)
        setState(WeaponState.fire);
        doFire();
        if (wcontrol)
            wcontrol.firedWeapon(weapon, false);

        return true;
    }

    abstract protected void doFire();

    protected bool doRefire() {
        log.trace("default refire");
        return false;
    }

    final void move(float m) {
        mWeaponMove = m;
    }

    //called when direction is changed while firing
    protected void doReadjust(Vector2f dir) {
        fireinfo.dir = dir;
        log.trace("readjust %s", dir);
    }

    //often the worm can change shooting direction while the weapon still fires
    protected bool canReadjust() {
        return true;
    }

    override protected void onKill() {
        super.onKill();
        interruptFiring(true);
    }

    //called to notify that the weapon should stop all activity (and cannot
    //  be fired again); will not call finished()
    //interface function; should be avoided in weapon implementations because
    //  it does not notify wcontrol (use finished instead)
    //implementers: override onWeaponActivate instead
    final void interruptFiring(bool unselect = false) {
        log.trace("interruptFiring");
        isSelected = isSelected && !unselect;
        setState(WeaponState.idle);
    }

    //set if the weapon is selected (i.e. ready to fire)
    //will not abort firing (but will abort charging when deselected)
    final void isSelected(bool s) {
        if (mIsSelected == s)
            return;
        mIsSelected = s;
        //xxx hacky
        onStateChange(mState);
        if (!isSelected && currentState == WeaponState.charge) {
            setState(WeaponState.idle);
        }
    }
    final bool isSelected() {
        return mIsSelected;
    }

    final WeaponState currentState() {
        return mState;
    }

    final protected void setState(WeaponState newState) {
        if (mState == newState)
            return;

        auto old = mState;
        mState = newState;
        mLastStateChange = engine.gameTime.current;
        onStateChange(old);
    }

    //called to notify the Shooter state has changed
    //Note: oldState does not have to be != mState, other values (like
    //      mIsSelected) may have changed
    protected void onStateChange(WeaponState oldState) {
        updateCrosshair();
        if (selector) {
            selector.isSelected = (mState == WeaponState.idle && mIsSelected);
        }
        if (mState != oldState && oldState == WeaponState.fire) {
            if (auto wani = weaponAniState()) {
                wani.stopFire();
            }
        }
        if (mState != oldState) {
            if (mState == WeaponState.prepare) {
                setParticle(mClass.prepareParticle);
            } else if (mState == WeaponState.fire) {
                setParticle(mClass.fireParticle);
            } else {
                setParticle(null);
            }
        }
        updateAnimation();
        if (wcontrol) {
            if (mIsSelected) {
                wcontrol.setPointMode(weapon.fireMode.point);
            } else {
                wcontrol.setPointMode(PointMode.none);
            }
        }
        if (mState != oldState
            && (mState == WeaponState.fire || oldState == WeaponState.fire))
        {
            //helper for derived classes
            onWeaponActivate(mState == WeaponState.fire);
            if (mState != WeaponState.fire && !mRegularFinish) {
                onInterrupt();
            }
        }
        mRegularFinish = false;
    }

    private void updateAnimation() {
        if (auto wani = weaponAniState()) {
            mQueueAnimUpdate = false;
            if (mIsSelected) {
                string w = weapon.animation;
                //right now, an empty string means "no weapon", but we mean
                //  "unknown weapon" (so a default animation is selected, not none)
                if (w == "") {
                    w = "-";
                }
                wani.weapon = w;
            } else {
                wani.weapon = "";
            }
        } else {
            //update was required, but could not be processed (maybe
            //  wrong worm state) -> queue for later
            mQueueAnimUpdate = true;
        }
    }

    //called when the weapon "function" becomes active or inactive
    //  (as internal_active will now always be true)
    //linked to the Shooter being in the "fire" state
    protected void onWeaponActivate(bool active) {
    }

    //called when firing was interrupted (in detail: leaving the fire state
    //  was not triggered by a finished() call)
    //will not be called from finished()
    protected void onInterrupt() {
    }

    //true when weapon function is working
    final bool weaponActive() {
        return mState == WeaponState.fire;
    }

    override void simulate() {
        super.simulate();
        if (mState == WeaponState.charge) {
            auto strength = currentFireStrength();
            if (mCrosshair) {
                mCrosshair.setLoad(strength);
            }
            //xxx replace comparision by checking against the time, with a small
            //  delay before actually shooting (like wwp does)
            if (strength >= 1.0f)
                startFire(true);
        }
        auto wani = weaponAniState();
        if (mWaitFireStart && wani && !wani.preparingFire) {
            log.trace("unstuck prepare animation");
            mWaitFireStart = false;
            setState(WeaponState.idle);
        }
        if (mIsSelected && wani) {
            wani.angle = weaponAngle();
        }
        if (canAim()) {
            updateWeaponAngle(mWeaponMove);
            if (mWeaponMove != 0
                && (mState == WeaponState.fire && canReadjust()))
            {
                doReadjust(weaponDir());
            }
        }
        if (mQueueAnimUpdate) {
            updateAnimation();
        }
        updateParticles();
    }

    private bool canAim() {
        return (mState == WeaponState.idle || mState == WeaponState.charge
            || mState == WeaponState.prepare
            || (mState == WeaponState.fire && canReadjust()))
            && mIsSelected;
    }

    private void updateCrosshair() {
        //create/destroy the crosshair
        bool exists = !!mCrosshair;
        bool shouldexist = weapon.fireMode.direction != ThrowDirection.fixed
            && canAim();
        if (exists != shouldexist) {
            if (exists) {
                mCrosshair.removeThis();
                mCrosshair = null;
            } else {
                mCrosshair = new RenderCrosshair(owner.graphic,
                    &weaponAngleSide);
                engine.scene.add(mCrosshair);
            }
        }

        //remove "load" bar after firing
        if (mCrosshair && mState != WeaponState.charge) {
            mCrosshair.resetLoad();
        }
    }

    override bool activity() {
        return mState == WeaponState.prepare || mState == WeaponState.fire
            || mState == WeaponState.charge;
    }

    bool delayedAction() {
        return activity();
    }

    //required for nasty weapons like guns which keep you from doing useful
    //things like running away
    bool isFixed() {
        return activity();
    }

    final bool isIdle() {
        return mState == WeaponState.idle;
    }

    bool animationOK() {
        if (auto wani = weaponAniState()) {
            return wani.ok();
        } else {
            return true;
        }
    }

    override string toString() {
        return myformat("[Shooter %#x %s]", toHash, mClass);
    }
}

import game.gfxset;

//move elsewhere?
class RenderCrosshair : SceneObject {
    private {
        GameCore mEngine;
        GfxSet mGfx;
        Sequence mAttach;
        float mLoad = 0.0f;
        bool mDoReset;
        InterpolateState mIP;
        ParticleType mSfx;
        ParticleEmitter mEmit;
        float delegate() mWeaponAngle;

        struct InterpolateState {
            bool did_init;
            InterpolateExp!(float, 4.25f) interp;
        }
    }

    this(Sequence a_attach, float delegate() weaponAngle) {
        assert(!!a_attach);
        mEngine = a_attach.engine;
        mGfx = mEngine.singleton!(GfxSet)();
        mAttach = a_attach;
        mWeaponAngle = weaponAngle;
        mSfx = mEngine.resources.get!(ParticleType)("p_rocketcharge");
        zorder = GameZOrder.Crosshair;
        init_ip();
        reset();
    }

    override void removeThis() {
        //make sure sound gets stopped
        mEmit.current = null;
        mEmit.update(mEngine.particleWorld);
        super.removeThis();
    }

    private void init_ip() {
        mIP.interp.currentTimeDg = &time.current;
        mIP.interp.init(mGfx.crosshair.animDur, 1, 0);
        mIP.did_init = true;
    }

    //value between 0.0 and 1.0 for the fire strength indicator
    void setLoad(float a_load) {
        mLoad = a_load;
        mEmit.current = (mLoad > float.epsilon) ? mSfx : null;
    }

    //set load indicator back to "resting" state
    void resetLoad() {
        setLoad(0.0);
    }

    //reset animation, called after this becomes .active again
    void reset() {
        mIP.interp.restart();
    }

    private TimeSourcePublic time() {
        return mEngine.interpolateTime;
    }

    override void draw(Canvas canvas) {
        auto tcs = mGfx.crosshair;

        if (!mIP.did_init) {
            //if this code is executed, the game was just loaded from a savegame
            init_ip();
        }

        auto pos = mAttach.interpolated_position;
        auto angle = mWeaponAngle ? mWeaponAngle() : PI/2;
        //normalized weapon direction
        auto dir = Vector2f.fromPolar(1.0f, angle);

        //crosshair animation
        auto target_offset = tcs.targetDist - tcs.targetStartDist;
        //xxx reset on weapon change
        Vector2i target_pos = pos + toVector2i(dir * (tcs.targetDist
            - target_offset*mIP.interp.value));
        AnimationParams ap;
        ap.p[0] = cast(int)((angle + 2*PI*mIP.interp.value)*180/PI);
        Animation cs = mAttach.team.aim;
        //(if really an animation should be supported, it's probably better to
        // use Sequence or so - and no more interpolation)
        cs.draw(canvas, target_pos, ap, Time.Null);

        //draw that band like thing, which indicates fire/load strength
        auto start = tcs.loadStart + tcs.radStart;
        auto abs_end = tcs.loadEnd - tcs.radEnd;
        auto scale = abs_end - start;
        auto end = start + cast(int)(scale*mLoad);
        auto rstart = start + 1; //omit first circle => invisible at mLoad=0
        float oldn = 0;
        int stip;
        auto cur = end;
        //NOTE: when firing, the load-colors look like they were animated;
        //  actually that's because the stipple-offset is changing when the
        //  mLoad value changes => stipple pattern moves with mLoad and the
        //  color look like they were changing
        while (cur >= rstart) {
            auto n = (1.0f*(cur-start)/scale);
            if ((stip % tcs.stipple)==0)
                oldn = n;
            auto col = tcs.colorStart + (tcs.colorEnd-tcs.colorStart)*oldn;
            auto rad = cast(int)(tcs.radStart+(tcs.radEnd-tcs.radStart)*n);
            canvas.drawFilledCircle(pos + toVector2i(dir*cur), rad, col);
            cur -= tcs.add;
            stip++;
        }

        mEmit.pos = toVector2f(pos);
        mEmit.update(mEngine.particleWorld);
    }
}
