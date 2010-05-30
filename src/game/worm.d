module game.worm;

import common.animation;
import framework.framework;
import game.core;
import game.sequence;
import game.sprite;
import game.teamtheme;
import game.temp : GameZOrder;
import game.weapon.types;
import game.weapon.weapon;
import game.particles;
import physics.all;
import utils.misc;
import utils.vector2;
import utils.time;
import utils.log;
import utils.misc;
import utils.math;
import tango.math.Math;

//crosshair
import common.scene;
import utils.interpolate;
import utils.timesource;

/**
  just an idea:
  thing which can be controlled like a worm
  game/controller.d would only have a sprite, which could have this interface...

interface IControllable {
    void move(Vector2f dir);
    void jump();
    void activateJetpack(bool activate);
    void drawWeapon(bool draw);
    bool weaponDrawn();
    void shooter(Shooter w);
    Shooter shooter();
    xxx not uptodate
}
**/

///which style a worm should jump
//keep in sync with worm.lua
enum JumpMode {
    normal,      ///standard forward jump (return)
    smallBack,   ///little backwards jump (double return)
    backFlip,    ///large backwards jump/flip (double backspace)
    straightUp,  ///jump straight up (backspace)
}

//feedback worm -> controller (implemented by controller)
//xxx: there's also WormControl, but I want to remove WormController
interface WormController {
    WeaponTarget getTarget();

    //returns true if there is more ammo left
    bool reduceAmmo(Shooter sh);

    void firedWeapon(Shooter sh, bool refire);

    void doneFiring(Shooter sh);

    bool engaged();
}

const Time cWeaponLoadTime = timeMsecs(1500);

enum FlyMode {
    fall,
    slide,
    roll,
    heavy,
}

class WormSprite : Sprite {
    private {
        WormSpriteClass wsc;
        WormStateInfo mCurrentState; //must not be null

        float mWeaponAngle = 0, mFixedWeaponAngle = float.nan;
        int mThreewayMoving;

        //beam destination, only valid while state is st_beaming
        Vector2f mBeamDest;
        //cached movement, will be applied in simulate
        Vector2f mMoveVector;

        //selected weapon; not necessarily the displayed one
        WeaponClass mRequestedWeapon;

        //"code" for selected weapon, null for weapons which don't support it
        WeaponSelector mWeaponSelector;
        //active weapons
        Shooter mShooterMain, mShooterSec;

        Time mStandTime;

        //by default off, GameController can use this
        bool mDelayedDeath;

        int mGravestone;

        FlyMode mLastFlyMode;
        Time mLastFlyChange, mLastDmg;

        JumpMode mJumpMode;

        //null if not there, instantiated all the time it's needed
        RenderCrosshair mCrosshair;

        //that thing when you e.g. shoot a bazooka to set the fire strength
        bool mCharging;
        Time mChargingStarted;

        Time mWeaponTimer;

        PhysicConstraint mRope;
        void delegate(Vector2f mv) mRopeMove;
        bool mRopeCanRefire;
        bool mBlowtorchActive;
    }

    TeamTheme teamColor;

    WormController wcontrol;


    protected this(WormSpriteClass spriteclass) {
        super(spriteclass);
        wsc = spriteclass;
        setStateForced(wsc.st_stand);

        gravestone = 0;
    }

    WormStateInfo currentState() {
        assert(!!mCurrentState);
        return mCurrentState;
    }
    private void currentState(WormStateInfo n) {
        mCurrentState = n;
    }

    override protected void updateInternalActive() {
        super.updateInternalActive();
        if (internal_active) {
            setCurrentAnimation();
        }
    }

    override bool activity() {
        return super.activity() || mCharging
            || currentState == wsc.st_jump_start
            || currentState == wsc.st_beaming
            || currentState == wsc.st_reverse_beaming
            || currentState == wsc.st_getup
            || isDelayedDying;
    }

    void youWinNow() {
        setState(wsc.st_win);
    }

    //-PI/2..+PI/2, actual angle depends from whether worm looks left or right
    float weaponAngle() {
        if (mFixedWeaponAngle == mFixedWeaponAngle)
            return mFixedWeaponAngle;
        return mWeaponAngle;
    }

    private void updateWeaponAngle(float move) {
        WeaponClass wp = actualWeapon();
        if (!wp || !canReadjust())
            return;
        float old = weaponAngle;
        //xxx why is worm movement a float anyway?
        int moveInt = (move>float.epsilon) ? 1 : (move<-float.epsilon ? -1 : 0);
        mFixedWeaponAngle = float.nan;
        switch (wp.fireMode.direction) {
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
                if (wp.fireMode.direction == ThrowDirection.limit90) {
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
        if (old != weaponAngle) {
            updateAnimation();
            checkReadjust();
        }
    }

    //real weapon angle (normalized direction)
    Vector2f weaponDir() {
        return dirFromSideAngle(physics.lookey, weaponAngle);
    }

    //weaponDir with horizontal firing angle (only considers lookey)
    Vector2f weaponDirHor() {
        return dirFromSideAngle(physics.lookey, 0);
    }

    //if can move etc.
    bool haveAnyControl() {
        return isAlive() && currentState !is wsc.st_drowning;
    }

    void gravestone(int grave) {
        //assert(grave >= 0 && grave < wsc.gravestones.length);
        //mGravestone = wsc.gravestones[grave];
        mGravestone = grave;
    }

    void delayedDeath(bool delay) {
        mDelayedDeath = delay;
    }
    bool delayedDeath() {
        return mDelayedDeath;
    }

    /+
     + Death is a complicated thing. There are 4 possibilities (death states):
     +  1. worm is really REALLY alive
     +  2. worm is dead, but still sitting around on the landscape (HUD still
     +     displays >0 health points, although HP is usually <= 0)
     +     this is "delayed death", until the gamemode stuff actually triggers
     +     dying with checkDying()
     +  3. worm is dead and in the progress of suiciding (an animation is
     +     displayed, showing the worm blowing up itself)
     +  4. worm is really REALLY dead, and is not visible anymore
     +     (worm sprite gets replaced by a gravestone sprite)
     + For the game, the only difference between 1. and 2. is, that in 2. the
     + worm is not controllable anymore. In 2., the health points usually are
     + <= 0, but for the game logic (and physics etc.), the worm is still alive.
     + The worm can only be engaged in state 1.
     +
     + If delayed death is not enabled (with setDelayedDeath()), state 2 is
     + skipped.
     +
     + When the worm is drowning, it's still considered alive. (xxx: need to
     + implement this properly) The worm dies with state 4 when it reaches the
     + "death zone".
     +
     + Note the the health points amount can be > 0 even if the worm is dead.
     + e.g. when the worm drowned and died on the death zone.
     +/

    //death states: 1
    //true: alive and healthy
    //false: waiting for suicide, suiciding, or dead and removed from world
    bool isAlive() {
        return physics.lifepower > 0 && !physics.dead;
    }

    //death states: 2 and 3
    //true: waiting for suicide or suiciding
    //false: anything else
    bool isWaitingForDeath() {
        return !isAlive() && !isReallyDead();
    }

    //death states: 4
    //true: dead and removed from world
    //false: anything else
    bool isReallyDead()
    out (res) { assert(!res || (physics.lifepower < 0) || physics.dead); }
    body {
        return currentState is wsc.st_dead;
    }

    //if suicide animation played
    bool isDelayedDying() {
        return currentState is wsc.st_die;
    }

    void finallyDie() {
        if (isAlive())
            return;
        if (internal_active) {
            if (isDelayedDying())
                return;
            //assert(delayedDeath());
            assert(!isAlive());
            setState(wsc.st_die);
        }
    }

    override protected void onKill() {
        weapon_unselect();
        if (currentState !is wsc.st_dead)
            setState(wsc.st_dead);
        super.onKill();
    }

    protected void setCurrentAnimation() {
        if (!graphic)
            return;

        if (currentState is wsc.st_jump) {
            switch (mJumpMode) {
                case JumpMode.normal, JumpMode.smallBack, JumpMode.straightUp:
                    auto state = wsc.findSequenceState("jump_normal", true);
                    graphic.setState(state);
                    break;
                case JumpMode.backFlip:
                    auto state = wsc.findSequenceState("jump_backflip", true);
                    graphic.setState(state);
                    break;
                default:
                    assert(false, "Implement");
            }
            return; //?
        }

        graphic.setState(currentState.animation);
    }

    override protected void waterStateChange() {
        super.waterStateChange();
        //do something that involves an object and a lot of water
        if (isUnderWater) {
            setState(wsc.st_drowning);
        }
    }

    WeaponClass displayedWeapon() {
        WeaponClass curW = actualWeapon();
        if (currentState is wsc.st_weapon || allowFireSecondary() && curW) {
            return curW;
        }
        return null;
    }

    protected override void fillAnimUpdate() {
        super.fillAnimUpdate();
        graphic.weapon_angle = weaponAngle;
        //for jetpack
        graphic.selfForce = physics.selfForce;

        if (auto wp = displayedWeapon()) {
            char[] w = wp.animation;
            //right now, an empty string means "no weapon", but we mean
            //  "unknown weapon" (so a default animation is selected, not none)
            if (w == "") {
                w = "-";
            }
            graphic.weapon = w;
            graphic.weapon_firing = firing();
        } else {
            graphic.weapon = "";
        }

        //xxx there's probably a better place for this
        if (mWeaponSelector)
            mWeaponSelector.isSelected = currentState is wsc.st_weapon
                || currentState is wsc.st_rope || currentState is wsc.st_jet
                || currentState is wsc.st_parachute;
    }

    //movement for walking/jetpack
    void move(Vector2f dir) {
        mMoveVector = dir;
    }

    bool isBeaming() {
        return (currentState is wsc.st_beaming)
            || (currentState is wsc.st_reverse_beaming) ;
    }

    void beamTo(Vector2f npos) {
        //if (!isSitting())
        //    return; //only can beam when standing
        //log("beam to: {}", npos);
        //xxx: check and lock destination
        mBeamDest = npos;
        setState(wsc.st_beaming);
    }

    void abortBeaming() {
        if (isBeaming)
            //xxx is that enough? what about animation?
            setStateForced(wsc.st_stand);
    }

    void freeze(bool frozen) {
        if (frozen) {
            setState(wsc.st_frozen);
        } else {
            if (currentState is wsc.st_frozen)
                setStateForced(wsc.st_unfreeze);
        }
    }

    //overwritten from GObject.simulate()
    override void simulate() {
        physUpdate();

        super.simulate();

        if (currentState.onAnimationEnd && graphic) {
            //as requested by d0c, timing is dependend from the animation
            if (graphic.readyflag) {
                //log("state transition because of animation end");
                //time to change; the setState code will reset the animation
                setState(currentState.onAnimationEnd, true);
            }
        }

        setParticle(currentState.particle);

        float weaponMove;
        //check if the worm is really allowed to move
        if (currentState.canAim) {
            //invert y to go from screen coords to math coords
            weaponMove = -mMoveVector.y;
        }
        if (wormCanWalkJump()) {
            physics.setWalking(mMoveVector);
        }
        if (currentState is wsc.st_rope) {
            mRopeMove(mMoveVector);
        }

        //when user presses key to change weapon angle
        //can rotate through all 180 degrees in 5 seconds
        //(given abs(weaponMove) == 1)
        updateWeaponAngle(weaponMove);

        //fun fact: I have not the slightest clue what this code is doing
        //... and yet I'm hacking it!
        if (isStanding() && actualWeapon() && wcontrol.engaged()) {
            if (mStandTime == Time.Never)
                mStandTime = engine.gameTime.current;
            //worms are not standing, they are FIGHTING!
            if (engine.gameTime.current - mStandTime > timeMsecs(350)) {
                setState(wsc.st_weapon);
            }
        } else {
            mStandTime = Time.Never;
        }

        auto strength = currentFireStrength();
        if (mCrosshair) {
            mCrosshair.setLoad(strength);
        }
        //xxx replace comparision by checking against the time, with a small
        //  delay before actually shooting (like wwp does)
        if (mCharging && strength == 1.0f)
            fire(true);

        //if shooter dies, undraw weapon
        //xxx doesn't work yet, shooter starts as active=false (wtf)
        //if (mWeapon && !mWeapon.active)
          //  shooter = null;

        updateCrosshair();
    }

    void jump(JumpMode m) {
        if (wormCanWalkJump()) {
            mJumpMode = m;
            setState(wsc.st_jump_start);
        } else if (currentState is wsc.st_jump_start) {
            //double-click
            if (mJumpMode == JumpMode.normal) mJumpMode = JumpMode.smallBack;
            if (mJumpMode == JumpMode.straightUp) mJumpMode = JumpMode.backFlip;
        }
    }

    private bool wormCanWalkJump() {
        return currentState.canWalk && !mCharging
            //no walk while shooting (or charging)
            && (!mShooterMain || !mShooterMain.isFixed);
    }

    //if worm is firing
    final bool firing() {
        //xxx: I'm not sure about the secondary shooter
        return !!mShooterMain && !allowAlternate();
    }

    //"careful" common code for unselecting a weapon
    private void weapon_unselect() {
        if (mWeaponSelector) {
            mWeaponSelector.isSelected = false;
            mWeaponSelector = null;
        }
        mCharging = false;
        //xxx
        //mRequestedWeapon = null;
        //I don't know if mWeaponTimer should be changed or what
    }

    //xxx: clearify relationship between shooter and so on
    void weapon(WeaponClass w) {
        if (w && w is mRequestedWeapon)
            return;
        auto oldweapon = actualWeapon();
        mRequestedWeapon = w;
        update_actual_weapon(oldweapon);
    }

    //by definition called when the return value of actualWeapon() will change
    //oldweapon is the previous value of actualWeapon()
    private void update_actual_weapon(WeaponClass oldweapon) {
        WeaponClass w = actualWeapon();

        if (w is oldweapon)
            return;

        weapon_unselect();

        if (w) {
            mWeaponSelector = w.createSelector(this);
            if (currentState is wsc.st_stand)
                setState(wsc.st_weapon);
            if (mWeaponTimer == Time.Null)
                //xxx should this be configurable?
                mWeaponTimer = (w.fireMode.timerFrom+w.fireMode.timerTo)/2;
            updateCrosshair();
            //replay the cross-moves-out animation
            if (mCrosshair && w !is oldweapon && !firing) {
                mCrosshair.reset();
            }
        } else {
            mWeaponTimer = Time.Null;
            if (!firing) {
                if (currentState is wsc.st_weapon)
                    setState(wsc.st_stand);
            }
        }
    }

    //the weapon that is selected or being fired
    //this is the weapon that is displayed (either with the worm in stand state,
    //  or firing the weapon; also the weapon returned here doesn't have to be
    //  visible; e.g. if the worm is walking around or anything else)
    final WeaponClass actualWeapon() {
        return firing ? mShooterMain.weapon : mRequestedWeapon;
    }

    //weapon requested by the last select weapon command
    //example: user fires minigun, and during firing selects another weapon;
    //  then actualWeapon==minigun, requestedWeapon==otherweapon
    //  when firing finishes, actualWeapon==requestedWeapon==otherweapon
    final WeaponClass requestedWeapon() {
        return mRequestedWeapon;
    }

    //returns the weapon that would activate/refire when pressing space
    WeaponClass wouldFire(bool refire = false) {
        if (mShooterSec && mShooterSec.activity && refire)
            return mShooterSec.weapon;
        if (allowFireSecondary())
            return requestedWeapon;
        if (mShooterMain && mShooterMain.activity && refire)
            return mShooterMain.weapon;
        if (currentState.canFire)
            return requestedWeapon;
        return null;
    }

    WeaponClass altWeapon() {
        if (allowAlternate()) {
            return mShooterMain.weapon;
        }
        return null;
    }

    //fire (or refire) the selected weapon
    //returns if firing could be started
    bool fire(bool keyUp = false, bool selectedOnly = false) {
        auto wp = requestedWeapon();

        //1. Try to refire currently active secondary weapon
        if (mShooterSec && mShooterSec.activity) {
            //think of firing a supersheep on a rope
            if (!keyUp)
                return refireWeapon(mShooterSec);
            return false;
        }

        //2. Try to fire selected weapon as new secondary
        if (allowFireSecondary()) {
            //secondary fire is possible, so do that instead
            //  (main weapon could only be refired here)
            if (keyUp || !wp)
                return false;

            //no variable strength here, fixed angle
            return fireWeapon(mShooterSec, wp.fireMode.throwStrengthFrom,
                true);
        }

        //3. Try to refire active main weapon
        if (mShooterMain && mShooterMain.activity()) {
            //this is ONLY for the "selectandfire" command, e.g. it would
            //  be quite annoying to accidentally blow a sally army when
            //  pressing J
            if (selectedOnly && wp && mShooterMain.weapon !is wp)
                return true;
            //don't refire jetpack/rope on space (you would accidentally
            //  disable it when running out of ammo)
            if (mShooterMain.weapon.allowSecondary && !selectedOnly)
                return true;
            if (!keyUp) {
                return refireWeapon(mShooterMain);
            }
            return false;
        }

        //4. Try to fire selected weapon as main weapon
        if (!wp)
            return false;
        //check if in wrong state, like flying around
        if (!currentState.canFire)
            return false;
        if (currentState is wsc.st_stand)
            //draw weapon
            setState(wsc.st_weapon);

        if (!keyUp) {
            //start firing
            if (wp.fireMode.variableThrowStrength) {
                //fire strength
                mCharging = true;
                mChargingStarted = engine.gameTime.current;
                //xxx: not sure how to deal with firing success etc.
                return true;
            } else {
                //fire instantly with default strength
                return fireWeapon(mShooterMain,
                    wp.fireMode.throwStrengthFrom);
            }
        } else {
            //fire key released, really fire variable-strength weapon
            if (!mCharging)
                return false;
            auto strength = currentFireStrength();
            mCharging = false;
            auto fm = wp.fireMode;
            return fireWeapon(mShooterMain, fm.throwStrengthFrom + strength
                * (fm.throwStrengthTo-fm.throwStrengthFrom));
        }

        assert(false, "never reached");
    }

    //alternate fire refires the active main weapon if it can't be refired
    //with the main button because a secondary weapon needs the control
    bool fireAlternate() {
        if (!allowAlternate())
            return false;

        //pressed fire button again while shooter is active,
        //so don't fire another round but let the shooter handle it
        return refireWeapon(mShooterMain);
    }

    //would the alternate-fire-button have an effect
    bool allowAlternate() {
        return mShooterMain && mShooterMain.activity()
            && mShooterMain.weapon.allowSecondary;
    }

    //allow firing the current weapon as secondary weapon
    bool allowFireSecondary() {
        //main shooter is active and shooter's weapon allows secondary weapons
        //also, can't fire a weapon allowing secondary weapons (jetpack) here
        //note that possibly mShooterMain.weapon != mRequestedWeapon
        return mShooterMain && mShooterMain.activity()
            && mShooterMain.weapon.allowSecondary
            && mRequestedWeapon && !mRequestedWeapon.allowSecondary;
    }

    void setWeaponTimer(Time t) {
        //range checked when actually firing
        mWeaponTimer = t;
    }

    //return the fire strength value, always between 0.0 and 1.0
    private float currentFireStrength() {
        if (!mCharging)
            return 0;
        auto diff = engine.gameTime.current - mChargingStarted;
        float s = cast(double)diff.msecs / cWeaponLoadTime.msecs;
        return clampRangeC(s, 0.0f, 1.0f);
    }

    private void checkReadjust() {
        if (mShooterMain && mShooterMain.activity)
            mShooterMain.readjust(weaponDir());
        if (mShooterSec && mShooterSec.activity)
            mShooterSec.readjust(weaponDirHor());
    }

    private bool canReadjust() {
        if (mShooterSec && mShooterSec.activity)
            return mShooterSec.canReadjust();
        if (mShooterMain && mShooterMain.activity)
            return mShooterMain.canReadjust();
        //no weapon active, allow normal aiming
        return true;
    }

    //fire currently selected weapon (mRequestedWeapon) as main weapon
    //will also create the shooter if necessary
    private bool fireWeapon(ref Shooter sh, float strength,
        bool fixedDir = false)
    {
        if (!mRequestedWeapon)
            return false;
        //xxx shooter is removed when the weapon is inactive?
        if (!sh || sh.weapon != mRequestedWeapon) {
            auto oldweapon = actualWeapon();
            sh = mRequestedWeapon.createShooter(this);
            sh.selector = mWeaponSelector;
            update_actual_weapon(oldweapon);
        }

        //log("fire: {}", mRequestedWeapon.name);

        FireInfo info;
        if (fixedDir)
            info.dir = weaponDirHor();
        else
            info.dir = weaponDir();
        info.strength = strength;
        //possibly add worm speed (but we don't want to lose dir if str == 0)
        if (strength > float.epsilon
            && physics.velocity.quad_length > float.epsilon)
        {
            Vector2f fDir = info.dir*strength + physics.velocity;
            float s = fDir.length;
            //worm speed and strength might add up to exactly 0 (nan check)
            if (s > float.epsilon) {
                info.strength = s;
                info.dir = fDir/s;
            }
        }
        info.timer = clampRangeC(mWeaponTimer, sh.weapon.fireMode.timerFrom,
            sh.weapon.fireMode.timerTo);
        if (wcontrol)
            info.pointto = wcontrol.getTarget;
        else
            info.pointto = physics.pos;
        sh.ammoCb = &reduceAmmo;
        sh.finishCb = &shooterFinish;
        //for wcontrol.firedWeapon: sh.fire might complete in one call and
        //  reset sh
        auto shTmp = sh;
        bool success = sh.fire(info);

        if (!success)
            return false;

        if (wcontrol)
            wcontrol.firedWeapon(shTmp, false);

        //update animation, so that fire animation is displayed
        //should only be done if this is the mShooterMain (this is a guess)
        //xxx: this check is a bit dirty, but...
        if (&sh is &mShooterMain && graphic) {
            //even if the weapon isn't "one shot", this should be fine
            graphic.weapon_fire_oneshot = true;
        }

        return true;
    }

    private bool refireWeapon(Shooter sh) {
        assert(!!sh);
        if (sh.refire()) {
            if (wcontrol)
                wcontrol.firedWeapon(sh, true);
            return true;
        }
        return false;
    }

    //callback from shooter when a round was fired
    private bool reduceAmmo(Shooter sh) {
        if (wcontrol)
            return wcontrol.reduceAmmo(sh);
        return true;
    }

    private void shooterFinish(Shooter sh) {
        auto oldweapon = actualWeapon();

        /+ never happens?
        if (!mRequestedWeapon) {
            //check for delayed state change weapon->stand because
            //main weapon was unset
            //xxx is this case even possible?
            if (!mShooterMain || !mShooterMain.activity) {
                if (currentState is wsc.st_weapon) {
                    setState(wsc.st_stand);
                }
            }
        }
        +/

        if (wcontrol)
            wcontrol.doneFiring(sh);
        if (sh is mShooterMain)
            mShooterMain = null;
        if (sh is mShooterSec)
            mShooterSec = null;
        //main shooter (e.g. jetpack) finishes while secondary (e.g. sheep)
        //still active -> swap them
        if (!mShooterMain && mShooterSec)
            swap(mShooterMain, mShooterSec);
        //shooter is done, so check if we need to switch animation
        //---setCurrentAnimation();
        //---updateCrosshair();

        update_actual_weapon(oldweapon);
    }

    private void updateCrosshair() {
        //--better don't touch it while firing...
        //--if (shooting())
        //--    return;
        //create/destroy the target cross
        bool exists = !!mCrosshair;
        bool shouldexist = false;
        WeaponClass wp = actualWeapon();
        if (currentState.canAim && wp) {
            //xxx special cases not handled, just turns on/off crosshair
            shouldexist = wp.fireMode.direction != ThrowDirection.fixed &&
                !allowAlternate();
        }
        if (exists != shouldexist) {
            if (exists) {
                mCrosshair.removeThis();
                mCrosshair = null;
            } else {
                mCrosshair = new RenderCrosshair(engine, graphic);
                engine.scene.add(mCrosshair);
            }
        }
    }

    bool delayedAction() {
        bool ac = mCharging;
        if (mShooterMain)
            ac |= mShooterMain.delayedAction;
        if (mShooterSec)
            ac |= mShooterSec.delayedAction;
        return ac;
    }

    void forceAbort() {
        if (mShooterSec && mShooterSec.activity)
            mShooterSec.interruptFiring();
        if (mShooterMain && mShooterMain.activity)
            mShooterMain.interruptFiring();
        abortBeaming();
        weapon_unselect();
    }

    protected void stateTransition(WormStateInfo from,
        WormStateInfo to)
    {

        if (from is wsc.st_beaming) {
            setPos(mBeamDest);
        }

        if (to is wsc.st_fly) {
            //whatever, when you beam the worm into the air
            //xxx replace by propper handing in physics.d
            physics.doUnglue();
        }
        if (to is wsc.st_jump) {
            auto look = Vector2f.fromPolar(1, physics.lookey);
            look.y = 0;
            look = look.normal(); //get sign *g*
            look.y = 1;
            physics.addImpulse(look.mulEntries(wsc.jumpStrength[mJumpMode]));
        }

        //die by blowing up
        if (to is wsc.st_dead) {
            bool was_alive = objectAlive();
            kill();
            //only show if it didn't die in deathzone
            //(the only reason this check is needed is because simulate() is
            //  somehow called when updating the graphic when kill() is called)
            if (was_alive) {
                //explosion!
                engine.explosionAt(physics.pos, wsc.suicideDamage, this);
                SpriteClass findGrave(int id) {
                    return engine.resources.get!(SpriteClass)
                        (myformat("x_gravestone{}", mGravestone), true);
                }
                auto graveclass = findGrave(mGravestone);
                if (!graveclass) //try to default to first gravestone
                    graveclass = findGrave(0);
                //no gravestone if not available?
                if (graveclass) {
                    auto grave = graveclass.createSprite();
                    grave.createdBy = this;
                    grave.activate(physics.pos);
                }
            }
        }

        //stop movement if not possible
        if (!currentState.canWalk) {
            physics.setWalking(Vector2f(0));
        }
        if (!currentState.canFire) {
            mCharging = false;
        }
    }

    void setState(WormStateInfo nstate, bool for_end = false) {
        if (nstate is wsc.st_stand &&
            (currentState is wsc.st_fly || currentState is wsc.st_jump ||
            currentState is wsc.st_jump_to_fly))
        {
            nstate = wsc.st_getup;
        }
        //if (nstate !is wsc.st_stand)
          //  Trace.formatln(nstate.name);

        if (currentState is nstate)
            return;

        if (currentState.noleave && !for_end)
            return;

        if (for_end) {
            assert(nstate is currentState.onAnimationEnd);
        }

        //log("state {} -> {}", currentState.name, nstate.name);

        auto oldstate = currentState;
        currentState = nstate;
        physics.posp = nstate.physic;
        //stop all induced forces (e.g. jetpack)
        physics.selfForce = Vector2f(0);

        stateTransition(oldstate, currentState);
        //if this fails, maybe stateTransition called setState()?
        assert(currentState is nstate);

        if (graphic) {
            setCurrentAnimation();
            updateAnimation();
        }

        //and particles
        updateParticles();

        //update water state (to catch an underwater state transition)
        waterStateChange();
    }

        //do as less as necessary to force a new state
    void setStateForced(WormStateInfo nstate) {
        assert(nstate !is null);

        currentState = nstate;
        physics.posp = nstate.physic;
        //stop all induced forces (e.g. jetpack)
        physics.selfForce = Vector2f(0);
        if (graphic) {
            setCurrentAnimation();
            updateAnimation();
        }

        //log("force state: {}", nstate.name);

        waterStateChange();
    }

    bool jetpackActivated() {
        return currentState is wsc.st_jet;
    }

    //activate = activate/deactivate the jetpack
    void activateJetpack(bool activate) {
        if (activate == jetpackActivated())
            return;

        //lolhack: return to stand state, and if that's wrong (i.e. jetpack
        //  deactivated in sky), other code will immediately correct the state
        WormStateInfo wanted = activate ? wsc.st_jet : wsc.st_stand;
        setState(wanted);
    }

    bool ropeActivated() {
        return currentState is wsc.st_rope;
    }

    void activateRope(void delegate(Vector2f mv) ropeMove) {
        if (!!ropeMove == ropeActivated())
            return;

        mRopeMove = ropeMove;
        WormStateInfo wanted = !!ropeMove ? wsc.st_rope : wsc.st_stand;
        setState(wanted);
        physics.doUnglue();
        physics.resetLook();
        if (!ropeMove)
            mRopeCanRefire = true;
    }

    bool ropeCanRefire() {
        return mRopeCanRefire;
    }

    //xxx need another solution etc.
    bool drillActivated() {
        return currentState is wsc.st_drill;
    }
    void activateDrill(bool activate) {
        if (activate == drillActivated())
            return;

        setState(activate ? wsc.st_drill : wsc.st_stand);
        physics.doUnglue();
    }
    bool blowtorchActivated() {
        return currentState is wsc.st_blowtorch;
    }
    void activateBlowtorch(bool activate) {
        if (activate == blowtorchActivated())
            return;

        setState(activate ? wsc.st_blowtorch : wsc.st_stand);
        if (activate)
            physics.setWalking(weaponDirHor, true);
        else
            physics.setWalking(Vector2f(0, 0));
    }
    bool parachuteActivated() {
        return currentState is wsc.st_parachute;
    }
    void activateParachute(bool activate) {
        if (activate == parachuteActivated())
            return;

        setState(activate ? wsc.st_parachute : wsc.st_stand);
    }
    private bool hasParachute() {
        WeaponClass wp = actualWeapon();
        //xxx wow, that's an ugly hack... but who cares
        return wp && wp.name == "parachute";
    }

    bool isStanding() {
        return currentState is wsc.st_stand;
    }
    bool isFlying() {
        return currentState is wsc.st_fly;
    }

    private void setFlyAnim(FlyMode m) {
        if (!graphic)
            return;
        if (currentState is wsc.st_fly) {
            //going for roll or heavy flight -> look in flying direction
            if (m == FlyMode.roll || m == FlyMode.heavy)
                physics.resetLook();
            //don't change to often
            if (m < mLastFlyMode &&
                engine.gameTime.current - mLastFlyChange < timeMsecs(200))
                return;
            graphic.setState(wsc.flyState[m]);
            mLastFlyChange = engine.gameTime.current;
            mLastFlyMode = m;
        }
    }

    override protected void physImpact(PhysicObject other, Vector2f normal) {
        super.physImpact(other, normal);
        mRopeCanRefire = false;
        if (currentState is wsc.st_fly) {
            //impact -> roll
            if (physics.velocity.length >= wsc.rollVelocity)
                setFlyAnim(FlyMode.roll);
            else
                //too slow? so use slide animation
                //xxx not so sure about that
                setFlyAnim(FlyMode.slide);
        }
        if (currentState is wsc.st_rope && !other) {
            if (mMoveVector.x != 0)
                physics.addImpulse(normal*wsc.ropeImpulse);
        }
        if (currentState is wsc.st_parachute) {
            activateParachute(false);
        }
    }

    override protected void physDamage(float amout, DamageCause type,
        Object cause)
    {
        super.physDamage(amout, type, cause);
        mRopeCanRefire = false;
        if (type != DamageCause.explosion)
            return;
        if (currentState is wsc.st_fly) {
            //when damaged in-flight, switch to heavy animation
            //xxx better react to impulse rather than damage
            //setFlyAnim(FlyMode.heavy);
        } else {
            //hit by explosion, abort everything (code below will immediately
            //  correct the state)
            setState(wsc.st_stand);
            //xxx how to remove rope constraint here?
        }
        mLastDmg = engine.gameTime.current;
    }

    private void physUpdate() {
        if (isDelayedDying)
            return;

        if (!jetpackActivated && !blowtorchActivated && !parachuteActivated) {
            //update walk animation
            if (physics.isGlued) {
                bool walkst = currentState is wsc.st_walk;
                if (walkst != physics.isWalking)
                    setState(physics.isWalking ? wsc.st_walk : wsc.st_stand);
                mRopeCanRefire = false;
            }

            //update if worm is flying around...
            bool onGround = currentState.isGrounded;
            if (physics.isGlued != onGround) {
                setState(physics.isGlued ? wsc.st_stand : wsc.st_fly);
                //recent damage -> ungluing possibly caused by explosion
                //xxx better physics feedback
                if (engine.gameTime.current - mLastDmg < timeMsecs(100))
                    setFlyAnim(FlyMode.heavy);
            }
            if (currentState is wsc.st_fly && graphic) {
                //worm is falling to fast -> use roll animation
                if (physics.velocity.length >= wsc.rollVelocity)
                    if (graphic.currentState is wsc.flyState[FlyMode.fall]
                        || graphic.currentState is
                            wsc.flyState[FlyMode.slide])
                    {
                        setFlyAnim(FlyMode.roll);
                    }
                //special check for parachute, this is hacky
                if (physics.velocity.y >= wsc.rollVelocity*0.8f && !mShooterMain
                    && hasParachute())
                {
                    //worm is falling fast enough -> skip all checks and fire
                    //  parachute
                    //xxx hasParachute() should have checked the parachute
                    //    weapon is selected, but this is still ugly
                    fireWeapon(mShooterMain, 0);
                }
            }
            if (currentState is wsc.st_jump && physics.velocity.y > 0) {
                setState(wsc.st_jump_to_fly);
            }

        }
        if (blowtorchActivated && !physics.isWalking()) {
            setState(wsc.st_stand);
        }
        checkReadjust();
        //check death
        if (internal_active && !isAlive() && !delayedDeath()) {
            finallyDie();
        }
    }
}

//contains custom state attributes for worm sprites
class WormStateInfo {
    char[] name;

    POSP physic;

    //automatic transition to this state if animation finished
    WormStateInfo onAnimationEnd;
    //don't leave this state (explictly excludes onAnimationEnd)
    bool noleave = false;

    SequenceState animation;

    //if non-null, always ensure a single particle like this is created
    //this normally should be an invisible particle emitter
    ParticleType particle;

    bool isGrounded = false;    //is this a standing-on-ground state
    bool canWalk = false;       //should the worm be allowed to walk
    bool canAim = false;        //can the target cross be moved
    bool canFire = false;       //can the main weapon be fired

    this (char[] a_name) {
        name = a_name;
    }
}

//the factories work over the sprite classes, so we need one
class WormSpriteClass : SpriteClass {
    WormStateInfo[char[]] states;

    float suicideDamage;
    //SequenceObject[] gravestones;
    Vector2f[JumpMode.max+1] jumpStrength;
    Vector2f[] jumpStrengthScript; //no static arrays with Lua wrapper
    float rollVelocity = 400;
    float ropeImpulse = 700;

    WormStateInfo st_stand, st_fly, st_walk, st_jet, st_weapon, st_dead,
        st_die, st_drowning, st_beaming, st_reverse_beaming, st_getup,
        st_jump_start, st_jump, st_jump_to_fly, st_rope, st_drill, st_blowtorch,
        st_parachute, st_win, st_frozen, st_unfreeze;

    //alias WormSprite.FlyMode FlyMode;

    SequenceState[FlyMode.max+1] flyState;

    this(GameCore e, char[] r) {
        super(e, r);

        initNoActivityWhenGlued = true;

        WormStateInfo state(char[] name) {
            assert(!(name in states));
            auto nstate = new WormStateInfo(name);
            states[name] = nstate;
            return nstate;
        }

        st_stand = state("stand");
        st_fly = state("fly");
        st_walk = state("walk");
        st_jet = state("jetpack");
        st_weapon = state("weapon");
        st_dead = state("dead");
        st_die = state("die");
        st_drowning = state("drowning");
        st_beaming = state("beaming");
        st_reverse_beaming = state("reverse_beaming");
        st_getup = state("getup");
        st_jump_start = state("jump_start");
        st_jump = state("jump");
        st_jump_to_fly = state("jump_to_fly");
        st_rope = state("rope");
        st_drill = state("drill");
        st_blowtorch = state("blowtorch");
        st_parachute = state("parachute");
        st_win = state("win");
        st_frozen = state("frozen");
        st_unfreeze = state("unfreeze");
    }

    void finishLoading() {
        flyState[FlyMode.fall] = findSequenceState("fly_fall",true);
        flyState[FlyMode.slide] = findSequenceState("fly_slide",true);
        flyState[FlyMode.roll] = findSequenceState("fly_roll",true);
        flyState[FlyMode.heavy] = findSequenceState("fly_heavy",true);

        //be aware that D has no array bounds checking in release mode
        //if not careful, a script could make D read past the end of an array
        //also the reason why the actual jumpStrength array is still static
        if (jumpStrengthScript.length == JumpMode.max+1) {
            jumpStrength[] = jumpStrengthScript;
        } else {
            throw new CustomException("jumpStrength invalid");
        }
    }

    override WormSprite createSprite() {
        return new WormSprite(this);
    }

    WormStateInfo findState(char[] name) {
        WormStateInfo* state = name in states;
        if (!state) {
            //xxx better error handling
            throw new CustomException("state "~name~" not found");
        }
        return *state;
    }

    SequenceState findSequenceState(char[] name,
        bool allow_not_found = false)
    {
        //something in projectile.d seems to need this special case?
        if (!sequenceType) {
            if (allow_not_found)
                return null;
            assert(false, "bla.: "~name);
        }
        return sequenceType.findState(name, allow_not_found);
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

        struct InterpolateState {
            bool did_init;
            InterpolateExp!(float, 4.25f) interp;
        }
    }

    this(GameCore a_engine, Sequence a_attach) {
        mEngine = a_engine;
        mGfx = mEngine.singleton!(GfxSet)();
        mAttach = a_attach;
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

        //xxx: forgot what this was about
        /+
        //NOTE: in this case, the readyflag is true, if the weapon is already
        // fully rotated into the target direction
        bool nactive = true; //mAttach.readyflag;
        if (mTarget.active != nactive) {
            mTarget.active = nactive;
            if (nactive)
                reset();
        }
        +/

        Sequence infos = mAttach;
        //xxx make this restriction go away?
        assert(!!infos,"Can only attach a target cross to worm sprites");
        auto pos = mAttach.interpolated_position; //toVector2i(infos.position);
        auto angle = fullAngleFromSideAngle(infos.rotation_angle,
            infos.weapon_angle);
        //normalized weapon direction
        auto dir = Vector2f.fromPolar(1.0f, angle);

        //crosshair animation
        auto target_offset = tcs.targetDist - tcs.targetStartDist;
        //xxx reset on weapon change
        Vector2i target_pos = pos + toVector2i(dir * (tcs.targetDist
            - target_offset*mIP.interp.value));
        AnimationParams ap;
        ap.p1 = cast(int)((angle + 2*PI*mIP.interp.value)*180/PI);
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
