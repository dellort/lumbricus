module game.worm;

import framework.framework;
import game.gobject;
import game.animation;
import physics.world;
import game.game;
import game.gfxset;
import game.sequence;
import game.sprite;
import game.weapon.types;
import game.weapon.weapon;
import game.temp;  //whatever, importing gamepublic doesn't give me JumpMode
import game.gamepublic;
import utils.misc;
import utils.vector2;
import utils.time;
import utils.log;
import utils.misc;
import utils.math;
import utils.configfile;
import utils.reflection;
import tango.math.Math;

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

interface WormController {
    Vector2f getTarget();

    void reduceAmmo(Shooter sh);

    void firedWeapon(Shooter sh, bool refire);

    void doneFiring(Shooter sh);
}

const Time cWeaponLoadTime = timeMsecs(1500);

enum FlyMode {
    fall,
    slide,
    roll,
    heavy,
}

class WormSprite : GObjectSprite {
    private {
        WormSpriteClass wsc;

        float mWeaponAngle = 0, mFixedWeaponAngle = float.nan;
        int mThreewayMoving;

        //beam destination, only valid while state is st_beaming
        Vector2f mBeamDest;
        //cached movement, will be applied in simulate
        Vector2f mMoveVector;

        //selected weapon
        WeaponClass mWeapon;
        Shooter mShooterMain, mShooterSec;
        Time mStandTime;

        //by default off, GameController can use this
        bool mDelayedDeath;

        bool mIsDead, mHasDrowned;

        int mGravestone;

        bool mWeaponAsIcon;

        FlyMode mLastFlyMode;
        Time mLastFlyChange, mLastDmg;

        JumpMode mJumpMode;

        //null if not there, instantiated all the time it's needed
        CrosshairGraphic mCrosshair;

        //that thing when you e.g. shoot a bazooka to set the fire strength
        bool mThrowing;
        Time mThrowingStarted;

        Time mWeaponTimer;

        //same like seqUpdate, but the exact type (I haet casting)
        WormSequenceUpdate wseqUpdate;

        PhysicConstraint mRope;
        void delegate(Vector2f mv) mRopeMove;
        bool mRopeCanRefire;
        bool mBlowtorchActive;
    }

    TeamTheme teamColor;

    WormController wcontrol;

    override bool activity() {
        return super.activity() || mThrowing
            || currentState == wsc.st_jump_start
            || currentState == wsc.st_beaming
            || currentState == wsc.st_reverse_beaming
            || currentState == wsc.st_getup
            || isDelayedDying;
    }

    //-PI/2..+PI/2, actual angle depends from whether worm looks left or right
    float weaponAngle() {
        if (mFixedWeaponAngle == mFixedWeaponAngle)
            return mFixedWeaponAngle;
        return mWeaponAngle;
    }

    private void updateWeaponAngle(float move) {
        if (!mWeapon)
            return;
        float old = weaponAngle;
        //xxx why is worm movement a float anyway?
        int moveInt = (move>float.epsilon) ? 1 : (move<-float.epsilon ? -1 : 0);
        mFixedWeaponAngle = float.nan;
        switch (mWeapon.fireMode.direction) {
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
                if (mWeapon.fireMode.direction == ThrowDirection.limit90) {
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
        return !isDead();
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

    //if object wants to die; if true, call finallyDie() (etc.)
    //actually, object can have any state, it even can be dead
    //you should prefer isDead()
    bool shouldDie() {
        return physics.lifepower <= 0;
    }

    //if worm is dead (including if worm is waiting to commit suicide)
    bool isDead() {
        return shouldDie() || isReallyDead();
    }
    //less strict than isDead(): return false for not-yet-suicided worms
    //but true for suiciding worms
    bool isReallyDead() {
        return mIsDead;
    }
    //returns true if suiciding is also done
    bool isReallyReallyDead() {
        return mIsDead && currentState is wsc.st_dead;
    }

    //true if worm has died by drowning (may still be floating down)
    bool hasDrowned() {
        return isReallyDead() && mHasDrowned;
    }

    //if suicide animation played
    bool isDelayedDying() {
        return isReallyDead() && currentState is wsc.st_die;
    }

    void finallyDie() {
        if (active) {
            if (isDelayedDying())
                return;
            //assert(delayedDeath());
            assert(shouldDie());
            setState(wsc.st_die);
        }
    }

    override protected void die() {
        //just to be safe
        mIsDead = true;
        super.die();
    }

    protected this (GameEngine engine, WormSpriteClass spriteclass) {
        super(engine, spriteclass);
        wsc = spriteclass;

        gravestone = 0;
    }

    this (ReflectCtor c) {
        super(c);
        c.types().registerMethod(this, &physDamage, "physDamage");
        c.types().registerMethod(this, &physImpact, "physImpact");
        c.types().registerMethod(this, &shooterFinish, "shooterFinish");
        c.types().registerMethod(this, &reduceAmmo, "reduceAmmo");
    }

    protected override void setCurrentAnimation() {
        if (!graphic)
            return;

        if (currentState is wsc.st_weapon) {
            auto curW = mWeapon;
            if (mShooterMain && mShooterMain.activity)
                curW = mShooterMain.weapon;
            assert(!!curW);

            char[] w = curW.animations[WeaponWormAnimations.Arm];
            auto state = wsc.findSequenceState(w, true);
            bool noState = !state;
            if (noState) {
                //no specific weapon animation there
                state = wsc.findSequenceState("weapon_unknown");
            }
            mWeaponAsIcon = noState || curW !is mWeapon;
            graphic.setState(state);
            return;
        }
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
        super.setCurrentAnimation();
    }

    protected override void createSequenceUpdate() {
        seqUpdate = wseqUpdate = new WormSequenceUpdate();
    }

    protected override void fillAnimUpdate() {
        super.fillAnimUpdate();
        assert(!!wseqUpdate);
        wseqUpdate.pointto_angle = weaponAngle;
        //for jetpack
        wseqUpdate.selfForce = physics.selfForce;
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
        log("beam to: {}", npos);
        //xxx: check and lock destination
        mBeamDest = npos;
        setState(wsc.st_beaming);
    }

    void abortBeaming() {
        if (isBeaming)
            //xxx is that enough? what about animation?
            setStateForced(wsc.st_stand);
    }

    //overwritten from GObject.simulate()
    override void simulate(float deltaT) {
        physUpdate();

        super.simulate(deltaT);

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

        if (isStanding() && mWeapon) {
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
        if (mThrowing && strength == 1.0f)
            fire(true);

        //if shooter dies, undraw weapon
        //xxx doesn't work yet, shooter starts as active=false (wtf)
        //if (mWeapon && !mWeapon.active)
          //  shooter = null;
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
        return currentState.canWalk && !mThrowing
            //no walk while shooting (or charging)
            && (!mShooterMain || !mShooterMain.isFixed);
    }

    //if weapon needs to be displayed outside the worm
    bool displayWeaponIcon() {
        //two cases here: a) we are in weapon state, but have no animation
        bool show = currentState is wsc.st_weapon && mWeaponAsIcon;
        //b) main weapon is busy, but secondary is ready
        //   (meaning worm animation is showing primary weapon)
        show |= allowFireSecondary();
        return show;
    }

    //xxx: clearify relationship between shooter and so on
    void weapon(WeaponClass w) {
        auto oldweapon = mWeapon;
        mWeapon = w;
        mThrowing = false;
        if (w) {
            if (currentState is wsc.st_stand)
                setState(wsc.st_weapon);
            if (mWeaponTimer == Time.Null)
                //xxx should this be configurable?
                mWeaponTimer = (w.fireMode.timerFrom+w.fireMode.timerTo)/2;
            //xxx: if weapon is changed, play the correct animations
            setCurrentAnimation();
            updateCrosshair();
            //replay the cross-moves-out animation
            if (mCrosshair && mWeapon !is oldweapon) {
                mCrosshair.reset();
            }
        } else {
            mWeaponTimer = Time.Null;
            if (!mShooterMain || !mShooterMain.activity) {
                if (currentState is wsc.st_weapon)
                    setState(wsc.st_stand);
            }
        }
    }
    WeaponClass weapon() {
        return mWeapon;
    }
    //returns the weapon that would activate/refire when pressing space
    WeaponClass firedWeapon(bool refire = false) {
        if (mShooterSec && mShooterSec.activity && refire)
            return mShooterSec.weapon;
        if (allowFireSecondary())
            return mWeapon;
        if (mShooterMain && mShooterMain.activity && refire)
            return mShooterMain.weapon;
        if (currentState.canFire)
            return mWeapon;
        return null;
    }

    //fire (or refire) the selected weapon (mWeapon)
    bool fire(bool keyUp = false, bool selectedOnly = false) {
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
            if (keyUp || !mWeapon)
                return false;

            //no variable strength here, fixed angle
            fireWeapon(mShooterSec, mWeapon.fireMode.throwStrengthFrom, true);
            return true;
        }

        //3. Try to refire active main weapon
        if (mShooterMain && mShooterMain.activity()) {
            //this is ONLY for the "selectandfire" command, e.g. it would
            //  be quite annoying to accidentally blow a sally army when
            //  pressing J
            if (selectedOnly && mWeapon && mShooterMain.weapon !is mWeapon)
                return true;
            if (!keyUp) {
                return refireWeapon(mShooterMain);
            }
            return false;
        }

        //4. Try to fire selected weapon as main weapon
        if (!mWeapon)
            return false;
        //check if in wrong state, like flying around
        if (!currentState.canFire)
            return false;
        if (currentState is wsc.st_stand)
            //draw weapon
            setState(wsc.st_weapon);

        if (!keyUp) {
            //start firing
            if (mWeapon.fireMode.variableThrowStrength) {
                //charge strength
                mThrowing = true;
                mThrowingStarted = engine.gameTime.current;
            } else {
                //fire instantly with default strength
                fireWeapon(mShooterMain, mWeapon.fireMode.throwStrengthFrom);
            }
        } else {
            //fire key released, really fire variable-strength weapon
            if (!mThrowing)
                return false;
            auto strength = currentFireStrength();
            mThrowing = false;
            auto fm = mWeapon.fireMode;
            fireWeapon(mShooterMain, fm.throwStrengthFrom + strength
                * (fm.throwStrengthTo-fm.throwStrengthFrom));
        }

        return true;
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
        //note that possibly mShooterMain.weapon != mWeapon
        return mShooterMain && mShooterMain.activity()
            && mShooterMain.weapon.allowSecondary
            && mWeapon && !mWeapon.allowSecondary;
    }

    void setWeaponTimer(Time t) {
        //range checked when actually firing
        mWeaponTimer = t;
    }

    //return the fire strength value, always between 0.0 and 1.0
    private float currentFireStrength() {
        if (!mThrowing) //what??
            return 0;
        auto diff = engine.gameTime.current - mThrowingStarted;
        float s = cast(double)diff.msecs / cWeaponLoadTime.msecs;
        return clampRangeC(s, 0.0f, 1.0f);
    }

    private void checkReadjust() {
        if (mShooterMain && mShooterMain.activity)
            mShooterMain.readjust(weaponDir());
        if (mShooterSec && mShooterSec.activity)
            mShooterSec.readjust(weaponDir());
    }

    //fire currently selected weapon (mWeapon) as main weapon
    //will also create the shooter if necessary
    private void fireWeapon(ref Shooter sh, float strength,
        bool fixedDir = false)
    {
        if (!mWeapon)
            return;
        if (!sh || sh.weapon != mWeapon)
            sh = mWeapon.createShooter(this);

        log("fire: {}", mWeapon.name);

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
        info.timer = clampRangeC(mWeaponTimer, mWeapon.fireMode.timerFrom,
            mWeapon.fireMode.timerTo);
        if (wcontrol)
            info.pointto = wcontrol.getTarget;
        else
            info.pointto = physics.pos;
        sh.ammoCb = &reduceAmmo;
        sh.finishCb = &shooterFinish;
        //for wcontrol.firedWeapon: sh.fire might complete in one call and
        //  reset sh
        auto shTmp = sh;
        sh.fire(info);

        if (wcontrol)
            wcontrol.firedWeapon(shTmp, false);
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
    private void reduceAmmo(Shooter sh) {
        if (wcontrol)
            wcontrol.reduceAmmo(sh);
    }

    private void shooterFinish(Shooter sh) {
        if (!mWeapon) {
            //check for delayed state change weapon->stand because
            //main weapon was unset
            //xxx is this case even possible?
            if (!mShooterMain || !mShooterMain.activity) {
                if (currentState is wsc.st_weapon)
                    setState(wsc.st_stand);
            }
        }
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
        setCurrentAnimation();
        updateCrosshair();
    }

    private void updateCrosshair() {
        //create/destroy the target cross
        bool exists = !!mCrosshair;
        bool shouldexist = false;
        if (currentState.canAim && mWeapon) {
            //xxx special cases not handled, just turns on/off crosshair
            shouldexist = mWeapon.fireMode.direction != ThrowDirection.fixed &&
                !allowAlternate();
        }
        if (exists != shouldexist) {
            if (exists) {
                mCrosshair.remove();
                mCrosshair = null;
            } else {
                mCrosshair = new CrosshairGraphic(teamColor, seqUpdate);
                engine.graphics.add(mCrosshair);
            }
        }
    }

    bool delayedAction() {
        bool ac = mThrowing;
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
        mWeapon = null;
    }

    override protected void stateTransition(StaticStateInfo from,
        StaticStateInfo to)
    {
        super.stateTransition(from, to);
        auto fromW = cast(WormStateInfo)from;
        auto toW = cast(WormStateInfo)to;
        //Trace.formatln("state {} -> {}", from.name, to.name);

        if (!mIsDead && (currentState is wsc.st_drowning)) {
            //die by drowning - are there more actions needed?
            mIsDead = true;
            mHasDrowned = true;
        }

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

        if (fromW.canAim || toW.canAim) {
            updateCrosshair();
        }

        if (to is wsc.st_die) {
            mIsDead = true;
        }
        //die by blowing up
        if (to is wsc.st_dead) {
            mIsDead = true;
            die();
            //explosion!
            engine.explosionAt(physics.pos, wsc.suicideDamage, this);
            auto grave = castStrict!(GravestoneSprite)(
                engine.createSprite("grave"));
            grave.createdBy = this;
            grave.setGravestone(mGravestone);
            grave.setPos(physics.pos);
        }

        //stop movement if not possible
        if (!currentState.canWalk) {
            physics.setWalking(Vector2f(0));
        }
        if (!currentState.canFire) {
            mThrowing = false;
        }
    }

    //xxx sorry for that
    override void setState(StaticStateInfo nstate, bool for_end = false) {
        if (nstate is wsc.st_stand &&
            (currentState is wsc.st_fly || currentState is wsc.st_jump ||
            currentState is wsc.st_jump_to_fly))
        {
            nstate = wsc.st_getup;
        }
        //if (nstate !is wsc.st_stand)
          //  Trace.formatln(nstate.name);
        super.setState(nstate, for_end);
    }

    override WormStateInfo currentState() {
        return cast(WormStateInfo)super.currentState;
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
        StaticStateInfo wanted = activate ? wsc.st_jet : wsc.st_stand;
        setState(wanted);
    }

    bool ropeActivated() {
        return currentState is wsc.st_rope;
    }

    void activateRope(void delegate(Vector2f mv) ropeMove) {
        if (!!ropeMove == ropeActivated())
            return;

        mRopeMove = ropeMove;
        StaticStateInfo wanted = !!ropeMove ? wsc.st_rope : wsc.st_stand;
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

    bool isStanding() {
        return currentState is wsc.st_stand;
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

    override protected void physImpact(PhysicBase other, Vector2f normal) {
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
    }

    override protected void physDamage(float amout, int cause) {
        super.physDamage(amout, cause);
        mRopeCanRefire = false;
        if (cause != DamageCause.explosion)
            return;
        if (currentState is wsc.st_fly) {
            //when damaged in-flight, switch to heavy animation
            //xxx better react to impulse rather than damage
            setFlyAnim(FlyMode.heavy);
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

        if (!jetpackActivated && !blowtorchActivated) {
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
                    if (graphic.getCurrentState is wsc.flyState[FlyMode.fall]
                        || graphic.getCurrentState is
                            wsc.flyState[FlyMode.slide])
                    {
                        setFlyAnim(FlyMode.roll);
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
        if (active && shouldDie() && !delayedDeath()) {
            finallyDie();
        }
    }
}

//contains custom state attributes for worm sprites
class WormStateInfo : StaticStateInfo {
    bool isGrounded = false;    //is this a standing-on-ground state
    bool canWalk = false;       //should the worm be allowed to walk
    bool canAim = false;        //can the target cross be moved
    bool canFire = false;       //can the main weapon be fired

    //xxx class
    this (ReflectCtor c) {
        super(c);
    }
    this () {
    }

    override void loadFromConfig(ConfigNode sc, ConfigNode physNode,
        GOSpriteClass owner)
    {
        super.loadFromConfig(sc, physNode, owner);
        isGrounded = sc.getBoolValue("is_grounded", isGrounded);
        canWalk = sc.getBoolValue("can_walk", canWalk);
        canAim = sc.getBoolValue("can_aim", canAim);
        canFire = sc.getBoolValue("can_fire", canFire);
    }
}

//the factories work over the sprite classes, so we need one
class WormSpriteClass : GOSpriteClass {
    float suicideDamage;
    //SequenceObject[] gravestones;
    Vector2f jumpStrength[JumpMode.max+1];
    float rollVelocity = 400;
    float ropeImpulse = 700;

    WormStateInfo st_stand, st_fly, st_walk, st_jet, st_weapon, st_dead,
        st_die, st_drowning, st_beaming, st_reverse_beaming, st_getup,
        st_jump_start, st_jump, st_jump_to_fly, st_rope, st_drill, st_blowtorch;

    //alias WormSprite.FlyMode FlyMode;

    SequenceState[FlyMode.max+1] flyState;

    //xxx class
    this (ReflectCtor c) {
        super(c);
    }

    this(GameEngine e, char[] r) {
        super(e, r);
    }
    override void loadFromConfig(ConfigNode config) {
        super.loadFromConfig(config);
        suicideDamage = config.getFloatValue("suicide_damage", 10);
        ropeImpulse = config.getFloatValue("rope_impulse", ropeImpulse);

        Vector2f getJs(char[] nid) {
            return config.getValue(nid,Vector2f(100,-100));
        }
        jumpStrength[JumpMode.normal] = getJs("jump_st_normal");
        jumpStrength[JumpMode.smallBack] = getJs("jump_st_smallback");
        jumpStrength[JumpMode.straightUp] = getJs("jump_st_straightup");
        jumpStrength[JumpMode.backFlip] = getJs("jump_st_backflip");

        //done, read out the stupid states :/
        st_stand = findState("stand");
        st_fly = findState("fly");
        st_walk = findState("walk");
        st_jet = findState("jetpack");
        st_weapon = findState("weapon");
        st_dead = findState("dead");
        st_die = findState("die");
        st_drowning = findState("drowning");
        st_beaming = findState("beaming");
        st_reverse_beaming = findState("reverse_beaming");
        st_getup = findState("getup");
        st_jump_start = findState("jump_start");
        st_jump = findState("jump");
        st_jump_to_fly = findState("jump_to_fly");
        st_rope = findState("rope");
        st_drill = findState("drill");
        st_blowtorch = findState("blowtorch");

        flyState[FlyMode.fall] = findSequenceState("fly_fall",true);
        flyState[FlyMode.slide] = findSequenceState("fly_slide",true);
        flyState[FlyMode.roll] = findSequenceState("fly_roll",true);
        flyState[FlyMode.heavy] = findSequenceState("fly_heavy",true);
    }
    override WormSprite createSprite() {
        return new WormSprite(engine, this);
    }

    override StaticStateInfo createStateInfo() {
        return new WormStateInfo();
    }

    override WormStateInfo findState(char[] name, bool canfail = false) {
        return cast(WormStateInfo)super.findState(name, canfail);
    }

    static this() {
        SpriteClassFactory.register!(WormSpriteClass)("worm_mc");
    }
}

class GravestoneSprite : GObjectSprite {
    private {
        GravestoneSpriteClass gsc;
        int mType;
    }

    void setGravestone(int n) {
        assert(n >= 0);
        if (n >= gsc.normal.length) {
            //what to do?
            assert(false, "gravestone not found");
        }
        mType = n;
        setCurrentAnimation();
    }

    protected override void setCurrentAnimation() {
        if (!graphic)
            return;

        SequenceState st;
        if (currentState is gsc.st_normal) {
            st = gsc.normal[mType];
        } else if (currentState is gsc.st_drown) {
            st = gsc.drown[mType];
        } else {
            assert(false);
        }

        graphic.setState(st);
    }

    this(GameEngine e, GravestoneSpriteClass s) {
        super(e, s);
        gsc = s;
        active = true;
    }

    this (ReflectCtor c) {
        super(c);
    }
}

class GravestoneSpriteClass : GOSpriteClass {
    StaticStateInfo st_normal, st_drown;

    //indexed by type
    SequenceState[] normal;
    SequenceState[] drown;

    //xxx class
    this (ReflectCtor c) {
        super(c);
    }

    this(GameEngine e, char[] r) {
        super(e, r);
    }

    override void loadFromConfig(ConfigNode config) {
        super.loadFromConfig(config);

        st_normal = findState("normal");
        st_drown = findState("drowning");

        //try to find as much gravestones as there are
        for (int n = 0; ; n++) {
            auto s_n = findSequenceState(myformat("n{}", n), true);
            auto s_d = findSequenceState(myformat("drown{}", n), true);
            if (!(s_n && s_d))
                break;
            normal ~= s_n;
            drown ~= s_d;
        }
    }

    override GravestoneSprite createSprite() {
        return new GravestoneSprite(engine, this);
    }

    static this() {
        SpriteClassFactory.register!(typeof(this))("grave_mc");
    }
}
