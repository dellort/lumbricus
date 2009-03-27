module game.controller;

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
import game.gamemodes.base;
import physics.world;
import utils.vector2;
import utils.configfile;
import utils.log;
import utils.time;
import utils.misc;
import utils.array;
import utils.queue;
import utils.reflection;

import math = tango.math.Math;


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
    }

    //node = the node describing a single team
    this(ConfigNode node, GameController parent) {
        this.parent = parent;
        mName = node.name;
        //xxx: error handling (when team-theme not found)
        teamColor = parent.engine.gfx.teamThemes[node.getStringValue("color",
            "blue")];
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
    }

    this (ReflectCtor c) {
    }

    // --- start Team

    char[] name() {
        return mName;
    }

    TeamTheme color() {
        return teamColor;
    }

    //if there's any alive worm
    bool alive() {
        return findNext(null, true) !is null;
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
            nitem.type = parent.engine.wc2wh(item.weapon);
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

    // --- end Team

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
            setOnHold(false);
            if (!activateNextInRow()) {
                //no worm could be activated (i.e. all dead)
                mActive = false;
                return;
            }
            parent.messageAdd("msgwormstartmove", [mCurrent.name]);
            forcedFinish = false;
        } else {
            //deactivating
            current = null;
            setPointMode(PointMode.none);
            setOnHold(false);
            mActive = act;
        }
    }

    ///select the worm to play when team becomes active
    bool activateNextInRow() {
        assert(mCurrent is null);
        assert(mActive);
        //this will activate the worm
        auto next = findNext(mLastActive, true);
        current = next;
        //current may change by user input, mLastActive will not
        mLastActive = next;
        if (!next)
            return false;
        return true;
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
        targetIsSet = false;
        setIndicator(null);
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

        AnimationGraphic t = parent.engine.graphics.createAnimation();

        switch(mPointMode) {
            case PointMode.target:
                t.setAnimation(color.pointed.get);
                break;
            case PointMode.instant, PointMode.instantFree:
                t.setAnimation(color.click.get);
                break;
            default:
                assert(false);
        }

        t.update(toVector2i(where));

        setIndicator(t);

        if (mPointMode == PointMode.instant
            || mPointMode == PointMode.instantFree)
        {
            //instant mode -> fire and forget
            current.doFireDown(true);
            current.doFireUp();
            targetIsSet = false;
        }
    }
    private void setIndicator(AnimationGraphic ind) {
        //only one cross indicator
        if (mCurrentTargetInd) {
            mCurrentTargetInd.remove();
        }
        mCurrentTargetInd = ind;
    }

    //xxx integrate (unused yet)
    void applyDoubleTime() {
        //parent.mRoundRemaining *= 2;
    }
    void dieNow() {
        mCurrent.worm.physics.applyDamage(100000, cDamageCauseDeath);
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
    //round controller may use this to wait for the next round
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
        //xxx checking all members every frame, too expensive?
        foreach (m; mMembers) {
            if (!m.mWorm)
                continue;
            //check if a worm is really dead (i.e. "gone"), like after drowning,
            //or when finished blowing himself up
            if (m.mWorm.physics.dead) {
                if (m.mWorm.hasDrowned()) {
                    //death by drowning
                    //drowned worms go physics.dead when reaching the bottom
                    parent.messageAdd("msgdrown", [m.name]);
                    parent.events.onWorm(WormEvent.wormDrown, m);
                } else {
                    //death by exploding
                    //suiciding worms go physics.dead when done blowing up
                    parent.messageAdd("msgdie", [m.name]);
                    parent.events.onWorm(WormEvent.wormDie, m);
                }
                m.removeWorm();
                continue;
            }
        }
        if (!mActive)
            return;
        if (mCurrent)
            mCurrent.simulate();
    }

    bool checkDyingMembers() {
        foreach (m; mMembers) {
            auto worm = m.mWorm;
            //already dead -> boring
            if (!worm)
                continue;

            //3 possible states: healthy, unhealthy but not suiciding, suiciding
            if (worm.shouldDie() && !worm.isDelayedDying()) {
                //unhealthy, not suiciding
                worm.finallyDie();
                assert(worm.isDelayedDying() || worm.isDead());
                return true;
            } else if (worm.isDelayedDying()) {
                //suiciding
                return true;
            }
        }
        return false;
    }

    void youWinNow() {
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
}

//member of a team, currently (and maybe always) capsulates a WormSprite object
class ServerTeamMember : TeamMember, WormController {
    ServerTeam mTeam;
    char[] mName = "unnamed worm";

    private {
        WeaponItem mCurrentWeapon;
        bool mActive;
        Time mLastAction;
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
        //take control over dying, so we can let them die on round end
        mWorm.delayedDeath = true;
        mWorm.gravestone = mTeam.gravestone;
        mWorm.teamColor = mTeam.color;
        //set feedback interface to this class
        mWorm.wcontrol = this;
        //let Controller place the worm
        mTeam.parent.placeOnLandscape(mWorm);
    }

    //returns if 0 points, i.e. returns true even if worm didn't commit yet
    bool dead() {
        return !mWorm || mWorm.isDead();
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

    void setActive(bool act) {
        if (mActive == act)
            return;
        if (act) {
            //member is being activated
            mActive = act;
            mWormAction = false;
            mLastAction = timeSecs(-40); //xxx not kosher
            mWeaponUsed = false;
            mLimitedMode = false;
            lastKnownLifepower = health;
            //select last used weapon, select default if none
            if (!mCurrentWeapon)
                mCurrentWeapon = mTeam.defaultWeapon;
            selectWeapon(mCurrentWeapon);
            mTeam.parent.events.onWorm(WormEvent.wormActivate, this);
        } else {
            //being deactivated
            move(Vector2f(0));
            mLastAction = Time.Null;
            mWormAction = false;
            if (alive) {
                mWorm.activateJetpack(false);
            }
            mWorm.weapon = null;
            //stop all action when round ends
            mWorm.forceAbort();
            mFireDown = false;
            mActive = act;
            mTeam.parent.events.onWorm(WormEvent.wormDeactivate, this);
        }
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
        //try alternate fire, if not possible jump instead
        if (!doAlternateFire())
            mWorm.jump(j);
        wormAction();
    }

    WalkState walkState() {
        if (!isControllable)
            return WalkState.noMovement;

        if (mWorm.jetpackActivated())
            return WalkState.jetpackFly;

        //no other possibilities currently
        return WalkState.walk;
    }

    WeaponHandle getCurrentWeapon() {
        return currentWeapon ? mEngine.wc2wh(currentWeapon.weapon) : null;
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
        return mWorm.displayWeaponIcon;
    }

    void selectWeapon(WeaponItem weapon) {
        if (!isControllable || mLimitedMode)
            return;
        if (weapon !is mCurrentWeapon) {
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
        /*if (selected) {
            messageAdd(_("msgselweapon", _("weapons." ~ selected.name)));
        } else {
            messageAdd(_("msgnoweapon"));
        }*/
        if (selected) {
            mTeam.setPointMode(selected.fireMode.point);
        } else {
            mTeam.setPointMode(PointMode.none);
        }
        mWorm.weapon = selected;
    }

    void doSetTimer(Time t) {
        if (!isControllable || mLimitedMode)
            return;

        mWorm.setWeaponTimer(t);
    }

    void doFireDown(bool forceSelected = false) {
        if (!isControllable)
            return;

        bool success = false;
        if (mWorm.allowAlternate && !forceSelected && !mTeam.alternateControl) {
            //non-alternate (worms-like) control -> spacebar disables
            //background weapon if possible (like jetpack)
            success = mWorm.fireAlternate();
            wormAction();
        } else {
            success = worm.fire(false, forceSelected);
        }
        //don't forget a keypress that had no effect
        mFireDown = !success;
        if (success)
            wormAction();
    }

    void doFireUp() {
        mFireDown = false;
        if (!isControllable)
            return;

        if (worm.fire(true)) {
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
            if (mWorm.allowFireSecondary()) {
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
        mTeam.parent.events.onFireWeapon(sh.weapon, refire);
    }

    void doneFiring(Shooter sh) {
        if (!sh.weapon.dontEndRound)
            mWeaponUsed = true;
    }

    // <-- End WormController

    //has the worm fired something since he became active?
    bool weaponUsed() {
        return mWeaponUsed;
    }

    Time lastAction() {
        return mLastAction;
    }

    //called if any action is issued, i.e. key pressed to control worm
    //or if it was moved by sth. else
    void wormAction(bool fromkeys = true) {
        if (fromkeys) {
            mWormAction = true;
            mLastAction = mTeam.parent.engine.gameTime.current;
        }
    }
    //has the worm done anything since activation?
    bool actionPerformed() {
        return mWormAction;
    }

    private void move(Vector2f vec) {
        if (!alive)
            return;
        if (!isControllable || vec == mLastMoveVector) {
            mWorm.move(Vector2f(0));
            return;
        }

        mLastMoveVector = vec;
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
        if (!mActive)
            return;

        //check if fire button is being held down, waiting for right state
        if (mFireDown)
            doFireDown();
    }

    void youWinNow() {
        if (mWorm)
            mWorm.setState(mWorm.findState("win"));
    }

    bool delayedAction() {
        //check for any activity that might justify control beyond end-of-round
        //e.g. still charging a weapon, still firing a multi-shot weapon
        return worm.delayedAction;
    }

    void forceAbort() {
        //forced stop of all action (like when being damaged)
        mWorm.forceAbort();
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
    char[] name;

    //config = item from "weapon_sets"
    this (GameEngine aengine, ConfigNode config) {
        engine = aengine;
        name = config.name;
        foreach (ConfigNode node; config.getSubNode("weapon_list")) {
            try {
                auto weapon = new WeaponItem(this, node);
                weapons[weapon.weapon] = weapon;
            } catch (Exception e) {
                registerLog("game.controller")
                    ("Error in weapon set '"~name~"': "~e.msg);
            }
        }
    }

    this (ReflectCtor c) {
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
        return !mWeapon.isAirstrike || mEngine.level.airstrikeAllow;
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
        //xxx error handling
        auto w = config["type"];
        mWeapon = mEngine.findWeaponClass(w);
        if (config.valueIs("quantity", "inf")) {
            mInfiniteQuantity = true;
        } else {
            mQuantity = config.getIntValue("quantity", 0);
        }
    }

    this (ReflectCtor c) {
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
        Team[] mTeams2;
        Team[] mActiveTeams;

        ServerTeamMember[GameObject] mGameObjectToMember;

        //xxx for loading only
        ConfigNode[char[]] mWeaponSets;
        private WeaponClass[] mCrateList;

        bool mIsAnythingGoingOn; // (= hack)

        struct Message {
            char[] id;
            char[][] args;
        }
        Queue!(Message) mMessages; //GUI messages which are sent to the clients
        Message mLastMessage;
        int mMessageChangeCounter;
        //time between messages, how they are actually displayed
        //is up to the gui
        const cMessageTime = timeSecs(1.5f);
        Time mLastMsgTime;

        int mWeaponListChangeCounter;

        Gamemode mGamemode;
        char[] mGamemodeId;

        CrateSprite mLastCrate;  //just to drop it on spacebar
        bool mGameEnded;

        EventAggregator mEvents;
    }

    this(GameEngine engine, GameConfig config) {
        mEngine = engine;

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

        mEvents = new EventAggregator(this);

        mMessages = new Queue!(Message);
        mLastMsgTime = -cMessageTime;
        //only valid while loading
        mWeaponSets = null;

        mEngine.finishPlace();
    }

    this (ReflectCtor c) {
        c.types().registerClass!(typeof(mMessages));
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

    WeaponHandle[] weaponList() {
        WeaponHandle[] res;
        foreach (c; mEngine.weaponList()) {
            res ~= engine.wc2wh(c);
        }
        return res;
    }

    int getMessageChangeCounter() {
        return mMessageChangeCounter;
    }

    void getLastMessage(out char[] msgid, out char[][] msg, out uint rnd) {
        msgid = mLastMessage.id;
        msg = mLastMessage.args;
        rnd = engine.rnd.next;
    }

    int getWeaponListChangeCounter() {
        return mWeaponListChangeCounter;
    }

    Team[] getActiveTeams() {
        return mActiveTeams;
    }

    //--- end GameLogicPublic

    void updateWeaponStats(TeamMember m) {
        changeWeaponList(m ? m.team : null);
    }

    private void changeWeaponList(Team t) {
        mWeaponListChangeCounter++;
    }

    GameEngine engine() {
        return mEngine;
    }

    void messageAdd(char[] msg, char[][] args = null) {
        mMessages.push(Message(msg, args));
    }

    private void changeMessageStatus(Message msg) {
        mMessageChangeCounter++;
        mLastMessage = msg;
    }

    bool messageIsIdle() {
        return mMessages.empty;
    }

    void startGame() {
        mIsAnythingGoingOn = true;
        //nothing happening? start a round
        messageAdd("msggamestart", null);

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
            mGamemode.simulate();

            foreach (t; mTeams)
                t.simulate();

            //process messages
            if (mLastMsgTime < mEngine.gameTime.current && !mMessages.empty()) {
                //show one
                Message msg = mMessages.pop();
                //note that messages will get lost if callback is not set,
                //this is intended
                changeMessageStatus(msg);
                mLastMsgTime = mEngine.gameTime.current + cMessageTime;
            }

            if (mLastCrate) {
                if (!mLastCrate.active) mLastCrate = null;
            }

            if (mGamemode.ended() && !mGameEnded) {
                mGameEnded = true;
                mEvents.output();
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

    void activateTeam(ServerTeam t, bool active = true) {
        if (!t)
            return;
        if (t.active == active)
            return;
        t.setActive(active);
        if (active) {
            //???
            assert(mActiveTeams.length == 0);
            mActiveTeams ~= t;
        } else {
            //should not fail
            arrayRemoveUnordered(mActiveTeams, t);
        }

        //xxx: not sure
        changeWeaponList(t);
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
        ConfigNode ws = mWeaponSets[id];
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

    //"weapon_sets" in teams.conf
    private void loadWeaponSets(ConfigNode config) {
        foreach (ConfigNode item; config) {
            mWeaponSets[item.name] = item;
        }
        char[][] crateList = config.getValueArray("crate_list", [""]);
        foreach (crateItem; crateList) {
            try {
                mCrateList ~= engine.findWeaponClass(crateItem);
            } catch (Exception e) {
                log("Error in crate list: "~e.msg);
            }
        }
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
        events.onDamage(cause, victim, damage, wclass);
    }

    void reportDemolition(int pixelCount, GameObject cause) {
        assert(!!cause);
        events.onDemolition(pixelCount, cause);
    }

    //queue for placing anywhere on landscape
    //call engine.finishPlace() when done with all sprites
    void placeOnLandscape(GObjectSprite sprite, bool must_place = true) {
        mEngine.queuePlaceOnLandscape(sprite);
    }

    //choose a random weapon based on crate_list
    //returns null if none was found
    WeaponClass chooseRandomForCrate() {
        if (mCrateList.length > 0) {
            int r = engine.rnd.next(0, mCrateList.length);
            return mCrateList[r];
        } else {
            return null;
        }
    }

    bool dropCrate() {
        Vector2f from, to;
        float water = engine.waterOffset - 10;
        if (!engine.placeObjectRandom(water, 10, 25, from, to)) {
            log("couldn't find a safe drop-position");
            return false;
        }
        auto content = chooseRandomForCrate();
        if (content) {
            GObjectSprite s = engine.createSprite("crate");
            CrateSprite crate = cast(CrateSprite)s;
            assert(!!crate);
            //put stuffies into it
            crate.stuffies = [new CollectableWeapon(content, 1)];
            if (engine.rnd.next(0, 10) == 0) {
                //add a bomb to that :D
                crate.stuffies ~= new CollectableBomb();
            }
            //actually start it
            crate.setPos(from);
            crate.active = true;
            mLastCrate = crate;
            log("drop {} -> {}", from, to);
            return true;
        } else {
            log("failed to create crate contents");
        }
        return false;
    }

    void instantDropCrate() {
        if (mLastCrate)
            mLastCrate.unParachute();
    }

    EventAggregator events() {
        return mEvents;
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



enum WormEvent {
    wormDie,
    wormDrown,
    wormActivate,
    wormDeactivate,
}

class EventAggregator {
    private {
        static LogStruct!("gameevents") log;
        GameController mController;
    }

    this(GameController c) {
        mController = c;
    }
    this(ReflectCtor c) {
    }

    void onDamage(GameObject cause, GObjectSprite victim, float damage,
        WeaponClass wclass)
    {
        char[] wname = "unknown_weapon";
        if (wclass)
            wname = wclass.name;
        auto m1 = mController.memberFromGameObject(cause, true);
        auto m2 = mController.memberFromGameObject(victim, false);
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

    void onDemolition(int pixelCount, GameObject cause) {
        mPixelsDestroyed += pixelCount;
        //log("blasted {} pixels of land", pixelCount);
    }

    void onFireWeapon(WeaponClass wclass, bool refire = false) {
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

    void onWorm(WormEvent id, ServerTeamMember m) {
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

    void onCrate(ServerTeamMember m, Collectable[] stuffies) {
        log("{} collects crate: {}", m, stuffies);
        mCrateCount++;
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
