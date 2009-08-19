module game.controller;

import common.animation;
import common.common;
import common.scene;
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
import game.sequence;
import game.gamemodes.base;
import game.controller_events;
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
import tango.util.Convert : to;


interface Controllable {
    bool fire(bool keyDown);
    bool jump(JumpMode j);
    bool move(Vector2f m);
    GObjectSprite getSprite();
}

class Team {
    char[] mName = "unnamed team";
    TeamTheme teamColor;
    int gravestone;
    WeaponSet weapons;
    WeaponItem defaultWeapon;
    int initialPoints; //on loading
    WeaponTarget currentTarget;
    bool targetIsSet;
    GameController parent;
    bool forcedFinish;

    private {
        TeamMember[] mMembers;  //all members (will not change in-game)
        TeamMember mCurrent;  //active worm that will receive user input
        TeamMember mLastActive;  //worm that played last (to choose next)
        bool mActive;         //is this team playing?
        bool mOnHold;

        //if you can click anything, if true, also show that animation
        PointMode mPointMode;
        Animator mCurrentTargetInd;

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
            auto worm = new TeamMember(value, this);
            mMembers ~= worm;
        }
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

    TeamMember[] getMembers() {
        return mMembers;
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

    //returns an id that is a) unique over all teams in the game, and
    //  b) will remain the same over all played rounds
    char[] uniqueId() {
        return mTeamNetId ~ "." ~ mTeamId;
    }

    void globalWins(int wins) {
        mGlobalWins = wins;
    }

    void crateSpy(int spyCount) {
        mCrateSpy = spyCount;
    }
    int crateSpy() {
        return mCrateSpy;
    }

    void doubleDmg(int dblCount) {
        mDoubleDmg = dblCount;
    }
    int doubleDmg() {
        return mDoubleDmg;
    }

    bool alternateControl() {
        return mAlternateControl;
    }

    private void placeMembers() {
        foreach (TeamMember m; mMembers) {
            m.place();
        }
    }

    //wraps around, if w==null, return first element, if any
    private TeamMember doFindNext(TeamMember w) {
        return arrayFindNext(mMembers, w);
    }

    TeamMember findNext(TeamMember w, bool must_be_alive = false) {
        return arrayFindNextPred(mMembers, w,
            (TeamMember t) {
                return !must_be_alive || t.alive;
            }
        );
    }

    ///activate a member for playing
    ///only for a member, not the team, use setActive for team
    void current(TeamMember cur) {
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
    TeamMember current() {
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
    TeamMember nextActive() {
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

    int opApply(int delegate(inout TeamMember member) del) {
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
            doSetPoint(currentTarget.currentPos);
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
            case PointMode.targetTracking:
                //find sprite closest to where
                parent.engine.physicworld.objectsAtPred(where, 10,
                    (PhysicObject obj) {
                        currentTarget.sprite = cast(GObjectSprite)obj.backlink;
                        return false;
                    }, (PhysicObject obj) {
                        return !!cast(GObjectSprite)obj.backlink;
                    });
                //fall-through
            case PointMode.target:
                //X animation
                setIndicator(color.pointed, currentTarget.currentPos);
                break;
            case PointMode.instant, PointMode.instantFree:
                //click effect
                parent.engine.animationEffect(color.click,
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
    private void setIndicator(Animation ani, Vector2f pos = Vector2f.init) {
        //only one cross indicator
        if (mCurrentTargetInd) {
            mCurrentTargetInd.removeThis();
            mCurrentTargetInd = null;
        }
        if (!ani)
            return;
        mCurrentTargetInd = new Animator(parent.engine.gameTime);
        mCurrentTargetInd.pos = toVector2i(pos) ;
        mCurrentTargetInd.setAnimation(ani);
        mCurrentTargetInd.zorder = GameZOrder.Crosshair; //this ok?
        parent.engine.scene.add(mCurrentTargetInd);
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
            if (targetIsSet && currentTarget.sprite) {
                //worm tracking
                mCurrentTargetInd.pos = toVector2i(currentTarget.currentPos);
            }
            //unused?
            //if (mCurrentTargetInd.readyflag()) {
            //    setIndicator(null);
            //}
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

    bool needUpdateHealth() {
        foreach (m; mMembers) {
            if (m.needUpdateHealth())
                return true;
        }
        return false;
    }

    void addWeapon(WeaponClass w, int quantity = 1) {
        weapons.addWeapon(w, quantity);
        parent.updateWeaponStats(null);
    }

    void skipTurn() {
        if (!mCurrent || !mActive)
            return;
        parent.events.onTeamEvent(TeamEvent.skipTurn, this);
        current = null;
    }

    void surrenderTeam() {
        parent.events.onTeamEvent(TeamEvent.surrender, this);
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
class TeamMember : WormController {
    Team mTeam;
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

    this(char[] a_name, Team a_team) {
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

    bool needUpdateHealth() {
        return mCurrentHealth != health();
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

    //xxx: probably replace by something better

    Sequence getGraphic() {
        return sprite ? sprite.graphic : null;
    }

    Sequence getControlledGraphic() {
        auto spr = sprite;
        if (mControlStack.length > 0)
            spr = mControlStack[$-1].getSprite();
        return spr ? spr.graphic : null;
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
        mEngine.queuePlaceOnLandscape(mWorm);
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
    //apparently amount of lost healthpoints since last activation
    //tolerance: positive number of health points, whose loss can be tolerated
    bool lifeLost(int tolerance = 0) {
        return health() + tolerance < lastKnownLifepower;
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
        mTeam.parent.events.onWormEvent(event, this);
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
        mTeam.parent.events.onSelectWeapon(this, selected);
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
                wormAction();
            }
            return;
        } else if (mWorm.firedWeapon(false) is wc) {
            if (keyDown)
                doFireDown(true);
            else
                doFireUp();
        } else {
            selectWeaponByClass(wc);
        }
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

    WeaponTarget getTarget() {
        return mTeam.currentTarget;
    }

    void reduceAmmo(Shooter sh) {
        WeaponItem wi = mTeam.weapons.byId(sh.weapon);
        assert(!!wi);
        wi.decrease();
        mTeam.parent.updateWeaponStats(this);
        if (!wi.canUse)
            //weapon ran out of ammo
            sh.interruptFiring(true);
        updateWeapon();
        //xxx select next weapon when current is empty... oh sigh
        //xxx also, select current weapon if we still have one, but weapon is
        //    undrawn! (???)
    }

    void firedWeapon(Shooter sh, bool refire) {
        assert(!!sh);
        mTeam.parent.events.onFireWeapon(sh.weapon, refire);
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
            mTeam.parent.events.onWormEvent(deathcause, this);
            if (deathcause == WormEvent.wormDrown) {
                //now it'd be nice if the clientengine could simply catch those
                //  events, but instead I do this hack (also: need pos and lost)
                Vector2i pos = toVector2i(mWorm.physics.pos);
                int lost = mCurrentHealth - health();
                mEngine.callbacks.memberDrown(this, lost, pos);
            }
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
        //stack gets cleared if the worm becomes inactive
        if (mControlStack.length == 0)
            return;
        if (mControlStack.length > 1 && c is mControlStack[$-1]) {
            //if removing the top object, transfer current movement to next
            c.move(Vector2f(0));
            mControlStack[$-2].move(mLastMoveVector);
        }
        //c does not have to be at the top of mControlStack
        arrayRemove(mControlStack, c);
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
            mTeam.parent.events.onWormEvent(WormEvent.wormStartDie, this);
            mWorm.finallyDie();
            assert(mWorm.isDelayedDying() || mWorm.isDead());
            return true;
        } else if (mWorm.isDelayedDying()) {
            //suiciding
            return true;
        }
        return false;
    }

    Team serverTeam() {
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
    this (GameEngine aengine, ConfigNode config, bool crateSet = false) {
        this(aengine);
        foreach (ConfigNode node; config.getSubNode("weapon_list")) {
            try {
                auto weapon = new WeaponItem(this, node);
                if (crateSet) {
                    //only drop weapons that are not infinite already,
                    //  and that can be used in the current world
                    if (!weapon.infinite && weapon.weapon.canUse())
                        crateList ~= weapon.weapon;
                } else {
                    weapons[weapon.weapon] = weapon;
                }
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
        assert(crateList.length == 0, "WeaponSet.addSet not for crate set");
        //add weapons
        foreach (WeaponClass key, WeaponItem value; other.weapons) {
            if (!(key in weapons))
                weapons[key] = new WeaponItem(this);
            auto wi = *(key in weapons);
            wi.addFromItem(value);
        }
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
            mQuantity = config.getCurValue!(int)();
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
class GameController {
    private {
        GameEngine mEngine;
        static LogStruct!("game.controller") log;

        Team[] mTeams;

        TeamMember[GameObject] mGameObjectToMember;

        //xxx for loading only
        ConfigNode[char[]] mWeaponSets;
        WeaponSet mCrateSet;

        bool mIsAnythingGoingOn; // (= hack)

        Gamemode mGamemode;
        char[] mGamemodeId;

        CrateSprite mLastCrate;  //just to drop it on spacebar
        bool mGameEnded;

        //Medkit, medkit+tool, medkit+tool+unrigged weapon
        //  (rest is rigged weapon)
        const cCrateProbs = [0.20f, 0.40f, 0.95f];
        //list of tool crates that can drop
        char[][] mActiveCrateTools;
        int[TeamTheme.cTeamColors.length] mTeamColorCache;

        GamePlugin[char[]] mPluginLookup;
        GamePlugin[] mPlugins;
        //xxx this should be configurable
        const char[][] cLoadPlugins = ["messages", "statistics", "persistence"];
    }

    ControllerEvents events;

    //when a worm collects a tool from a crate
    ChainDelegate!(TeamMember, CollectableTool) collectTool;

    this(GameEngine engine, GameConfig config) {
        mEngine = engine;
        mEngine.setController(this);

        //those work for all gamemodes
        addCrateTool("cratespy");
        addCrateTool("doubledamage");

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

        foreach (pid; cLoadPlugins) {
            //only load once
            if (!(pid in mPluginLookup)) {
                mPlugins ~= GamePluginFactory.instantiate(pid, engine);
                mPluginLookup[pid] = mPlugins[$-1];
            }
        }

        mEngine.finishPlace();

        collectTool ~= &doCollectTool;
    }

    this (ReflectCtor c) {
        Types t = c.types();
        t.registerMethod(this, &doCollectTool, "doCollectTool");
    }

    //--- start GameLogicPublic

    ///all participating teams (even dead ones)
    Team[] getTeams() {
        return mTeams;
    }

    char[] gamemode() {
        return mGamemodeId;
    }

    ///True if game has ended
    bool gameEnded() {
        return mGamemode.ended;
    }

    ///Status of selected gamemode (may contain timing, scores or whatever)
    Object gamemodeStatus() {
        return mGamemode.getStatus;
    }

    ///Request interface to a plugin; returns null if the plugin is not loaded
    Object getPlugin(char[] id) {
        return aaIfIn(mPluginLookup, id);
    }

    //--- end GameLogicPublic

    void addCrateTool(char[] id) {
        assert(arraySearch(mActiveCrateTools, id) < 0);
        mActiveCrateTools ~= id;
    }

    void updateWeaponStats(TeamMember m) {
        changeWeaponList(m ? m.team : null);
    }

    private void changeWeaponList(Team t) {
        engine.callbacks.weaponsChanged(t);
    }

    GameEngine engine() {
        return mEngine;
    }

    bool isIdle() {
        foreach (t; mTeams) {
            if (!t.isIdle())
                return false;
        }
        return true;
    }

    void startGame() {
        assert(!mIsAnythingGoingOn);
        mIsAnythingGoingOn = true;
        //nothing happening? start a round

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
                if (!mLastCrate.activity) mLastCrate = null;
            }

            if (mGamemode.ended() && !mGameEnded) {
                mGameEnded = true;

                events.onGameEnded();

                //increase total round count
                engine.persistentState.setValue("round_counter",
                    currentRound + 1);

                debug {
                    saveConfig(engine.persistentState,
                        "persistence_debug.conf");
                }
            }
        }
    }

    //index of currently running game round (zero-based)
    //note: even during onGameEnded event, still returns the current index
    int currentRound() {
        return engine.persistentState.getValue("round_counter", 0);
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

    bool needUpdateHealth() {
        foreach (t; mTeams) {
            if (t.needUpdateHealth())
                return true;
        }
        return false;
    }

    Team[] teams() {
        return mTeams;
    }

    //this function now is no longer special, can use t.setActive directly
    void activateTeam(Team t, bool active = true) {
        t.setActive(active);
    }

    void deactivateAll() {
        foreach (t; mTeams) {
            activateTeam(t, false);
        }
    }

    //actually still stupid debugging code
    private void spawnWorm(Vector2i pos) {
        //now stupid debug code in another way
        auto w = mEngine.createSprite("worm");
        w.activate(toVector2f(pos));
    }

    //config = the "teams" node, i.e. from data/data/teams.conf
    private void loadTeams(ConfigNode config) {
        mTeams = null;
        foreach (ConfigNode sub; config) {
            addTeam(sub);
        }
        placeWorms();
    }

    //config = the "teams" node, i.e. from data/data/teams.conf
    private void addTeam(ConfigNode config) {
        auto team = new Team(config, this);
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

    WeaponSet initWeaponSet(char[] id, bool forCrate = false) {
        ConfigNode ws;
        if (id in mWeaponSets)
            ws = mWeaponSets[id];
        else
            ws = mWeaponSets["default"];
        if (!ws)
            throw new Exception("Weapon set " ~ id ~ " not found.");
        return new WeaponSet(mEngine, ws, forCrate);
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
        mCrateSet = initWeaponSet("crate_set", true);
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
                    //try {
                        mEngine.queuePlaceOnLandscape(
                            mEngine.createSprite(sub["type"]));
                    /*} catch {
                        log("Warning: Placing {} objects failed", sub["type"]);
                        continue;
                    }*/
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
    void addMemberGameObject(TeamMember member, GameObject go) {
        //NOTE: the GameObject stays in this AA for forever
        //  in some cases, it could be released again (i.e. after a new round
        //  was started)
        assert(!go.createdBy, "fix memberFromGameObject and remove this");
        mGameObjectToMember[go] = member;
    }

    TeamMember memberFromGameObject(GameObject go, bool transitive) {
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
        events.onDamage(cause, victim, damage, wclass);
    }

    void reportDemolition(int pixelCount, GameObject cause) {
        assert(!!cause);
        events.onDemolition(pixelCount, cause);
    }

    Collectable[] fillCrate() {
        Collectable[] ret;
        float r = engine.rnd.nextDouble2();
        if (r < cCrateProbs[0]) {
            //medkit
            ret ~= new CollectableMedkit(50);
        } else if (r < cCrateProbs[1]) {
            //tool
            ret ~= CrateToolFactory.instantiate(
                mActiveCrateTools[engine.rnd.next($)]);
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
        if (!engine.placeObjectRandom(10, 25, from, to)) {
            log("couldn't find a safe drop-position");
            return false;
        }

        GObjectSprite s = engine.createSprite("crate");
        CrateSprite crate = cast(CrateSprite)s;
        assert(!!crate);
        //put stuffies into it
        crate.stuffies = fillCrate();
        //actually start it
        crate.activate(from);
        mLastCrate = crate;
        if (!silent) {
            events.onCrateDrop(crate.crateType);
        }
        log("drop {} -> {}", from, to);
        return true;
    }

    void instantDropCrate() {
        if (mLastCrate)
            mLastCrate.unParachute();
    }

    private bool doCollectTool(TeamMember collector, CollectableTool tool)
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
        events.onSuddenDeath();
    }
}
