module game.controller;

import common.animation;
import common.common;
import framework.commandline;
import game.game;
import game.gfxset;
import game.gobject;
import game.worm;
import game.crate;
import game.sprite;
import game.weapon.types;
import game.weapon.weapon;
import game.gamepublic;
import game.temp;
import game.gamemodes.base;
import physics.world;
import utils.vector2;
import utils.configfile;
import utils.log;
import utils.time;
import utils.md;
import utils.misc;
import utils.array;
import utils.queue;
import utils.reflection;

import math = tango.math.Math;


interface Controllable {
    bool fire(bool keyDown);
    bool jump(JumpMode j);
    bool move(Vector2f m);
    GObjectSprite getSprite();
}

class ServerTeam : Team {
    char[] mName = "unnamed team";
    TeamTheme teamColor;
    int gravestone;
    WeaponSet weapons;
    WeaponItem defaultWeapon;
    int initialPoints; //on loading
    Vector2f currentTarget;
    bool targetIsSet;
    GameController parent;
    bool forcedFinish;

    private {
        ServerTeamMember[] mMembers;  //all members (will not change in-game)
        TeamMember[] mMembers2;
        ServerTeamMember mCurrent;  //active worm that will receive user input
        ServerTeamMember mLastActive;  //worm that played last (to choose next)
        bool mActive;         //is this team playing?
        bool mOnHold;

        //if you can click anything, if true, also show that animation
        PointMode mPointMode;
        AnimationGraphic mCurrentTargetInd;

        Vector2f movementVec = {0, 0};
        bool mAlternateControl;
        bool mAllowSelect;   //can next worm be selected by user (tab)
        char[] mTeamId, mTeamNetId;

        int mGlobalWins;
        //incremented for each crate; xxx take over to next round
        int mDoubleDmg, mCrateSpy;
    }

    //node = the node describing a single team
    this(ConfigNode node, GameController parent) {
        this.parent = parent;
        mName = node.name;
        //xxx: error handling (when team-theme not found)
        char[] colorId = parent.checkTeamColor(node["color"]);
        teamColor = parent.engine.gfx.teamThemes[colorId];
        initialPoints = node.getIntValue("power", 100);
        //graveStone = node.getIntValue("grave", 0);
        //the worms currently aren't loaded by theirselves...
        foreach (char[] name, char[] value; node.getSubNode("member_names")) {
            auto worm = new ServerTeamMember(value, this);
            mMembers ~= worm;
        }
        mMembers2 = arrayCastCopyImplicit!(TeamMember, ServerTeamMember)(mMembers);
        //xxx error handling
        weapons = parent.initWeaponSet(node["weapon_set"]);
        //what's a default weapon? I don't know, so I can't bring it back
        //defaultWeapon = weapons.byId(node["default_weapon"]);
        gravestone = node.getIntValue("grave", 0);
        mAlternateControl = node.getStringValue("control") != "worms";
        mTeamId = node["id"];
        mTeamNetId = node["net_id"];
    }

    this (ReflectCtor c) {
    }

    // --- start Team

    char[] name() {
        return mName;
    }

    char[] id() {
        return mTeamId;
    }

    TeamTheme color() {
        return teamColor;
    }

    //if there's any alive worm
    bool alive() {
        foreach (m; mMembers) {
            if (m.alive())
                return true;
        }
        return false;
    }

    bool active() {
        return mActive;
    }

    int totalHealth() {
        int h;
        foreach (t; mMembers) {
            //no negative values
            //(it's sad - but the other team member don't care about the
            // wounded! it's a cruel game.)
            h += t.health < 0 ? 0 : t.health;
        }
        return h;
    }

    WeaponList getWeapons() {
        //convert WeaponSet to WeaponList
        WeaponItem[] items = weapons.weapons.values;
        WeaponList list;
        foreach (item; items) {
            WeaponListItem nitem;
            nitem.type = item.weapon;
            nitem.quantity = item.infinite ?
                WeaponListItem.QUANTITY_INFINITE : item.count;
            nitem.enabled = item.canUse();
            if (nitem.quantity > 0)
                list ~= nitem;
        }
        return list;
    }

    TeamMember[] getMembers() {
        return mMembers2;
    }

    TeamMember getActiveMember() {
        return current;
    }

    bool allowSelect() {
        return mAllowSelect;
    }

    int globalWins() {
        return mGlobalWins;
    }

    bool hasCrateSpy() {
        return mCrateSpy > 0;
    }

    bool hasDoubleDamage() {
        return mActive && (mDoubleDmg > 0);
    }

    // --- end Team

    char[] netId() {
        return mTeamNetId;
    }

    bool alternateControl() {
        return mAlternateControl;
    }

    private void placeMembers() {
        foreach (ServerTeamMember m; mMembers) {
            m.place();
        }
    }

    //wraps around, if w==null, return first element, if any
    private ServerTeamMember doFindNext(ServerTeamMember w) {
        return arrayFindNext(mMembers, w);
    }

    ServerTeamMember findNext(ServerTeamMember w, bool must_be_alive = false) {
        return arrayFindNextPred(mMembers, w,
            (ServerTeamMember t) {
                return !must_be_alive || t.alive;
            }
        );
    }

    ///activate a member for playing
    ///only for a member, not the team, use setActive for team
    void current(ServerTeamMember cur) {
        if (cur is mCurrent)
            return;
        if (mCurrent)
            mCurrent.setActive(false);
        mCurrent = cur;
        if (mCurrent) {
            mCurrent.setActive(true);
            //apply current movement (user may have pressed keys early)
            mCurrent.move(movementVec);
        }
    }
    ///get active member (can be null)
    ServerTeamMember current() {
        return mCurrent;
    }

    bool isActive() {
        return mActive;
    }

    bool isControllable() {
        return mActive && !mOnHold;
    }

    void setOnHold(bool hold) {
        if (!mActive)
            return;
        mOnHold = hold;
    }

    ///set if this team should be able to move/play
    //module-private (not to be used by gamemodes)
    private void setActive(bool act) {
        if (act == mActive)
            return;
        if (act) {
            //activating team
            mActive = act;
            parent.mActiveTeams ~= this;
            setOnHold(false);
            if (!activateNextInRow()) {
                //no worm could be activated (i.e. all dead)
                mActive = false;
                return;
            }
            forcedFinish = false;
            assert(!!current);
            /+ already in TeamMember?
            foreach (e; parent.mEvents) {
                e.onWormEvent(WormEvent.wormActivate, current);
            }
            +/
        } else {
            //deactivating
            arrayRemoveUnordered(parent.mActiveTeams, this); //should not fail
            mActive = act;
            current = null;
            setPointMode(PointMode.none);
            targetIsSet = false;
            setOnHold(false);
            if (mDoubleDmg > 0) {
                mDoubleDmg--;
            }
            mAllowSelect = false;
        }
    }

    ///select the worm to play when team becomes active
    bool activateNextInRow() {
        assert(mCurrent is null);
        assert(mActive);
        //this will activate the worm
        auto next = nextActive();
        current = next;
        //current may change by user input, mLastActive will not
        mLastActive = next;
        if (!next)
            return false;
        return true;
    }

    ///get the worm that would be next-in-row to move
    ///returns null if none left
    ServerTeamMember nextActive() {
        return findNext(mLastActive, true);
    }

    void allowSelect(bool allow) {
        mAllowSelect = allow;
    }

    ///choose next in reaction to user keypress
    void doChooseWorm() {
        if (!mActive || !mCurrent || !mAllowSelect)
            return;
        //activates next, and deactivates current
        //special case: only one left -> current() will do nothing
        current = findNext(mCurrent, true);
    }

    char[] toString() {
        return "[team '" ~ name ~ "']";
    }

    int opApply(int delegate(inout ServerTeamMember member) del) {
        foreach (m; mMembers) {
            int res = del(m);
            if (res)
                return res;
        }
        return 0;
    }

    //note: also clears the target indicator
    void setPointMode(PointMode mode) {
        if (mPointMode == mode)
            return;
        mPointMode = mode;
        setIndicator(null);
        //show X again, if set before
        if (mode == PointMode.target && targetIsSet)
            doSetPoint(currentTarget);
    }
    private bool checkPointMode() {
        return (mPointMode == PointMode.none || targetIsSet);
    }
    void doSetPoint(Vector2f where) {
        if (mPointMode == PointMode.none || !isControllable)
            return;

        if (mPointMode == PointMode.instantFree) {
            //move point out of landscape
            if (!parent.engine.physicworld.freePoint(where, 6))
                return;
        }

        targetIsSet = true;
        currentTarget = where;

        switch(mPointMode) {
            case PointMode.target:
                //X animation
                auto t = new AnimationGraphic();
                parent.engine.graphics.add(t);
                t.setAnimation(color.pointed.get);
                t.update(toVector2i(where));
                setIndicator(t);
                break;
            case PointMode.instant, PointMode.instantFree:
                //click effect
                parent.engine.callbacks.animationEffect(color.click.get,
                    toVector2i(where), AnimationParams.init);

                //instant mode -> fire and forget
                current.doFireDown(true);
                current.doFireUp();
                targetIsSet = false;
                break;
            default:
                assert(false);
        }
    }
    private void setIndicator(AnimationGraphic ind) {
        //only one cross indicator
        if (mCurrentTargetInd) {
            mCurrentTargetInd.remove();
        }
        mCurrentTargetInd = ind;
    }

    void dieNow() {
        mCurrent.worm.physics.applyDamage(100000, DamageCause.death);
    }

    //select (and draw) a weapon by its id
    void selectWeapon(WeaponClass weaponId) {
        if (mCurrent)
            mCurrent.selectWeapon(weapons.byId(weaponId));
    }

    bool teamAction() {
        if (mCurrent) {
            return mCurrent.actionPerformed();
        }
        return false;
    }

    //check if some parts of the team are still moving
    //gamemode plugin may use this to wait for the next turn
    bool isIdle() {
        foreach (m; mMembers) {
            //check if any alive member is still moving around
            if (m.alive() && !m.isIdle())
                return false;
        }
        return true;
    }

    void simulate() {
        if (mCurrentTargetInd) {
            if (mCurrentTargetInd.hasFinished()) {
                setIndicator(null);
            }
        }

        bool has_active_worm;

        foreach (m; mMembers) {
            m.simulate();
            has_active_worm |= m.active;
        }

        if (!has_active_worm)
            setActive(false);
    }

    bool checkDyingMembers() {
        foreach (m; mMembers) {
            if (m.checkDying())
                return true;
        }
        return false;
    }

    void youWinNow() {
        mGlobalWins++;
        foreach (m; mMembers) {
            m.youWinNow();
        }
    }

    void updateHealth() {
        foreach (m; mMembers) {
            m.updateHealth();
        }
    }

    void addWeapon(WeaponClass w, int quantity = 1) {
        weapons.addWeapon(w, quantity);
        parent.updateWeaponStats(null);
    }

    void skipTurn() {
        if (!mCurrent || !mActive)
            return;
        parent.engine.events.call("onTeamEvent", TeamEvent.skipTurn, this);
        current = null;
    }

    void surrenderTeam() {
        parent.engine.events.call("onTeamEvent", TeamEvent.surrender, this);
        current = null;
        //xxx: set worms to "white flag" animation first
        foreach (m; mMembers) {
            m.removeWorm();
        }
    }

    void addDoubleDamage() {
        mDoubleDmg++;
    }

    void addCrateSpy() {
        mCrateSpy++;
    }
}

//member of a team, currently (and maybe always) capsulates a WormSprite object
class ServerTeamMember : TeamMember, WormController {
    ServerTeam mTeam;
    char[] mName = "unnamed worm";

    private {
        WeaponItem mCurrentWeapon;
        WeaponClass mWormLastWeapon;
        bool mActive;
        Time mLastAction;
        Time mLastActivity = timeSecs(-40);
        WormSprite mWorm;
        bool mWormAction;
        Vector2f mLastMoveVector;
        GameEngine mEngine;
        int lastKnownLifepower;
        int mLastKnownPhysicHealth;
        int mCurrentHealth; //health value reported to client
        bool mFireDown;
        bool mWeaponUsed;
        bool mLimitedMode;
        Controllable[] mControlStack;
    }

    this(char[] a_name, ServerTeam a_team) {
        this.mName = a_name;
        this.mTeam = a_team;
        mEngine = mTeam.parent.engine;
    }

    this (ReflectCtor c) {
    }

    void removeWorm() {
        if (mWorm)
            mLastKnownPhysicHealth = mWorm.physics.lifepowerInt;
        mWorm = null;
    }

    //send new health value to client
    void updateHealth() {
        mCurrentHealth = health();
    }

    // --- start TeamMember

    char[] name() {
        return mName;
    }

    Team team() {
        return mTeam;
    }

    bool active() {
        return mActive;
    }

    bool alive() {
        //currently by havingwormspriteness... since dead worms haven't
        return (mWorm !is null) && !mWorm.isDead();
    }

    int currentHealth() {
        return mCurrentHealth;
    }

    Graphic getGraphic() {
        if (sprite && sprite.graphic) {
            return sprite.graphic.graphic;
        }
        return null;
    }

    Graphic getControlledGraphic() {
        auto spr = sprite;
        if (mControlStack.length > 0)
            spr = mControlStack[$-1].getSprite();
        if (spr && spr.graphic) {
            return spr.graphic.graphic;
        }
        return null;
    }

    // --- end TeamMember

    int health(bool realHp = false) {
        //hack to display negative values
        //the thing is that a worm can be dead even if the physics report a
        //positive value - OTOH, we do want these negative values... HACK GO!
        //mLastKnownPhysicHealth is there because mWorm could disappear
        auto h = mWorm ? mWorm.physics.lifepowerInt : mLastKnownPhysicHealth;
        if (alive() || realHp) {
            return h;
        } else {
            return h < 0 ? h : 0;
        }
    }

    private void place() {
        if (mWorm)
            return;
        //create and place into the landscape
        //habemus lumbricus
        mWorm = cast(WormSprite)mEngine.createSprite("worm");
        mTeam.parent.addMemberGameObject(this, mWorm);
        assert(mWorm !is null);
        mWorm.physics.lifepower = mTeam.initialPoints;
        lastKnownLifepower = health;
        updateHealth();
        //take control over dying, so we can let them die on end of turn
        mWorm.delayedDeath = true;
        mWorm.gravestone = mTeam.gravestone;
        mWorm.teamColor = mTeam.color;
        //set feedback interface to this class
        mWorm.wcontrol = this;
        //let Controller place the worm
        mTeam.parent.placeOnLandscape(mWorm);
    }

    GObjectSprite sprite() {
        return mWorm;
    }

    WormSprite worm() {
        return mWorm;
    }

    bool isControllable() {
        return mActive && alive() && mTeam.isControllable();
    }

    char[] toString() {
        return "[tworm " ~ (mTeam ? mTeam.toString() : null) ~ ":'" ~ name ~ "']";
    }

    //xxx should be named: round lost?
    bool lifeLost() {
        return health() < lastKnownLifepower;
    }

    void addHealth(int amount) {
        if (mWorm) {
            mWorm.physics.lifepower += amount;
            lastKnownLifepower += amount;
            updateHealth();
        }
    }

    void setActive(bool act) {
        if (mActive == act)
            return;
        if (act) {
            //member is being activated
            mActive = act;
            resetActivity();
            mWeaponUsed = false;
            mLimitedMode = false;
            lastKnownLifepower = health;
            //select last used weapon, select default if none
            if (!mCurrentWeapon)
                mCurrentWeapon = mTeam.defaultWeapon;
            selectWeapon(mCurrentWeapon);
        } else {
            //being deactivated
            controllableMove(Vector2f(0));
            mControlStack = null;
            move(Vector2f(0));
            mTeam.setPointMode(PointMode.none);
            mWormLastWeapon = null;
            resetActivity();
            mLastAction = Time.Null;
            if (mWorm) {
                //stop all action when turn ends
                mWorm.activateJetpack(false);
                mWorm.forceAbort();
                mWorm.weapon = null;
            }
            mFireDown = false;
            mActive = act;
        }
        WormEvent event = mActive ? WormEvent.wormActivate
            : WormEvent.wormDeactivate;
        mEngine.events.call("onWormEvent", event, this);
    }

    void setLimitedMode() {
        //can only leave this by deactivating
        mLimitedMode = true;
        mFireDown = false;
        updateWeapon();
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

    WormAniState wormState() {
        if (getGraphic() is null)
            return WormAniState.invisible;

        if (worm.hasDrowned())
            return WormAniState.drowning;

        if (!isControllable)
            return WormAniState.noMovement;

        if (mWorm.jetpackActivated())
            return WormAniState.jetpackFly;

        //no other possibilities currently
        return WormAniState.walk;
    }

    WeaponClass getCurrentWeapon() {
        return currentWeapon ? currentWeapon.weapon : null;
    }

    WeaponItem currentWeapon() {
        return mCurrentWeapon;
    }

    bool displayWeaponIcon() {
        if (!mWorm)
            return false;
        //this is probably still bogus, what about other possible stuff like
        //ropes etc. that could be added later?
        //suggestion: define when exactly a worm can throw a weapon and attempt
        //to display the weapon icon in these situations
        return mCurrentWeapon && mWorm.displayWeaponIcon;
    }

    void selectWeapon(WeaponItem weapon) {
        if (!isControllable || mLimitedMode)
            return;
        if (weapon && weapon !is mCurrentWeapon) {
            wormAction();
        }
        mCurrentWeapon = weapon;
        if (mCurrentWeapon)
            if (!mCurrentWeapon.canUse())
                mCurrentWeapon = null;
        updateWeapon();
    }

    void selectWeaponByClass(WeaponClass id) {
        selectWeapon(mTeam.weapons.byId(id));
    }

    //update weapon state of current worm (when new weapon selected)
    private void updateWeapon() {
        if (!mActive || !alive)
            return;

        WeaponClass selected;
        if (mCurrentWeapon) {
            if (!mCurrentWeapon.canUse() || mLimitedMode) {
                //nothing, leave selected = null
            } else if (currentWeapon.weapon) {
                selected = mCurrentWeapon.weapon;
            }
        }
        mEngine.events.call("onSelectWeapon", this, selected);
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

    void doFireDown(bool forceSelected = false) {
        if (!isControllable)
            return;

        bool success = true;
        if (!controllableFire(true)) {
            success = false;
            if (mWorm.allowAlternate && !forceSelected && !mTeam.alternateControl) {
                //non-alternate (worms-like) control -> spacebar disables
                //background weapon if possible (like jetpack)
                success = mWorm.fireAlternate();
                wormAction();
            } else if (mTeam.checkPointMode()) {
                success = worm.fire(false, forceSelected);
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

        if (controllableFire(false) || worm.fire(true)) {
            wormAction();
        }
    }

    //returns true if the keypress was taken
    bool doAlternateFire() {
        if (!isControllable)
            return false;

        if (mTeam.alternateControl) {
            //alternate (new-lumbricus) control: alternate-fire button (return)
            //refires background weapon (like jetpack-deactivation)
            if (mWorm.allowAlternate())
            {
                mWorm.fireAlternate();
                wormAction();
                return true;
            }
        } else {
            //worms-like: alternate-fire button (return) fires selected
            //weapon if in secondary mode
            if (mWorm.allowFireSecondary() && mTeam.checkPointMode()) {
                if (worm.fire()) {
                    wormAction();
                }
                return true;
            }
        }
        return false;
    }

    // Start WormController implementation (see game.worm) -->

    Vector2f getTarget() {
        return mTeam.currentTarget;
    }

    void reduceAmmo(Shooter sh) {
        WeaponItem wi = mTeam.weapons.byId(sh.weapon);
        assert(!!wi);
        wi.decrease();
        mTeam.parent.updateWeaponStats(this);
        if (!wi.canUse)
            //weapon ran out of ammo
            sh.interruptFiring();
        updateWeapon();
        //xxx select next weapon when current is empty... oh sigh
        //xxx also, select current weapon if we still have one, but weapon is
        //    undrawn! (???)
    }

    void firedWeapon(Shooter sh, bool refire) {
        assert(!!sh);
        mEngine.events.call("onFireWeapon", sh.weapon, refire);
    }

    void doneFiring(Shooter sh) {
        if (!sh.weapon.dontEndRound)
            mWeaponUsed = true;
        if (sh.weapon.deselectAfterFire)
            selectWeapon(null);
    }

    // <-- End WormController

    //has the worm fired something since he became active?
    bool weaponUsed() {
        return mWeaponUsed;
    }

    Time lastAction() {
        return mLastAction;
    }

    // != lastAction; last activity of the owned WormSprite (updated even if
    // member is not active)
    Time lastActivity() {
        return mLastActivity;
    }

    //called if any action is issued, i.e. key pressed to control worm
    //or if it was moved by sth. else
    void wormAction() {
        mWormAction = true;
        mLastAction = mTeam.parent.engine.gameTime.current;
        if (mTeam.allowSelect)
            mTeam.allowSelect = false;
    }
    //has the worm done anything since activation?
    bool actionPerformed() {
        return mWormAction;
    }

    void resetActivity() {
        mWormAction = false;
        mLastAction = timeSecs(-40); //xxx not kosher
    }

    private void move(Vector2f vec) {
        if (!alive || !isControllable || vec == mLastMoveVector) {
            mWorm.move(Vector2f(0));
            return;
        }

        mLastMoveVector = vec;
        if (!controllableMove(vec))
            mWorm.move(vec);
        wormAction();
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
        //xxx checking all members every frame, too expensive?
        if (!mWorm)
            return;

        //check if a worm is really dead (i.e. "gone"), like after drowning,
        //or when finished blowing himself up
        if (mWorm.physics.dead) {
            //xxx maybe rather have a onWormDie with a deathcause parameter?
            WormEvent deathcause = mWorm.hasDrowned()
                ? WormEvent.wormDrown : WormEvent.wormDie;
            mEngine.events.call("onWormEvent", deathcause, this);
            //NOTES:
            //drowning: drowned worms go physics.dead when reaching the bottom
            //else: death by exploding; suiciding worms go physics.dead when
            //      done blowing up
            removeWorm();
            return;
        }

        if (mWorm && mWorm.activity())
            mLastActivity = mEngine.gameTime.current;

        if (!mActive)
            return;

        if (mWorm) {
            if (mWorm.firedWeapon !is mWormLastWeapon) {
                mWormLastWeapon = mWorm.firedWeapon;
                if (mWormLastWeapon) {
                    mTeam.setPointMode(mWormLastWeapon.fireMode.point);
                } else {
                    mTeam.setPointMode(PointMode.none);
                }
            }
        }

        //check if fire button is being held down, waiting for right state
        if (mFireDown)
            doFireDown();

        //isn't done normally?
        if (!alive())
            setActive(false);
    }

    void youWinNow() {
        if (mWorm)
            mWorm.setState(mWorm.findState("win"));
    }

    bool delayedAction() {
        //check for any activity that might justify control beyond end-of-turn
        //e.g. still charging a weapon, still firing a multi-shot weapon
        return worm.delayedAction;
    }

    void forceAbort() {
        //forced stop of all action (like when being damaged)
        mWorm.forceAbort();
    }

    void pushControllable(Controllable c) {
        //if the new top object takes movement input, stop the current top
        if (c.move(mLastMoveVector))
            move(Vector2f(0));
        mControlStack ~= c;
    }

    void releaseControllable(Controllable c) {
        foreach (int idx, Controllable ctrl; mControlStack) {
            if (ctrl is c) {
                if (idx > 0)
                    mControlStack = mControlStack[0..idx];
                else
                    mControlStack = null;
                break;
            }
        }
    }

    //checks if this worm wants to blow up, returns true if it wants to or is
    //  in progress of blowing up
    bool checkDying() {
        //already dead -> boring
        if (!mWorm)
            return false;

        //3 possible states: healthy, unhealthy but not suiciding, suiciding
        if (mWorm.shouldDie() && !mWorm.isDelayedDying()) {
            //unhealthy, not suiciding
            mWorm.finallyDie();
            assert(mWorm.isDelayedDying() || mWorm.isDead());
            return true;
        } else if (mWorm.isDelayedDying()) {
            //suiciding
            return true;
        }
        return false;
    }

    ServerTeam serverTeam() {
        return mTeam;
    }

    GameEngine engine() {
        return mEngine;
    }
}

class WeaponSet {
    GameEngine engine;
    WeaponItem[WeaponClass] weapons;
    WeaponClass[] crateList;

    //config = item from "weapon_sets"
    this (GameEngine aengine, ConfigNode config) {
        this(aengine);
        foreach (ConfigNode node; config.getSubNode("weapon_list")) {
            try {
                auto weapon = new WeaponItem(this, node);
                weapons[weapon.weapon] = weapon;
                //only drop weapons that are not infinite already,
                //  and that can be used in the current world
                if (!weapon.infinite && weapon.weapon.canUse())
                    crateList ~= weapon.weapon;
            } catch (ClassNotRegisteredException e) {
                registerLog("game.controller")
                    ("Error in weapon set '"~config.name~"': "~e.msg);
            }
        }
    }

    //create empty set
    this(GameEngine aengine) {
        engine = aengine;
    }

    this (ReflectCtor c) {
    }

    void saveToConfig(ConfigNode config) {
        auto node = config.getSubNode("weapon_list");
        node.clear();
        //xxx doesn't give a deterministic order, but it shouldn't matter
        foreach (WeaponItem wi; weapons) {
            node.setStringValue(wi.weapon.name, wi.quantityToString);
        }
    }

    void addSet(WeaponSet other) {
        assert(!!other);
        //add weapons
        foreach (WeaponClass key, WeaponItem value; other.weapons) {
            if (!(key in weapons))
                weapons[key] = new WeaponItem(this);
            auto wi = *(key in weapons);
            wi.addFromItem(value);
        }
        //xxx: no crateList synchronization here, crate set is loaded
        //     independently anyway
    }

    WeaponItem byId(WeaponClass weaponId) {
        if (!weaponId)
            return null;
        if (weaponId in weapons)
            return weapons[weaponId];
        return null;
    }

    void addWeapon(WeaponClass c, int quantity = 1) {
        WeaponItem item = byId(c);
        if (!item) {
            item = new WeaponItem(this);
            item.mWeapon = c;
            weapons[c] = item;
        }
        if (!item.infinite) {
            item.mQuantity += quantity;
        }
    }

    //choose a random weapon based on this weapon set
    //returns null if none was found
    //xxx: Implement different drop probabilities (by value/current count)
    WeaponClass chooseRandomForCrate() {
        if (crateList.length > 0) {
            int r = engine.rnd.next(0, crateList.length);
            return crateList[r];
        } else {
            return null;
        }
    }
}

class WeaponItem {
    private {
        GameEngine mEngine;
        WeaponSet mContainer;
        WeaponClass mWeapon;
        int mQuantity;
        bool mInfiniteQuantity;
    }

    bool haveAtLeastOne() {
        return mQuantity > 0 || mInfiniteQuantity;
    }

    bool canUse() {
        if (!haveAtLeastOne())
            return false;
        return mWeapon.canUse();
    }

    void decrease() {
        if (mQuantity > 0)
            mQuantity--;
    }

    WeaponClass weapon() {
        return mWeapon;
    }

    bool infinite() {
        return mInfiniteQuantity;
    }
    int count() {
        return infinite ? typeof(mQuantity).max : mQuantity;
    }

    this (WeaponSet parent) {
        mContainer = parent;
        mEngine = parent.engine;
    }

    //config = an item in "weapon_list"
    this (WeaponSet parent, ConfigNode config) {
        this(parent);
        auto w = config.name;
        //may throw ClassNotRegisteredException
        mWeapon = mEngine.findWeaponClass(w);
        if (config.value == "inf") {
            mInfiniteQuantity = true;
        } else {
            mQuantity = config.getCurValue!(int)(0);
        }
    }

    this (ReflectCtor c) {
    }

    //add the stockpile of another WeaponItem to this one
    //if this.mWeapon is not yet set, it is set to the other item's weapon
    void addFromItem(WeaponItem other) {
        assert(!!other);
        if (!mWeapon)
            mWeapon = other.weapon;
        assert(!!mWeapon);
        if (infinite || other.infinite)
            mInfiniteQuantity = true;
        else
            mQuantity += other.count;
    }

    char[] quantityToString() {
        if (infinite)
            return "inf";
        return to!(char[])(mQuantity);
    }
}

//the GameController controlls the game play; especially, it converts keyboard
//events into worm moves (or weapon moves!), controlls which object is focused
//by the "camera", and also manages worm teams
//xxx: move gui parts out of this
class GameController : GameLogicPublic {
    private {
        GameEngine mEngine;
        static LogStruct!("game.controller") log;

        ServerTeam[] mTeams;
        ServerTeam[] mActiveTeams;

        //same as mTeams, but array of another type (for gamepublic.d)
        Team[] mTeams2;

        ServerTeamMember[GameObject] mGameObjectToMember;

        //xxx for loading only
        ConfigNode[char[]] mWeaponSets;
        WeaponSet mCrateSet;

        bool mIsAnythingGoingOn; // (= hack)

        const cMessageTime = timeSecs(1.5f);
        Time mLastMsgTime;
        int mMessageCounter;

        int mWeaponListChangeCounter;

        Gamemode mGamemode;
        char[] mGamemodeId;

        CrateSprite mLastCrate;  //just to drop it on spacebar
        bool mGameEnded;

        //Medkit, medkit+tool, medkit+tool+unrigged weapon
        //  (rest is rigged weapon)
        const cCrateProbs = [0.20f, 0.40f, 0.95f];
        int[TeamTheme.cTeamColors.length] mTeamColorCache;
    }

    package ControllerPlugin[] mPlugins;

    //when a worm collects a tool from a crate
    ChainDelegate!(ServerTeamMember, CollectableTool) collectTool;

    this(GameEngine engine, GameConfig config) {
        mEngine = engine;
        mEngine.setController(this);

        setupControllerEvents();

        if (config.weapons) {
            loadWeaponSets(config.weapons);
        }
        if (config.teams) {
            loadTeams(config.teams);
        }
        if (config.levelobjects) {
            loadLevelObjects(config.levelobjects);
        }

        mGamemodeId = config.gamemode["mode"];
        mGamemode = GamemodeFactory.instantiate(mGamemodeId, this,
            config.gamemode);

        //only valid while loading
        mWeaponSets = null;

        new ControllerMsgs(this);
        new ControllerStats(this);
        new ControllerPersistence(this);

        mEngine.finishPlace();

        collectTool ~= &doCollectTool;
    }

    this (ReflectCtor c) {
        Types t = c.types();
        t.registerMethod(this, &doCollectTool, "doCollectTool");
    }

    private void setupControllerEvents() {
        engine.events.declare!()("onGameStart");
        engine.events.declare!(GameObject, GObjectSprite, float, WeaponClass)
            ("onDamage");
        engine.events.declare!(int, GameObject)("onDemolition");
        //worm draws a weapon (wclass may be null if weapon was put away)
        engine.events.declare!(ServerTeamMember, WeaponClass)("onSelectWeapon");
        engine.events.declare!(WeaponClass, bool)("onFireWeapon");
        engine.events.declare!(WormEvent, ServerTeamMember)("onWormEvent");
        engine.events.declare!(TeamEvent, ServerTeam)("onTeamEvent");
        engine.events.declare!(CrateType)("onCrateDrop");
        engine.events.declare!(ServerTeamMember, Collectable[])("onCrateCollect");
        //imo, sudden death is common enough to be here
        engine.events.declare!()("onSuddenDeath");
        //also called on a tie, with winner = null
        engine.events.declare!(Team)("onVictory");
    }

    //--- start GameLogicPublic

    Team[] getTeams() {
        return mTeams2;
    }

    char[] gamemode() {
        return mGamemodeId;
    }

    bool gameEnded() {
        return mGamemode.ended;
    }

    Object gamemodeStatus() {
        return mGamemode.getStatus;
    }

    WeaponClass[] weaponList() {
        return mEngine.weaponList();
    }

    int getWeaponListChangeCounter() {
        return mWeaponListChangeCounter;
    }

    //--- end GameLogicPublic

    void updateWeaponStats(TeamMember m) {
        changeWeaponList(m ? m.team : null);
    }

    private void changeWeaponList(Team t) {
        engine.callbacks.weaponsChanged(t);
    }

    GameEngine engine() {
        return mEngine;
    }

    void messageAdd(char[] msg, char[][] args = null, Team actor = null,
        Team viewer = null)
    {
        messageIsIdle(); //maybe reset wait time
        if (mMessageCounter == 0)
            mLastMsgTime = mEngine.gameTime.current;
        mMessageCounter++;

        GameMessage gameMsg;
        gameMsg.lm.id = msg;
        gameMsg.lm.args = args;
        gameMsg.lm.rnd = engine.rnd.next;
        gameMsg.actor = actor;
        gameMsg.viewer = viewer;
        engine.callbacks.showMessage(gameMsg);
    }

    bool messageIsIdle() {
        if (mLastMsgTime + cMessageTime*mMessageCounter
            >= mEngine.gameTime.current)
        {
            //did wait long enough
            mMessageCounter = 0;
            return false;
        }
        return true;
    }

    void startGame() {
        assert(!mIsAnythingGoingOn);
        mIsAnythingGoingOn = true;
        //nothing happening? start a round
        engine.events.call("onGameStart");

        deactivateAll();
        //lol, see gamemode comments for how this should really be used
        mGamemode.initialize();
        mGamemode.startGame();
    }

    void simulate() {
        Time diffT = mEngine.gameTime.difference;

        if (!mIsAnythingGoingOn) {
            startGame();
        } else {
            foreach (t; mTeams)
                t.simulate();

            mGamemode.simulate();

            if (mLastCrate) {
                if (!mLastCrate.active) mLastCrate = null;
            }

            if (mGamemode.ended() && !mGameEnded) {
                mGameEnded = true;
                engine.events.call!()("onGameEnded");
            }
        }
    }

    //return true if there are dying worms
    bool checkDyingWorms() {
        foreach (t; mTeams) {
            //death is in no hurry, one worm a frame
            if (t.checkDyingMembers())
                return true;
        }
        return false;
    }

    //send clients new health values
    void updateHealth() {
        foreach (t; mTeams) {
            t.updateHealth();
        }
    }

    ServerTeam[] teams() {
        return mTeams;
    }

    //this function now is no longer special, can use t.setActive directly
    void activateTeam(ServerTeam t, bool active = true) {
        t.setActive(active);
    }

    void deactivateAll() {
        foreach (t; mTeams) {
            activateTeam(t, false);
        }
        mActiveTeams = null;
    }

    bool membersIdle() {
        foreach (t; mTeams) {
            if (!t.isIdle())
                return false;
        }
        return true;
    }

    //actually still stupid debugging code
    private void spawnWorm(Vector2i pos) {
        //now stupid debug code in another way
        auto w = mEngine.createSprite("worm");
        w.setPos(toVector2f(pos));
        w.active = true;
    }

    WeaponSet initWeaponSet(char[] id) {
        ConfigNode ws;
        if (id in mWeaponSets)
            ws = mWeaponSets[id];
        else
            ws = mWeaponSets["default"];
        if (!ws)
            throw new Exception("Weapon set " ~ id ~ " not found.");
        return new WeaponSet(mEngine, ws);
    }

    //config = the "teams" node, i.e. from data/data/teams.conf
    private void loadTeams(ConfigNode config) {
        mTeams = null;
        foreach (ConfigNode sub; config) {
            addTeam(sub);
        }
        mTeams2 = arrayCastCopyImplicit!(Team, ServerTeam)(mTeams);
        placeWorms();
    }

    //config = the "teams" node, i.e. from data/data/teams.conf
    private void addTeam(ConfigNode config) {
        auto team = new ServerTeam(config, this);
        mTeams ~= team;
    }

    private char[] checkTeamColor(char[] col) {
        int colId = 0;  //default to first color
        foreach (int idx, char[] tc; TeamTheme.cTeamColors) {
            if (col == tc) {
                colId = idx;
                break;
            }
        }

        //assign the color least used, preferring the one requested
        foreach (int idx, int count; mTeamColorCache) {
            if (count < mTeamColorCache[colId])
                colId = idx;
        }
        mTeamColorCache[colId]++;
        return TeamTheme.cTeamColors[colId];
    }

    //like "weapon_sets" in gamemode.conf, but renamed according to game config
    private void loadWeaponSets(ConfigNode config) {
        //1. complete sets
        char[] firstId;
        foreach (ConfigNode item; config) {
            if (firstId.length == 0)
                firstId = item.name;
            if (item.value.length == 0)
                mWeaponSets[item.name] = item;
        }
        //2. referenced sets
        foreach (ConfigNode item; config) {
            if (item.value.length > 0) {
                if (!(item.value in mWeaponSets))
                    throw new Exception("Weapon set " ~ item.value
                        ~ " not found.");
                mWeaponSets[item.name] = mWeaponSets[item.value];
            }
        }
        if (mWeaponSets.length == 0)
            throw new Exception("No weapon sets defined.");
        //we always need a default set
        assert(firstId in mWeaponSets);
        if (!("default" in mWeaponSets))
            mWeaponSets["default"] = mWeaponSets[firstId];
        //crate weapon set is named "crate_set" (will fall back to "default")
        mCrateSet = initWeaponSet("crate_set");
    }

    //create and place worms when necessary
    private void placeWorms() {
        log("placing worms...");

        foreach (t; mTeams) {
            t.placeMembers();
        }

        log("placing worms done.");
    }

    private void loadLevelObjects(ConfigNode objs) {
        log("placing level objects");
        foreach (ConfigNode sub; objs) {
            auto mode = sub.getStringValue("mode", "unknown");
            if (mode == "random") {
                auto cnt = sub.getIntValue("count");
                log("count {} type {}", cnt, sub["type"]);
                for (int n = 0; n < cnt; n++) {
                    try {
                        placeOnLandscape(mEngine.createSprite(sub["type"]));
                    } catch {
                        log("Warning: Placing {} objects failed", sub["type"]);
                        continue;
                    }
                }
            } else {
                log("warning: unknown placing mode: '{}'", sub["mode"]);
            }
        }
        log("done placing level objects");
    }

    //associate go with member; used i.e. for who-damages-who reporting
    //NOTE: tracking membership of projectiles generated by worms works slightly
    //  differently (projectiles form a singly linked list to who fired them)
    void addMemberGameObject(ServerTeamMember member, GameObject go) {
        //NOTE: the GameObject stays in this AA for forever
        //  in some cases, it could be released again (i.e. after a new round
        //  was started)
        assert(!go.createdBy, "fix memberFromGameObject and remove this");
        mGameObjectToMember[go] = member;
    }

    ServerTeamMember memberFromGameObject(GameObject go, bool transitive) {
        //typically, GameObject is transitively (consider spawning projectiles!)
        //created by a Worm
        //"victim" from reportViolence should be directly a Worm

        while (transitive && go.createdBy) {
            go = go.createdBy;
        }

        return aaIfIn(mGameObjectToMember, go);
    }

    WeaponClass weaponFromGameObject(GameObject go) {
        //commonly, everything causing damage is transitively created by
        //  a Shooter, but not always (consider landscape objects/crates/
        //  exploding worms)
        Shooter sh;
        while ((sh = cast(Shooter)go) is null && go.createdBy) {
            go = go.createdBy;
        }
        if (sh !is null)
            return sh.weapon;
        return null;
    }

    void reportViolence(GameObject cause, GObjectSprite victim, float damage) {
        assert(!!cause && !!victim);
        auto wclass = weaponFromGameObject(cause);
        engine.events.call("onDamage", cause, victim, damage, wclass);
    }

    void reportDemolition(int pixelCount, GameObject cause) {
        assert(!!cause);
        engine.events.call("onDemolition", pixelCount, cause);
    }

    //queue for placing anywhere on landscape
    //call engine.finishPlace() when done with all sprites
    void placeOnLandscape(GObjectSprite sprite, bool must_place = true) {
        mEngine.queuePlaceOnLandscape(sprite);
    }

    Collectable[] fillCrate() {
        Collectable[] ret;
        float r = engine.rnd.nextDouble2();
        if (r < cCrateProbs[0]) {
            //medkit
            ret ~= new CollectableMedkit(50);
        } else if (r < cCrateProbs[1]) {
            //tool
            //sorry about this
            switch (engine.rnd.next(3)) {
                case 0: ret ~= new CollectableToolCrateSpy(); break;
                case 1: ret ~= new CollectableToolDoubleTime(); break;
                case 2: ret ~= new CollectableToolDoubleDamage(); break;
            }
        } else {
            //weapon
            auto content = mCrateSet.chooseRandomForCrate();
            if (content) {
                ret ~= new CollectableWeapon(content, 1);
                if (r > cCrateProbs[2]) {
                    //add a bomb to that :D
                    ret ~= new CollectableBomb();
                }
            } else {
                log("failed to create crate contents");
            }
        }
        return ret;
    }

    //  silent = true to prevent generating an event (for debug drop, to
    //           prevent message spam)
    bool dropCrate(bool silent = false) {
        Vector2f from, to;
        float water = engine.waterOffset - 10;
        if (!engine.placeObjectRandom(water, 10, 25, from, to)) {
            log("couldn't find a safe drop-position");
            return false;
        }

        GObjectSprite s = engine.createSprite("crate");
        CrateSprite crate = cast(CrateSprite)s;
        assert(!!crate);
        //put stuffies into it
        crate.stuffies = fillCrate();
        //actually start it
        crate.setPos(from);
        crate.active = true;
        mLastCrate = crate;
        if (!silent) {
            engine.events.call("onCrateDrop", crate.crateType);
        }
        log("drop {} -> {}", from, to);
        return true;
    }

    void instantDropCrate() {
        if (mLastCrate)
            mLastCrate.unParachute();
    }

    private bool doCollectTool(ServerTeamMember collector, CollectableTool tool)
    {
        if (auto t = cast(CollectableToolCrateSpy)tool) {
            collector.serverTeam.addCrateSpy();
            return true;
        }
        if (auto t = cast(CollectableToolDoubleDamage)tool) {
            collector.serverTeam.addDoubleDamage();
            return true;
        }
        return false;
    }

    //show effects of sudden death start
    //doesn't raise water / affect gameplay
    void startSuddenDeath() {
        engine.addEarthQuake(500, timeSecs(4.5f), true);
        engine.callbacks.nukeSplatEffect();
        engine.events.call("onSuddenDeath");
    }
}



enum WormEvent {
    wormDie,
    wormDrown,
    wormActivate,
    wormDeactivate,
}

enum TeamEvent {
    skipTurn,
    surrender,
}

abstract class ControllerPlugin {
    private {
        GameController mController;
        GameEngine mEngine;
    }

    this(GameController c) {
        mController = c;
        mEngine = c.engine;
        mController.mPlugins ~= this;
        regMethods();
    }
    this(ReflectCtor c) {
        regMethods(c.types);
    }

    final GameController controller() {
        return mController;
    }

    final GameEngine engine() {
        return mEngine;
    }

    abstract protected void regMethods(Types t = null);

    static char[] genRegFunc(char[][] mnames) {
        char[] ret = `override protected void regMethods(Types t = null) {`;
        foreach (n; mnames) {
            ret ~= `
                if (t) {
                    t.registerMethod(this, &`~n~`, "`~n~`");
                }
                if (mEngine) {
                    mEngine.events.register("`~n~`", &`~n~`);
                }
                `;
        }
        ret ~= `}`;
        return ret;
    }
}

//the idea was that the whole game state should be observable (including
//events), so you can move displaying all messages into a separate piece of
//code, instead of creating messages directly
class ControllerMsgs : ControllerPlugin {
    this(GameController c) {
        super(c);
    }
    this(ReflectCtor c) {
        super(c);
    }

    mixin(genRegFunc(["onGameStart", "onSelectWeapon", "onWormEvent",
        "onTeamEvent", "onCrateDrop", "onCrateCollect", "onSuddenDeath",
        "onVictory", "onGameEnded"]));

    private void onGameStart() {
        controller.messageAdd("msggamestart", null);
    }

    private void onSelectWeapon(ServerTeamMember m, WeaponClass wclass) {
        //xxx just copying old code... maybe this can be extended to show
        //    grenade timer messages (like in wwp)
        /*if (wclass) {
            controller.messageAdd("msgselweapon", ["_.weapons." ~ wclass.name],
                m.team, m.team);
        } else {
            controller.messageAdd("msgnoweapon", null, m.team, m.team);
        }*/
    }

    private void onWormEvent(WormEvent id, ServerTeamMember m) {
        switch (id) {
            case WormEvent.wormActivate:
                controller.messageAdd("msgwormstartmove", [m.name], m.team,
                    m.team);
                break;
            case WormEvent.wormDrown:
                controller.messageAdd("msgdrown", [m.name], m.team);
                break;
            case WormEvent.wormDie:
                controller.messageAdd("msgdie", [m.name], m.team);
                break;
            default:
        }
    }

    private void onTeamEvent(TeamEvent id, ServerTeam t) {
        switch (id) {
            case TeamEvent.skipTurn:
                controller.messageAdd("msgskipturn", [t.name()], t);
                break;
            case TeamEvent.surrender:
                controller.messageAdd("msgsurrender", [t.name()], t);
                break;
            default:
        }
    }

    private void onCrateDrop(CrateType type) {
        switch (type) {
            case CrateType.med:
                controller.messageAdd("msgcrate_medkit");
                break;
            case CrateType.tool:
                controller.messageAdd("msgcrate_tool");
                break;
            default:
                controller.messageAdd("msgcrate");
        }
    }

    private void onCrateCollect(ServerTeamMember member,
        Collectable[] stuffies)
    {
        foreach (item; stuffies) {
            if (auto weapon = cast(CollectableWeapon)item) {
                //weapon
                controller.messageAdd("collect_item", [member.name(),
                    "_." ~ item.id(), to!(char[])(weapon.quantity)],
                    member.team, member.team);
            } else if (auto medkit = cast(CollectableMedkit)item) {
                //medkit
                controller.messageAdd("collect_medkit", [member.name(),
                    to!(char[])(medkit.amount)], member.team, member.team);
            } else if (auto tool = cast(CollectableTool)item) {
                //tool
                controller.messageAdd("collect_tool", [member.name(),
                    "_." ~ item.id()], member.team, member.team);
            } else if (auto bomb = cast(CollectableBomb)item) {
                //crate with bomb
                controller.messageAdd("collect_bomb", [member.name()],
                    member.team, member.team);
            }
        }
    }

    private void onSuddenDeath() {
        controller.messageAdd("msgsuddendeath");
    }

    private void onVictory(Team winner) {
        if (winner) {
            controller.messageAdd("msgwin", [winner.name], winner);
        } else {
            controller.messageAdd("msgnowin");
        }
    }

    private void onGameEnded() {
        //xxx is this really useful? I would prefer showing the
        //  "team xxx won" message longer
        controller.messageAdd("msggameend");
    }
}

//stupid simple statistics module
//this whole thing is more or less debugging code
//
//currently missing:
//  - Team/Worm-based statistics
//  - Proper output/sending to clients
//  - timecoded events, with graph drawing?
//  - gamemode dependency?
class ControllerStats : ControllerPlugin {
    private {
        static LogStruct!("gameevents") log;
    }

    this(GameController c) {
        super(c);
    }
    this(ReflectCtor c) {
        super(c);
    }

    mixin(genRegFunc(["onDamage", "onDemolition", "onFireWeapon",
        "onWormEvent", "onCrateCollect", "onGameEnded"]));

    private void onDamage(GameObject cause, GObjectSprite victim, float damage,
        WeaponClass wclass)
    {
        char[] wname = "unknown_weapon";
        if (wclass)
            wname = wclass.name;
        auto m1 = controller.memberFromGameObject(cause, true);
        auto m2 = controller.memberFromGameObject(victim, false);
        char[] dmgs = myformat("{}", damage);
        if (victim.physics.lifepower < 0) {
            float ov = min(-victim.physics.lifepower, damage);
            mOverDmg += ov;
            dmgs = myformat("{} ({} overdmg)", damage, ov);
        }
        mTotalDmg += damage;
        if (m1 && m2) {
            if (m1 is m2)
                log("worm {} injured himself by {} with {}", m1, dmgs, wname);
            else
                log("worm {} injured {} by {} with {}", m1, m2, dmgs, wname);
        } else if (m1 && !m2) {
            mCollateralDmg += damage;
            log("worm {} caused {} collateral damage with {}", m1, dmgs,
                wname);
        } else if (!m1 && m2) {
            //neutral damage is not caused by weapons
            assert(wclass is null, "some createdBy relation wrong");
            mNeutralDamage += damage;
            log("victim {} received {} damage from neutral objects", m2,
                dmgs);
        } else {
            //most likely level objects blowing up other objects
            //  -> count as collateral
            mCollateralDmg += damage;
            log("unknown damage {}", dmgs);
        }
    }

    private void onDemolition(int pixelCount, GameObject cause) {
        mPixelsDestroyed += pixelCount;
        //log("blasted {} pixels of land", pixelCount);
    }

    private void onFireWeapon(WeaponClass wclass, bool refire = false) {
        char[] wname = "unknown_weapon";
        if (wclass)
            wname = wclass.name;
        log("Fired weapon (refire={}): {}",refire,wname);
        if (!refire) {
            if (!(wclass in mWeaponStats))
                mWeaponStats[wclass] = 1;
            else
                mWeaponStats[wclass] += 1;
            mShotsFired++;
        }
    }

    private void onWormEvent(WormEvent id, ServerTeamMember m) {
        switch (id) {
            case WormEvent.wormActivate:
                log("Worm activate: {}", m);
                break;
            case WormEvent.wormDeactivate:
                log("Worm deactivate: {}", m);
                break;
            case WormEvent.wormDie:
                log("Worm die: {}", m);
                mWormsDied++;
                break;
            case WormEvent.wormDrown:
                int dh = m.currentHealth() - m.health();
                log("Worm drown (floating label would say: {}): {} ", dh, m);
                if (m.health(true) > 0)
                    mWaterDmg += m.health(true);
                mWormsDrowned++;
                break;
            default:
        }
    }

    private void onCrateCollect(ServerTeamMember m, Collectable[] stuffies) {
        log("{} collects crate: {}", m, stuffies);
        mCrateCount++;
    }

    private void onGameEnded() {
        output();
    }

    //xxx for debugging only

    private {
        float mTotalDmg = 0f, mCollateralDmg = 0f, mOverDmg = 0f,
            mWaterDmg = 0f, mNeutralDamage = 0f;
        int mWormsDied, mWormsDrowned, mShotsFired, mPixelsDestroyed,
            mCrateCount;
        int[WeaponClass] mWeaponStats;
    }

    //dump everything to console
    void output() {
        log("Worms killed: {} ({} died, {} drowned)", mWormsDied+mWormsDrowned,
            mWormsDied, mWormsDrowned);
        log("Total damage caused: {}", mTotalDmg);
        log("Damage by water: {}", mWaterDmg);
        log("Collateral damage caused: {}", mCollateralDmg);
        log("Damage by neutral objects: {}", mNeutralDamage);
        log("Total overdamage: {}", mOverDmg);
        log("Shots fired: {}", mShotsFired);
        int c = -1;
        WeaponClass maxw;
        foreach (WeaponClass wc, int count; mWeaponStats) {
            if (count > c) {
                maxw = wc;
                c = count;
            }
        }
        if (maxw)
            log("Favorite weapon: {} ({} shots)", maxw.name, c);
        log("Landscape destroyed: {} pixels", mPixelsDestroyed);
        log("Crates collected: {}", mCrateCount);
    }
}

//this plugin adds persistence functionality for teams (wins / weapons)
//  (overengineering ftw)
class ControllerPersistence : ControllerPlugin {
    private {
        const cKeepWeaponsDef = false;
        const cGiveWeaponsDef = int.max;   //default: always give
        const cVictoryDef = "absolute";
        const cVictoryCountDef = 2;
    }

    this(GameController c) {
        super(c);
    }
    this(ReflectCtor c) {
        super(c);
    }

    mixin(genRegFunc(["onGameStart", "onGameEnded"]));

    private void onGameStart() {
        foreach (t; controller.teams) {
            load(t);
        }
    }

    private void onGameEnded() {
        foreach (t; controller.teams) {
            save(t);
        }

        //reduce round count for giving weapons
        int curGiveWeapons = engine.persistentState.getValue("give_weapons",
            cGiveWeaponsDef);
        engine.persistentState.setValue("give_weapons", curGiveWeapons - 1);

        //increase total round count
        engine.persistentState.setValue("round_counter",
            engine.persistentState.getValue("round_counter", 0) + 1);

        //check if we have a winner
        //if the victory condition triggered, the "winner" field will be set,
        //  which can be checked by the GUI
        ServerTeam winner;
        if (checkVictory(engine.persistentState.getStringValue("victory_type",
            cVictoryDef), winner))
        {
            //this was the final round, game is over
            if (winner) {
                engine.persistentState.setStringValue("winner",
                    winner.netId ~ "." ~ winner.id);
            } else {
                //no winner (e.g. game lasted a fixed number of rounds)
                //the game is over anyway, set "winner" field as marker
                engine.persistentState.setStringValue("winner", "draw");
            }
        }

        debug {
            gConf.saveConfig(engine.persistentState, "persistence_debug.conf");
        }
    }

    private void load(ServerTeam t) {
        auto node = persistNode(t);
        t.mGlobalWins = node.getValue!(int)("global_wins", 0);

        //start with empty weapon set if give_weapons not set
        if (engine.persistentState.getValue("give_weapons",
            cGiveWeaponsDef) <= 0)
        {
            t.weapons = new WeaponSet(engine);
        }
        //add weapons from last round
        if (engine.persistentState.getValue("keep_weapons", cKeepWeaponsDef)) {
            scope lastRoundWeapons = new WeaponSet(engine,
                node.getSubNode("weapons"));
            t.weapons.addSet(lastRoundWeapons);
        }

        t.mCrateSpy = node.getValue("crate_spy", t.mCrateSpy);
        t.mDoubleDmg = node.getValue("double_damage", t.mDoubleDmg);
    }

    private void save(ServerTeam t) {
        auto node = persistNode(t);
        node.setValue!(int)("global_wins", t.globalWins);

        //save this round's weapons
        if (engine.persistentState.getValue("keep_weapons", cKeepWeaponsDef)) {
            t.weapons.saveToConfig(node.getSubNode("weapons"));
        }

        node.setValue("crate_spy", t.mCrateSpy);
        node.setValue("double_damage", t.mDoubleDmg);
    }

    //return true if the game is over
    //xxx this does not have to be here, all needed information is in
    //    engine.persistentState
    private bool checkVictory(char[] condition, out ServerTeam winner) {
        //first check error cases (0 or 1 team in the game)
        //Note: even if teams surrender or leave during game, they are not
        //      removed from this list
        if (controller.teams.length == 0)
            return true;
        if (controller.teams.length == 1) {
            winner = controller.teams[0];
            return true;
        }

        //determine first and second by number of wins
        ServerTeam first, second;
        foreach (t; controller.teams) {
            if (!first || t.globalWins >= first.globalWins) {
                second = first;
                first = t;
            }
        }
        assert(!!first && !!second);

        //now check victory condition
        int rounds = engine.persistentState.getValue("round_counter", 1);
        int victoryCount = engine.persistentState.getValue("victory_count",
            cVictoryCountDef);
        switch (condition) {
            case "difference":
                //need at least victoryCount more than second place
                if (first.globalWins >= second.globalWins + victoryCount)
                {
                    winner = first;
                    return true;
                }
                break;
            case "rounds":
                //play a fixed number of rounds
                if (rounds >= victoryCount) {
                    //best team wins
                    if (first.globalWins > second.globalWins)
                        winner = first;
                    return true;
                }
                break;
            case "absolute":
            default:  //"absolute" is the default
                //win if a fixed number of points is reached
                if (first.globalWins >= victoryCount) {
                    winner = first;
                    return true;
                }
                break;
        }
        return false;
    }

    private ConfigNode persistNode(ServerTeam t) {
        return engine.persistentState.getSubNode(
            t.netId ~ "." ~ t.id);
    }
}
