//all that was TeamMember, lol.
//this merges parts from TeamMember and WormSprite into a separate class
//especially about how worms interact with weapons (when firing weapons)
//things that don't belong here: HUD logic (health updates...), any Team stuff
module game.wcontrol;

import common.animation;
import framework.drawing;
import game.core;
import game.events;
import game.input;
import game.sprite;
import game.teamtheme;
import game.weapon.types;
import game.weapon.weapon;
import game.weapon.weaponset;
import game.worm;
import physics.all;
import utils.array;
import utils.misc;
import utils.time;
import utils.vector2;

import game.temp : GameZOrder;

//make available for other modules
//renamed imports being public is actually a dmd bug
public import game.worm : JumpMode;

//for GUI, to give the user some feedback when the keypress did nothing
//xxx I would love to use TeamMember as sender, but that would get messy
alias DeclareEvent!("weapon_misfire", WeaponClass, WormControl,
    WeaponMisfireReason) OnWeaponMisfire;

//separate control for special weapons like super sheep or rope
interface Controllable {
    //returning false means the worm's normal action should be executed
    bool fire(bool keyDown);
    bool jump(JumpMode j);
    bool move(Vector2f m);
    //returning null => no active sprite; worm is considered to be active
    Sprite getSprite();
}

//every worm, that's controllable by the user (includes all TeamMembers) has
//  an instance of this class
//user input is directly (after command parsing) fed to this class
//NOTE: this should work with other object types too (not only worms), so that
//      the engine can do more stuff than just... worms
class WormControl : WeaponController {
    private {
        GameCore mEngine;
        //Sprite mWorm;    //never null
        WormSprite mWorm;
        //SpriteControl mWormControl; //is cast(SpriteControl)mWorm
        WeaponClass mCurrentWeapon;
        WeaponClass mCurrentEquipment;
        WeaponClass mOnHoldWeapon;
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
        InputGroup mInput;
        MoveStateXY mInputMoveState;

        //if you can click anything, if true, also show that animation
        PointMode mPointMode;
        Animator mCurrentTargetInd;
        WeaponTarget mCurrentTarget;
        bool mTargetIsSet;
        int mWeaponParam;
        Shooter[] mWeapons;

        //hack to make weapon angle permanent
        float mWeaponAngle = float.nan;

        bool delegate(Canvas, Vector2i) mMouseRender;
    }

    this(Sprite worm) {
        assert(!!worm);
        mEngine = worm.engine;
        mWeaponSet = new WeaponSet(mEngine);
        //mWeaponSet can change; this seems to be the easiest way
        OnWeaponSetChanged.handler(mEngine.events, &weaponSetChanged);
        mWorm = castStrict!(WormSprite)(worm);
        //mWormControl = cast(SpriteControl)mWorm;
        //assert(!!mWormControl);
        OnSpriteDie.handler(mWorm.instanceLocalEvents, &onSpriteDie);
        OnDamage.handler(mWorm.instanceLocalEvents, &onSpriteDamage);
        //init keyboard input
        mInput = new InputGroup();
        auto i = mInput;
        i.addT("jump", &inpJump);
        i.add("move", &inpMove);
        i.addT("weapon", &inpWeapon);
        i.addT("set_param", &inpSetParam);
        i.addT("set_target", &inpSetTarget);
        i.addT("select_fire_refire", &inpSelRefire);
        i.addT("selectandfire", &inpSelFire);
        i.addT("weapon_fire", &inpFire);
        inputEnabled = false;
    }

    final GameCore engine() {
        return mEngine;
    }

    //-- input

    final InputGroup input() { return mInput; }

    //activate or deactivate keyboard input for this worm
    private void inputEnabled(bool en) {
        input.enabled = en;
    }

    //return null on failure
    private WeaponClass findWeapon(string name) {
        return engine.resources.get!(WeaponClass)(name, true);
    }

    private bool inpJump(bool alt) {
        jump(alt ? JumpMode.straightUp : JumpMode.normal);
        return true;
    }

    private bool inpMove(string cmd) {
        mInputMoveState.handleCommand(cmd);
        engine.log.trace("move state for {:x}: {}", toHash, mInputMoveState);
        move(toVector2f(mInputMoveState.direction));
        return true;
    }

    private bool inpWeapon(string weapon) {
        WeaponClass wc;
        if (weapon != "-")
            wc = findWeapon(weapon);
        selectWeapon(wc);
        return true;
    }

    private bool inpSetParam(int p) {
        if (!isControllable || mLimitedMode)
            return false;

        mWeaponParam = p;
        return true;
    }

    private bool inpSetTarget(int x, int y) {
        doSetPoint(Vector2f(x, y));
        return true;
    }

    private bool inpSelRefire(string m, bool down) {
        WeaponClass wc = findWeapon(m);
        selectFireRefire(wc, down, false);
        return true;
    }

    private bool inpSelFire(string m, bool down) {
        WeaponClass wc = findWeapon(m);
        selectFireRefire(wc, down, true);
        return true;
    }

    private bool inpFire(bool is_down) {
        doFire(is_down);
        return true;
    }

    //-- input end

    private void onSpriteDie(Sprite sender) {
        if (sender is mWorm)
            mWorm.killVeto(this);
    }

    private void onSpriteDamage(Sprite sender, GameObject cause,
        DamageCause dmgType, float damage)
    {
        if (sender is mWorm && engaged)
            forceAbort(false);
    }

    //sets list of available weapons (by reference)
    void setWeaponSet(WeaponSet set) {
        mWeaponSet = set;
    }

    //"alternate control" (mAlternateControl = true) is like WWP, where you
    //  always mix up Space and Return
    //default (false) is Lumbricus control, where you only need Space
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
        if (!mEngaged || v == mOnHold)
            return;
        mOnHold = v;
        if (!mOnHold && mOnHoldWeapon) {
            selectWeapon(mOnHoldWeapon);
        }
        move(mMoveVector);
    }

    bool isOnHold() {
        return mOnHold;
    }

    //xxx what is this equipment stuff? a planned feature?
    //  ^ older idea to unify handling of jetpacks, drills, etc. without
    //    having to have special methods for it (which worm.d still has); all
    //    that is on hold and I'm really unsure how to proceed
    private void setEquipment(WeaponClass e) {
        if (!e)
            mWorm.activateJetpack(false);
    }

    bool isAlive() {
        return mWorm.isAlive();
    }

    //always the worm
    Sprite sprite() {
        return mWorm;
    }

    //the worm, or whatever controllable weapon was lunched (e.g. super sheep)
    Sprite controlledSprite() {
        //NOTE: at least one weapon (girder) can return null here; there's not
        //  really a sprite or any other game object the user is controlling;
        //  it's just that the weapon code wants to catch some key presses
        //thus, it returns the worm sprite if getSprite() returns null
        Sprite ret;
        if (mControlStack.length > 0) {
            ret = mControlStack[$-1].getSprite();
        }
        return ret ? ret : mWorm;
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

        //some assertion fail if enaged, but not alive
        if (!isAlive())
            eng = false;

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
            inputEnabled = true;
            mWorm.fixed = false;
        } else {
            //being deactivated
            inputEnabled = false;
            mEngaged = false;
            controllableMove(Vector2f(0));
            mControlStack = null;
            move(Vector2f(0));
            setPointMode(PointMode.none);
            mLastAction = Time.Null;

            //stop all action when turn ends
            setEquipment(null);
            forceAbort();

            setPointMode(PointMode.none);
            mTargetIsSet = false;

            mFireDown = false;
            mMouseRender = null;
        }

        mOnHold = false;
        mOnHoldWeapon = null;
        //stale keypresses
        mInputMoveState.reset();

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
        //xxx assertion fails when you beam into deathzone
        //  e.g. below water ground line in closed level with big sdl window
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
            if (!doAlternateFire(true))
                mWorm.jump(j);
            else
                //xxx the keyUp is only needed in alternate (worms-like) mode,
                //    where it will cause firing with minimum strength
                //    (just like in wwp); but we could also add a bool keyDown
                //    to jump()
                doAlternateFire(false);
        }
        wormAction();
    }

    WeaponClass currentWeapon() {
        return mCurrentWeapon;
    }

    bool canUseWeapon(WeaponClass c) {
        return mWeaponSet.canUseWeapon(c);
    }

    void selectWeapon(WeaponClass weapon) {
        if (!isControllable || mLimitedMode) {
            mOnHoldWeapon = weapon;
            return;
        }
        if (!canUseWeapon(weapon))
            weapon = null;
        //(changed later: selecting no-weapon is an action too)
        if (weapon !is mCurrentWeapon) {
            wormAction();
        }
        mCurrentWeapon = weapon;
        updateWeapon();
    }

    //makes room on the weapon stack to select the passed weapon, and
    //  decides whether the new weapon should be added as primary or secondary
    //also checks if the current stack state allows selecting this weapon
    //Returns: true if the stack was prepared ok and the weapon can be pushed
    //         false if the weapon cannot be selected (e.g. cannot select rope
    //           while jetpack is working)
    //caller has to make sure the weapon is allowed to use at all
    private bool prepareSelect(WeaponClass weapon) {
        //set as new main
        if (mWeapons.length == 0)
            return true;
        if (mWeapons[$-1].isIdle && mWeapons[$-1].weapon !is weapon) {
            if (mWeapons.length == 2 && weapon && weapon.allowSecondary)
                return false;
            //replace current main / secondary
            unselectWeapon(mWeapons.length - 1);
            return true;
        }
        if (mWeapons.length == 1 && mWeapons[0].weapon.allowSecondary && weapon
            && !weapon.allowSecondary)
        {
            //add as secondary
            return true;
        }
        return false;
    }

    //update weapon state of current worm (when new weapon selected)
    private void updateWeapon() {
        if (!mEngaged || !isAlive())
            return;

        WeaponClass selected = mCurrentWeapon;

        if (!canUseWeapon(mCurrentWeapon) || mLimitedMode)
            selected = null;

        if (prepareSelect(selected) && selected) {
            auto sh = selected.createShooter(mWorm);
            //set feedback interface to this class
            sh.setControl(this);
            sh.isSelected = true;
            mWeapons ~= sh;
            gWeaponLog.trace("weapons: {}", mWeapons);
            //hack to make weapon angle permanent
            if (sh is mWeapons[0] && mWeaponAngle == mWeaponAngle)
                sh.weaponAngle = mWeaponAngle;
        }
    }

    private void weaponSetChanged(WeaponSet sender) {
        //if a weapon is removed externally (like by script), make sure
        //  it is also removed from the worm
        //Note: updateWeapon() will not remove an active weapon
        if (sender is mWeaponSet) {
            updateWeapon();
        }
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

    private void selectFireRefire(WeaponClass wc, bool keyDown,
        bool instantFire)
    {
        if (!isControllable)
            return;

        if (!wc)
            return;

        if (keyDown) {
            if (allowAlternate && mWeapons[0].weapon is wc) {
                fireSecondaryWeapon();
            } else {
                instantFire = instantFire || mCurrentWeapon is wc;
                selectWeapon(wc);
                //don't fire the wrong weapon if selection failed
                //(hang on a rope, bazooka selected, press 'J' => don't fire)
                if (mainWeapon() !is wc)
                    return;
                if (instantFire) {
                    //fireMainWeapon will save the keypress and wait if not ready
                    fireMainWeapon(true);
                }
            }
        } else {
            //key was released (like fire behavior)
            fireMainWeapon(false);
        }
    }

    //returns true if the keypress was taken
    bool doFire(bool keyDown) {
        if (!isControllable)
            return true;

        if (controllableFire(keyDown)) {
            wormAction();
            return true;
        }

        //alternate: swapped controls if 2 weapons are active (weird, isn't it?)
        if (mAlternateControl && allowAlternate && keyDown)
            return fireSecondaryWeapon();

        return fireMainWeapon(keyDown);
    }

    //returns true if the keypress was taken
    bool doAlternateFire(bool keyDown) {
        if (!isControllable)
            return false;

        if (mAlternateControl && allowAlternate) {
            fireMainWeapon(keyDown);
            //take key even on failure (in which case mFireDown would be set),
            //  so the keyUp gets here too
            return true;
        }

        if (keyDown)
            return fireSecondaryWeapon();
        return false;
    }

    private bool allowAlternate() {
        return mWeapons.length > 0 && !mWeapons[0].isIdle
            && mWeapons[0].weapon.allowSecondary;
    }

    //fires main weapon (stack top; 1 or 2 on the stack)
    private bool fireMainWeapon(bool keyDown = true) {
        bool success = false;

        if (mWeapons.length > 0) {
            if (keyDown) {
                if (checkPointMode()) {
                    if (!mWeaponSet.coolingDown(mWeapons[$-1].weapon)) {
                        success = mWeapons[$-1].startFire();
                    } else if (!mFireDown) {
                        OnWeaponMisfire.raise(mWeapons[$-1].weapon, this,
                            WeaponMisfireReason.cooldown);
                    }
                } else if (!mFireDown) {
                    OnWeaponMisfire.raise(mWeapons[$-1].weapon, this,
                        WeaponMisfireReason.targetNotSet);
                }
            } else {
                mWeapons[$-1].startFire(true);
                success = true;
            }
        }

        //don't forget a key down that had no effect
        mFireDown = keyDown && !success;
        if (success)
            wormAction();
        return success;
    }

    //fires secondary weapon (stack bottom, e.g. jetpack)
    //for user convenience, it will also work if there is only 1 active weapon
    //  like jetpack/rope on the stack
    private bool fireSecondaryWeapon() {
        bool success = false;

        if (allowAlternate) {
            success = mWeapons[0].startFire();
        }
        if (success)
            wormAction();
        return success;
    }

    private void unselectWeapon(int idx) {
        if (mWeapons.length > idx) {
            mWeapons[idx].kill();
            arrayRemoveN(mWeapons, idx);
            gWeaponLog.trace("weapons: {}", mWeapons);
        }
    }

    private void unselectWeapon(Shooter sh) {
        if (mWeapons.length > 0 && sh) {
            sh.kill();
            arrayRemove(mWeapons, sh);
            gWeaponLog.trace("weapons: {}", mWeapons);
        }
    }

    private void checkWeaponStack() {
        assert(mWeapons.length <= 2);
        //main finished while secondary present
        if (mWeapons.length == 2 && mWeapons[0].isIdle()) {
            unselectWeapon(0);
        }
    }

    WeaponClass mainWeapon() {
        return mWeapons.length ? mWeapons[$-1].weapon : null;
    }

    // Start WeaponController implementation (see game.weapon.weapon) -->

    WeaponTarget getTarget() {
        return mCurrentTarget;
    }

    int getWeaponParam() {
        return mWeaponParam;
    }

    bool reduceAmmo(WeaponClass weapon) {
        mWeaponSet.decreaseWeapon(weapon);
        //mTeam.parent.updateWeaponStats(this);
        return canUseWeapon(weapon);
        //xxx select next weapon when current is empty... oh sigh
        //xxx also, select current weapon if we still have one, but weapon is
        //    undrawn! (???)
    }

    void firedWeapon(WeaponClass weapon, bool refire) {
        assert(!!weapon);
        //for cooldown
        mWeaponSet.firedWeapon(weapon);
        OnFireWeapon.raise(weapon, refire);
    }

    void doneFiring(Shooter sh) {
        if (!sh.weapon.dontEndRound)
            mWeaponUsed = true;
        //out of ammo
        if (!canUseWeapon(sh.weapon)) {
            unselectWeapon(sh);
        }
        checkWeaponStack();
        if ((sh.weapon.deselectAfterFire || !canUseWeapon(sh.weapon))
            && mCurrentWeapon is sh.weapon)
        {
            selectWeapon(null);
        }
        updateWeapon();
    }

    // <-- End WeaponController

    //for the hud
    WeaponClass weaponForIcon() {
        //icon if main weapon fails to display, or there is a secondary weapon
        if (mWeapons.length == 1 && !mWeapons[$-1].animationOK) {
            return mWeapons[0].weapon;
        } else if (mWeapons.length == 2) {
            return mWeapons[1].weapon;
        }
        return null;
    }

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
    private void wormAction() {
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
        mMoveVector = vec;

        bool canMove = isAlive() && isControllable();
        applyMoveVector(canMove ? mMoveVector : Vector2f(0));

        if (vec != mMoveVector && canMove)
            wormAction();
    }

    private void applyMoveVector(Vector2f vec) {
        if (!controllableMove(vec)) {
            //xxx assumes the worm uses only the x part (for now always true)
            mWorm.move(vec);
            if (mWeapons.length > 0) {
                //screen to math
                mWeapons[0].move(-vec.y);
                mWeapons[0].isSelected = mWorm.currentState.canFire;
            }
        }
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
        }

        if (mWorm && mWorm.activity())
            mLastActivity = mEngine.gameTime.current;

        if (!mEngaged)
            return;

        //check if fire button is being held down, waiting for right state
        if (mFireDown)
            fireMainWeapon(true);

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

        if (mWorm) {
            if (mWeapons.length > 0) {
                auto weapon = mWeapons[0];

                mWorm.fixed = weapon.isFixed;
                weapon.isSelected = mWorm.currentState.canFire;

                //hack to make weapon angle permanent
                mWeaponAngle = weapon.weaponAngle;
            } else {
                mWorm.fixed = false;
            }
        }
    }

    void youWinNow() {
        mWorm.youWinNow();
    }

    //check for any activity that might justify control beyond end-of-turn
    //e.g. still charging a weapon, still firing a multi-shot weapon
    bool delayedAction() {
        bool res = mWorm.delayedAction;
        foreach (ref sh; mWeapons) {
            res |= sh.delayedAction;
        }
        return res;
    }

    void forceAbort(bool unselect = true) {
        //forced stop of all action (like when being damaged)
        if (unselect) {
            for (int i = 0; i < mWeapons.length; i++) {
                unselectWeapon(i);
            }
        } else {
            foreach (ref sh; mWeapons) {
                sh.interruptFiring(false);
            }
            checkWeaponStack();
        }
        mWorm.forceAbort();
    }

    void pushControllable(Controllable c) {
        //if the new top object takes movement input, stop the current top
        if (c.move(mMoveVector))
            applyMoveVector(Vector2f(0));
        mControlStack ~= c;
    }

    void releaseControllable(Controllable c) {
        //stack gets cleared if the worm becomes unengaged
        if (mControlStack.length == 0)
            return;
        bool transferMove = false;
        if (mControlStack.length > 1 && c is mControlStack[$-1]) {
            //if removing the top object, transfer current movement to next
            c.move(Vector2f(0));
            transferMove = true;
        }
        //c does not have to be at the top of mControlStack
        arrayRemove(mControlStack, c);
        if (transferMove) {
            controllableMove(mMoveVector);
        }
    }

    //checks if this worm wants to blow up, returns true if it wants to or is
    //  in progress of blowing up
    bool checkDying() {
        return mWorm.checkSuiciding();
    }

    void prepareTurn() {
        digestPoison();
    }

    //if the worm is poisoned, die a little bit more
    void digestPoison() {
        mWorm.digestPoison();
    }

    //--

    //xxx not quite kosher
    TeamTheme color() {
        return mWorm.teamColor;
    }

    PointMode pointMode() {
        return mPointMode;
    }
    //note: also clears the target indicator
    void setPointMode(PointMode mode) {
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
            if (!mEngine.physicWorld.freePoint(where, 6)) {
                if (mCurrentWeapon) {
                    OnWeaponMisfire.raise(mCurrentWeapon, this,
                        WeaponMisfireReason.targetInvalid);
                }
                return;
            }
        }

        mTargetIsSet = true;
        WeaponTarget lastTarget = mCurrentTarget;
        mCurrentTarget.currentPos = where;

        switch(mPointMode) {
            case PointMode.targetTracking:
                //find sprite closest to where
                mEngine.physicWorld.objectsAt(where, 10,
                    (PhysicObject obj) {
                        auto spr = cast(Sprite)obj.backlink;
                        if (spr) {
                            mCurrentTarget.sprite = spr;
                            return false;
                        }
                        return true;
                    });
                //fall-through
            case PointMode.target:
                //X animation
                setIndicator(color.pointed, mCurrentTarget.currentPos);
                break;
            case PointMode.instant, PointMode.instantFree:
                //instant mode -> fire and forget
                if (fireMainWeapon(true)) {
                    //click effect (only if firing succeeded)
                    mEngine.animationEffect(color.click,
                        toVector2i(where), AnimationParams.init);
                } else {
                    //don't reset target if firing failed (this is esp.
                    //  important if firing failed because a prepare animation
                    //  is playing)
                    mCurrentTarget = lastTarget;
                }
                fireMainWeapon(false);
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

    //moved from game.d (was failing in multiplayer mode)
    //for each frame, the delegate gets called with the mouse position and the
    //  canvas while the topmost layer of the game is drawn
    //replace_mouse_pointer: if true, the mouse pointer is invisible in the game
    void addRenderOnMouse(bool delegate(Canvas, Vector2i) onRender,
        bool replace_mouse_pointer = false)
    {
        mMouseRender = onRender;
        //mMouseInvisible = replace_mouse_pointer;
    }

    //undo addRenderOnMouse()
    void removeRenderOnMouse(bool delegate(Canvas, Vector2i) dg) {
        if (mMouseRender !is dg)
            return;
        mMouseRender = null;
        //mMouseInvisible = false;
    }

    bool renderOnMouse(Canvas c, Vector2i mousepos) {
        if (mMouseRender)
            return mMouseRender(c, mousepos);
        return true;
    }
}
