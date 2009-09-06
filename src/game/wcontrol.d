//all that was TeamMember, lol.
//this merges parts from TeamMember and WormSprite into a separate class
//especially about how worms interact with weapons (when firing weapons)
//things that don't belong here: HUD logic (health updates...), any Team stuff
module game.wcontrol;

import common.animation;
import game.game;
import game.gfxset;
import game.sprite;
import game.temp;
import game.weapon.types;
import game.weapon.weapon;
import game.worm;
import physics.world;
import utils.array;
import utils.misc;
import utils.reflection;
import utils.time;
import utils.vector2;

import game.gamepublic; //for ZOrder

/+
//feedback WormControl -> WormSprite
interface SpriteControl {
    //enable/disable equipment (right now: jetpack, rope)
    //returns success
    //(fails when...:
    //  enable: not possible or available
    //  disable: equipment wasn't enabled)
    //WeaponClass is only used for simplification (to identify jetpack/rope)
    bool enableEquipment(WeaponClass type, bool enable);
}
+/

//separate control for special weapons like super sheep or rope
interface Controllable {
    bool fire(bool keyDown);
    bool jump(JumpMode j);
    bool move(Vector2f m);
    GObjectSprite getSprite();
}

//every worm, that's controllable by the user (includes all TeamMembers) has
//  an instance of this class
//user input is directly (after command parsing) fed to this class
//NOTE: this should work with other object types too (not only worms), so that
//      the engine can do more stuff than just... worms
class WormControl : WormController {
    private {
        GameEngine mEngine;
        //GObjectSprite mWorm;    //never null
        WormSprite mWorm;
        //SpriteControl mWormControl; //is cast(SpriteControl)mWorm
        WeaponClass mCurrentWeapon;
        WeaponClass mWormLastWeapon;
        WeaponClass mCurrentEquipment;
        bool mEngaged;
        Time mLastAction;
        Time mLastActivity = timeSecs(-40);
        bool mWormAction;
        Vector2f mMoveVector;
        bool mFireDown;
        bool mWeaponUsed;
        bool mLimitedMode;
        Controllable[] mControlStack;
        //usually shared with other team members (but that doesn't concern us)
        WeaponSet mWeaponSet;
        bool mAlternateControl;
        bool mOnHold;

        //if you can click anything, if true, also show that animation
        PointMode mPointMode;
        Animator mCurrentTargetInd;
        WeaponTarget mCurrentTarget;
        bool mTargetIsSet;
    }

    this(GObjectSprite worm) {
        assert(!!worm);
        mEngine = worm.engine;
        mWeaponSet = new WeaponSet(mEngine);
        mWorm = castStrict!(WormSprite)(worm);
        //mWormControl = cast(SpriteControl)mWorm;
        //assert(!!mWormControl);
        //set feedback interface to this class
        mWorm.wcontrol = this;
    }

    this(ReflectCtor c) {
    }

    final GameEngine engine() {
        return mEngine;
    }

    //sets list of available weapons (by reference)
    void setWeaponSet(WeaponSet set) {
        mWeaponSet = set;
    }

    void setAlternateControl(bool v) {
        mAlternateControl = v;
    }

    //enable delayed dying; if a worm runs out of health points, it doesn't
    //  commit suicide immediately; instead, it is done when checkDying() is
    //  called
    //if delayed dying is not enabled with this functions, worms die immediately
    void setDelayedDeath() {
        mWorm.delayedDeath = true;
    }

    //set on-hold mode; in on-hold mode, the worm is not controllable, although
    //  it stays engaged (e.g. weapon state is not changed)
    //on-hold mode is automatically reset to false if worm is (de)activated
    void setOnHold(bool v) {
        if (!mEngaged)
            return;
        mOnHold = v;
    }

    bool isOnHold() {
        return mOnHold;
    }

    private void setEquipment(WeaponClass e) {
        /+
        if (e is mCurrentEquipment)
            return;
        if (mCurrentEquipment)
            mWormControl.enableEquipment(mCurrentEquipment, false);
        mCurrentEquipment = e;
        if (mCurrentEquipment)
            mWormControl.enableEquipment(mCurrentEquipment, true);
        +/
        if (!e)
            mWorm.activateJetpack(false);
    }

    bool isAlive() {
        return mWorm.isAlive();
    }

    //always the worm
    GObjectSprite sprite() {
        return mWorm;
    }

    //the worm, or whatever controllable weapon was lunched (e.g. super sheep)
    GObjectSprite controlledSprite() {
        if (mControlStack.length > 0) {
            return mControlStack[$-1].getSprite();
        } else {
            return mWorm;
        }
    }

    //this "engaged" is about whether the worm can be made controllable etc.
    //engaged=true: worm normally is controllable; but might not be controllable
    //  if setOnHold(true) was called (after engaging)
    //  a weapon can be selected, but doesn't need to
    //engaged=false: normally nothing goes on, but stuff might be still in
    //  progress; e.g. worm is flying around, or dying animation is played
    void setEngaged(bool eng) {
        if (mEngaged == eng)
            return;

        if (eng) {
            //worm is being activated
            mEngaged = true;
            mWeaponUsed = false;
            mLimitedMode = false;
            //select last used weapon, select default if none
            //xxx: default weapon somewhere got lost (not with this last change)
            //if (!mCurrentWeapon)
            //    mCurrentWeapon = mTeam.defaultWeapon;
            selectWeapon(mCurrentWeapon);
        } else {
            //being deactivated
            controllableMove(Vector2f(0));
            mControlStack = null;
            move(Vector2f(0));
            setPointMode(PointMode.none);
            mWormLastWeapon = null;
            mLastAction = Time.Null;

            //stop all action when turn ends
            setEquipment(null);
            mWorm.forceAbort();
            mWorm.weapon = null;

            setPointMode(PointMode.none);
            mTargetIsSet = false;

            mFireDown = false;
            mEngaged = false;
        }

        mOnHold = false;

        resetActivity();
    }

    bool engaged() {
        return mEngaged;
    }

    void setLimitedMode() {
        //can only leave this by deactivating
        mLimitedMode = true;
        mFireDown = false;
        updateWeapon();
    }

    bool isControllable() {
        if (mEngaged)
            assert(isAlive());
        return mEngaged && !mOnHold;
    }

    void jump(JumpMode j) {
        if (!isControllable)
            return;
        bool eaten;
        foreach_reverse (ctl; mControlStack) {
            eaten = ctl.jump(j);
            if (eaten)
                break;
        }
        if (!eaten) {
            //try alternate fire, if not possible jump instead
            if (!doAlternateFire())
                mWorm.jump(j);
        }
        wormAction();
    }

    //just for gameview.d
    //maybe move into GObjectSprite
    bool isDrowning() {
        return mWorm.graphic && mWorm.hasDrowned();
    }

    WeaponClass currentWeapon() {
        return mCurrentWeapon;
    }

    //return true if the current selected weapon can't be rendered:
    //  1. because there's no animation (like jetpack before it's activated)
    //  2. because worm is in jetpack or rope modus
    bool displayWeaponIcon() {
        //this is probably still bogus, what about other possible stuff like
        //ropes etc. that could be added later?
        //suggestion: define when exactly a worm can throw a weapon and attempt
        //to display the weapon icon in these situations
        return mCurrentWeapon && mWorm.displayWeaponIcon;
    }

    bool canUseWeapon(WeaponClass c) {
        return c && mWeaponSet.find(c).quantity > 0 && c.canUse(engine);
    }

    void selectWeapon(WeaponClass weapon) {
        if (!isControllable || mLimitedMode)
            return;
        mCurrentWeapon = weapon;
        if (!canUseWeapon(mCurrentWeapon))
            mCurrentWeapon = null;
        //(changed later: selecting no-weapon is an action too)
        if (weapon !is mCurrentWeapon) {
            wormAction();
        }
        updateWeapon();
    }

    //update weapon state of current worm (when new weapon selected)
    private void updateWeapon() {
        if (!mEngaged || !isAlive())
            return;

        WeaponClass selected = mCurrentWeapon;

        if (!canUseWeapon(mCurrentWeapon) || mLimitedMode)
            selected = null;

        mWorm.weapon = selected;
    }

    void doSetTimer(Time t) {
        if (!isControllable || mLimitedMode)
            return;

        mWorm.setWeaponTimer(t);
    }

    private bool controllableFire(bool keyDown) {
        bool ret;
        foreach_reverse(ctl; mControlStack) {
            ret = ctl.fire(keyDown);
            if (ret)
                break;
        }
        return ret;
    }

    private bool controllableMove(Vector2f m) {
        bool ret;
        foreach_reverse(ctl; mControlStack) {
            ret = ctl.move(m);
            if (ret)
                break;
        }
        return ret;
    }

    void selectFireRefire(WeaponClass wc, bool keyDown) {
        if (!isControllable)
            return;

        if (mWorm.altWeapon is wc) {
            if (keyDown) {
                mWorm.fireAlternate();
            }
        } else if (mWorm.firedWeapon(false) is wc) {
            if (keyDown)
                doFireDown(true);
            else
                doFireUp();
        } else {
            selectWeapon(wc);
        }
        wormAction();
    }

    void doFireDown(bool forceSelected = false) {
        if (!isControllable)
            return;

        bool success = true;
        if (!controllableFire(true)) {
            success = false;
            if (mWorm.allowAlternate && !forceSelected && !mAlternateControl) {
                //non-alternate (worms-like) control -> spacebar disables
                //background weapon if possible (like jetpack)
                success = mWorm.fireAlternate();
            } else if (checkPointMode()) {
                success = mWorm.fire(false, forceSelected);
            }
            //don't forget a keypress that had no effect
            mFireDown = !success;
        }
        if (success)
            wormAction();
    }

    void doFireUp() {
        mFireDown = false;
        if (!isControllable)
            return;

        if (controllableFire(false) || mWorm.fire(true)) {
            wormAction();
        }
    }

    //returns true if the keypress was taken
    bool doAlternateFire() {
        if (!isControllable)
            return false;

        bool success = false;

        if (mAlternateControl) {
            //alternate (new-lumbricus) control: alternate-fire button (return)
            //refires background weapon (like jetpack-deactivation)
            if (mWorm.allowAlternate())
            {
                mWorm.fireAlternate();
                success = true;
            }
        } else {
            //worms-like: alternate-fire button (return) fires selected
            //weapon if in secondary mode
            if (mWorm.allowFireSecondary() && checkPointMode()) {
                success = mWorm.fire();
            }
        }
        if (success)
            wormAction();
        return success;
    }

    // Start WormController implementation (see game.worm) -->

    WeaponTarget getTarget() {
        return mCurrentTarget;
    }

    void reduceAmmo(Shooter sh) {
        mWeaponSet.decreaseWeapon(sh.weapon);
        //mTeam.parent.updateWeaponStats(this);
        if (!canUseWeapon(sh.weapon))
            //weapon ran out of ammo
            sh.interruptFiring(true);
        updateWeapon();
        //xxx select next weapon when current is empty... oh sigh
        //xxx also, select current weapon if we still have one, but weapon is
        //    undrawn! (???)
    }

    void firedWeapon(Shooter sh, bool refire) {
        assert(!!sh);
//xxx        mTeam.parent.events.onFireWeapon(sh.weapon, refire);
    }

    void doneFiring(Shooter sh) {
        if (!sh.weapon.dontEndRound)
            mWeaponUsed = true;
        if (sh.weapon.deselectAfterFire)
            selectWeapon(null);
    }

    // <-- End WormController

    //has the worm fired something since he became engaged?
    bool weaponUsed() {
        return mWeaponUsed;
    }

    Time lastAction() {
        return mLastAction;
    }

    // != lastAction; last activity of the owned WormSprite (updated even if
    // member is not engaged)
    Time lastActivity() {
        return mLastActivity;
    }

    //called if any action is issued, i.e. key pressed to control worm
    //or if it was moved by sth. else
    void wormAction() {
        mWormAction = true;
        mLastAction = mEngine.gameTime.current;
    }

    //has the worm done anything since activation?
    //is false: after activation/deactivation
    //is true: if, after activation, an action like moving around was performed
    bool actionPerformed() {
        return mWormAction;
    }

    void resetActivity() {
        mWormAction = false;
        mLastAction = timeSecs(-40); //xxx not kosher
    }

    private void move(Vector2f vec) {
        if (!isAlive() || !isControllable) {
            mMoveVector = Vector2f(0);
            mWorm.move(mMoveVector);
            return;
        }

        if (vec == mMoveVector)
            return;

        wormAction();

        mMoveVector = vec;
        if (!controllableMove(vec))
            mWorm.move(vec);
    }

    void doMove(Vector2i vec) {
        //xxx: restrict movement vector, but is this correct?
        vec.x = clampRangeC(vec.x, -1, +1);
        vec.y = clampRangeC(vec.y, -1, +1);
        move(toVector2f(vec));
    }

    bool isIdle() {
        return mWorm.physics.isGlued;
    }

    void simulate() {
        if (mCurrentTargetInd) {
            if (mTargetIsSet && mCurrentTarget.sprite) {
                //worm tracking
                mCurrentTargetInd.pos = toVector2i(mCurrentTarget.currentPos);
            }
            //unused?
            //if (mCurrentTargetInd.readyflag()) {
            //    setIndicator(null);
            //}
        }

        if (mWorm && mWorm.activity())
            mLastActivity = mEngine.gameTime.current;

        if (!mEngaged)
            return;

        if (mWorm.firedWeapon !is mWormLastWeapon) {
            mWormLastWeapon = mWorm.firedWeapon;
            if (mWormLastWeapon) {
                setPointMode(mWormLastWeapon.fireMode.point);
            } else {
                setPointMode(PointMode.none);
            }
        }

        //check if fire button is being held down, waiting for right state
        if (mFireDown)
            doFireDown();

        //if the worm can't be controlled anymore due to circumstances
        //right now: if the worm died or is drowning
        if (!mWorm.haveAnyControl())
            setEngaged(false);

        //if moving (by keys or by itself), the worm is performing an action
        //xxx: what if it moves by itself? (e.g. worm swings on a rope)
        //     okok, there's mWorm.activity() too. and lastActivity()
        if (mMoveVector != Vector2f(0)) {
            wormAction();
        }
    }

    void youWinNow() {
        mWorm.setState(mWorm.findState("win"));
    }

    //check for any activity that might justify control beyond end-of-turn
    //e.g. still charging a weapon, still firing a multi-shot weapon
    bool delayedAction() {
        return mWorm.delayedAction;
    }

    void forceAbort() {
        //forced stop of all action (like when being damaged)
        mWorm.forceAbort();
    }

    void pushControllable(Controllable c) {
        //if the new top object takes movement input, stop the current top
        if (c.move(mMoveVector))
            move(Vector2f(0));
        mControlStack ~= c;
    }

    void releaseControllable(Controllable c) {
        //stack gets cleared if the worm becomes unengaged
        if (mControlStack.length == 0)
            return;
        if (mControlStack.length > 1 && c is mControlStack[$-1]) {
            //if removing the top object, transfer current movement to next
            c.move(Vector2f(0));
            mControlStack[$-2].move(mMoveVector);
        }
        //c does not have to be at the top of mControlStack
        arrayRemove(mControlStack, c);
    }

    //checks if this worm wants to blow up, returns true if it wants to or is
    //  in progress of blowing up
    bool checkDying() {
        //if this delayed dying business is not enabled
        if (!mWorm.delayedDeath())
            return false;

        //4 possible states:
        //  healthy, unhealthy but not suiciding, suiciding, dead and done

        //worm is healthy?
        if (mWorm.isAlive())
            return false;

        //dead and done?
        if (mWorm.isReallyDead())
            return false;

        //worm is dead, but something is in progress (waiting/suiciding)

        if (!mWorm.isDelayedDying()) {
            //unhealthy, not suiciding
            //=> start suiciding
            mWorm.finallyDie();
        }

        return true;
    }

    //--

    //xxx not quite kosher
    private TeamTheme color() {
        return mWorm.teamColor;
    }

    //note: also clears the target indicator
    private void setPointMode(PointMode mode) {
        if (mPointMode == mode)
            return;
        mPointMode = mode;
        setIndicator(null);
        //show X again, if set before
        if ((mode == PointMode.target || mode == PointMode.targetTracking)
            && mTargetIsSet)
        {
            setIndicator(color.pointed, mCurrentTarget.currentPos);
        }
    }
    //checks if ready to fire, according to point mode
    private bool checkPointMode() {
        return (mPointMode == PointMode.none || mTargetIsSet);
    }
    void doSetPoint(Vector2f where) {
        if (mPointMode == PointMode.none || !isControllable)
            return;

        if (mPointMode == PointMode.instantFree) {
            //move point out of landscape
            if (!mEngine.physicworld.freePoint(where, 6))
                return;
        }

        mTargetIsSet = true;
        mCurrentTarget = where;

        switch(mPointMode) {
            case PointMode.targetTracking:
                //find sprite closest to where
                mEngine.physicworld.objectsAtPred(where, 10,
                    (PhysicObject obj) {
                        mCurrentTarget.sprite = cast(GObjectSprite)obj.backlink;
                        return false;
                    }, (PhysicObject obj) {
                        return !!cast(GObjectSprite)obj.backlink;
                    });
                //fall-through
            case PointMode.target:
                //X animation
                setIndicator(color.pointed, mCurrentTarget.currentPos);
                break;
            case PointMode.instant, PointMode.instantFree:
                //click effect
                mEngine.animationEffect(color.click,
                    toVector2i(where), AnimationParams.init);

                //instant mode -> fire and forget
                doFireDown(true);
                doFireUp();
                mTargetIsSet = false;
                break;
            default:
                assert(false);
        }
    }
    private void setIndicator(Animation ani, Vector2f pos = Vector2f.init) {
        //only one cross indicator
        if (mCurrentTargetInd) {
            mCurrentTargetInd.removeThis();
            mCurrentTargetInd = null;
        }
        if (!ani)
            return;
        mCurrentTargetInd = new Animator(mEngine.gameTime);
        mCurrentTargetInd.pos = toVector2i(pos) ;
        mCurrentTargetInd.setAnimation(ani);
        mCurrentTargetInd.zorder = GameZOrder.Crosshair; //this ok?
        mEngine.scene.add(mCurrentTargetInd);
    }

    //-- moved from worm.d
}
