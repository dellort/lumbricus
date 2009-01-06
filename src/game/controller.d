module game.controller;
import game.game;
import game.gobject;
import game.worm;
import game.crate;
import game.sprite;
import game.weapon.types;
import game.weapon.weapon;
import game.gamepublic;
import physics.world;
import utils.vector2;
import utils.configfile;
import utils.log;
import utils.time;
import utils.misc;
import utils.array;
import utils.queue;
import utils.reflection;

import framework.i18n;

import str = std.string;
import math = std.math;

//nasty proxy to the currently active TeamMember
//this is per client (and not per-team)
class ServerMemberControl : TeamMemberControl {
    private {
        //xxx the controller needs to be replaced by sth. "better" hahaha
        GameController ctl;

        this(GameController c) {
            ctl = c;
        }
    }

    this (ReflectCtor c) {
    }
    this () {
    }

    private ServerTeamMember activemember() {
        if (ctl.mCurrentTeam) {
            return ctl.mCurrentTeam.mCurrent;
        }
        return null;
    }

    TeamMember getActiveMember() {
        return activemember();
    }

    Team getActiveTeam() {
        return ctl.mCurrentTeam;
    }

    Time currentLastAction() {
        auto c = activemember;
        if (c) {
            return c.lastAction;
        }
        return timeSecs(0);
    }

    void selectNextMember() {
        auto c = activemember;
        if (c) {
            c.mTeam.doChooseWorm();
        }
    }

    WalkState walkState() {
        auto m = activemember;
        if (m) {
            return m.walkState;
        }
        return WalkState.noMovement;
    }

    void jump(JumpMode mode) {
        auto m = activemember;
        if (m) {
            m.jump(mode);
        }
    }

    void setMovement(Vector2i dir) {
        auto m = activemember;
        if (m) {
            m.doMove(dir);
        }
    }

    WeaponMode weaponMode() {
        if (activemember) {
            //TODO
            return WeaponMode.full;
        }
        return WeaponMode.none;
    }

    void weaponDraw(WeaponHandle w) {
        auto m = activemember;
        if (m) {
            m.selectWeaponByClass(ctl.engine.wh2wc(w));
        }
    }

    WeaponHandle currentWeapon() {
        auto m = activemember;
        if (m) {
            return m.currentWeapon ?
                ctl.engine.wc2wh(m.currentWeapon.weapon) : null;
        }
        return null;
    }

    bool displayWeaponIcon() {
        auto m = activemember;
        if (m) {
            return m.displayWeaponIcon();
        }
        return false;
    }

    void weaponSetTimer(Time timer) {
        //TODO
    }

    void weaponSetTarget(Vector2i targetPos) {
        auto m = activemember;
        if (m && m.mTeam) {
            m.mTeam.doSetPoint(toVector2f(targetPos));
        }
    }

    void weaponFire(bool is_down) {
        auto m = activemember;
        if (m) {
            if (is_down)
                m.doFireDown();
            else
                m.doFireUp();
        }
    }
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
    bool allowSelect;   //can next worm be selected by user (tab)
    bool forcedFinish;

    private {
        ServerTeamMember[] mMembers;  //all members (will not change in-game)
        ServerTeamMember mCurrent;  //active worm that will receive user input
        ServerTeamMember mLastActive;  //worm that played last (to choose next)
        bool mActive;         //is this team playing?
        bool mOnHold;

        //if you can click anything, if true, also show that animation
        PointMode mPointMode;
        TargetIndicator mCurrentTargetInd;

        Vector2f movementVec = {0, 0};
        bool mAlternateControl;
    }

    //node = the node describing a single team
    this(ConfigNode node, GameController parent) {
        this.parent = parent;
        mName = node.getStringValue("name", mName);
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

    bool alive() {
        return isAlive(); //oops
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
        return arrayCastCopyImplicit!(TeamMember, ServerTeamMember)(mMembers);
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
                return !must_be_alive || t.isAlive;
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

    //if there's any alive worm
    bool isAlive() {
        return findNext(null, true) !is null;
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
    void setActive(bool act) {
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

    ///choose next in reaction to user keypress
    void doChooseWorm() {
        if (!mActive || !mCurrent || !allowSelect)
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

        targetIsSet = true;
        currentTarget = where;

        TargetIndicator t = parent.engine.graphics.createTargetIndicator(color,
            toVector2i(where), mPointMode);

        if (mPointMode == PointMode.target) {
            //targetting mode (homing) -> save point reference
            setIndicator(t);
        }
        if (mPointMode == PointMode.instant) {
            //instant mode -> fire and forget
            current.doFireDown(true);
            targetIsSet = false;
        }
    }
    private void setIndicator(TargetIndicator ind) {
        //only one cross indicator
        if (mCurrentTargetInd)
            mCurrentTargetInd.remove();
        mCurrentTargetInd = ind;
    }

    //xxx integrate (unused yet)
    void applyDoubleTime() {
        parent.mRoundRemaining *= 2;
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
            if (m.isAlive() && !m.isIdle())
                return false;
        }
        return true;
    }

    void simulate() {
        if (!mActive)
            return;
        if (mCurrent)
            mCurrent.simulate();
    }

    bool checkDyingMembers() {
        foreach (m; mMembers) {
            auto worm = m.mWorm;
            //already dead -> boring
            //also bail out here if worm drowned/is drowning
            if (!worm || worm.isReallyDead()) {
                m.removeWorm();
                continue;
            }

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
            mLastKnownPhysicHealth = cast(int)mWorm.physics.lifepower;
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

    bool alive() {
        //xxx this is fishy
        return isAlive;
    }

    int health() {
        //hack to display negative values
        //the thing is that a worm can be dead even if the physics report a
        //positive value - OTOH, we do want these negative values... HACK GO!
        //mLastKnownPhysicHealth is there because mWorm could disappear
        auto h = mWorm ? cast(int)mWorm.physics.lifepower : mLastKnownPhysicHealth;
        if (isAlive()) {
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

    bool isAlive() {
        //currently by havingwormspriteness... since dead worms haven't
        return (mWorm !is null) && !mWorm.isDead();
    }

    bool isControllable() {
        return mActive && isAlive() && mTeam.isControllable();
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
            lastKnownLifepower = health;
            //select last used weapon, select default if none
            if (!mCurrentWeapon)
                mCurrentWeapon = mTeam.defaultWeapon;
            selectWeapon(mCurrentWeapon);
        } else {
            //being deactivated
            move(Vector2f(0));
            mLastAction = timeMusecs(0);
            mWormAction = false;
            if (isAlive) {
                mWorm.activateJetpack(false);
            }
            mWorm.weapon = null;
            //stop all action when round ends
            mWorm.forceAbort();
            mFireDown = false;
            mActive = act;
        }
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
        if (!isControllable)
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
    void updateWeapon() {
        if (!mActive || !isAlive)
            return;

        WeaponClass selected;
        if (mCurrentWeapon) {
            if (!mCurrentWeapon.canUse()) {
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
            success = worm.fire();
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
        if (!isAlive)
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
                aengine.mLog("Error in weapon set '"~name~"': "~e.msg);
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
        public /+weewee+/ Log mLog;

        ServerTeam[] mTeams;
        ServerTeam mCurrentTeam;
        ServerTeam mLastTeam;

        ServerTeamMember[GameObject] mGameObjectToMember;

        //xxx for loading only
        ConfigNode[char[]] mWeaponSets;
        private WeaponClass[] mCrateList;

        Time mRoundRemaining, mPrepareRemaining, mWinRemaining, mCleanupWait;
        //time a round takes
        Time mTimePerRound;
        //extra time before round time to switch seats etc
        Time mHotseatSwitchTime;
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
        const cMessageTime = 1.5f;
        Time mLastMsgTime;

        int mWeaponListChangeCounter;

        RoundState mCurrentRoundState = RoundState.nextOnHold;

        ServerMemberControl control;
    }

    this(GameEngine engine, GameConfig config) {
        mEngine = engine;

        control = new ServerMemberControl(this);

        mLog = registerLog("gamecontroller");

        if (config.weapons) {
            loadWeaponSets(config.weapons);
        }
        if (config.teams) {
            loadTeams(config.teams);
        }
        if (config.levelobjects) {
            loadLevelObjects(config.levelobjects);
        }

        mTimePerRound = timeSecs(config.gamemode.getIntValue("roundtime",15));
        mHotseatSwitchTime = timeSecs(
            config.gamemode.getIntValue("hotseattime",5));

        mMessages = new Queue!(Message);
        mLastMsgTime = timeSecs(-cMessageTime);
        //only valid while loading
        mWeaponSets = null;
    }

    this (ReflectCtor c) {
        c.types().registerClass!(typeof(mMessages));
    }

    //--- start GameLogicPublic

    Team[] getTeams() {
        return arrayCastCopyImplicit!(Team, ServerTeam)(mTeams);
    }

    RoundState currentRoundState() {
        return mCurrentRoundState;
    }

    Time currentRoundTime() {
        return mRoundRemaining;
    }

    Time currentPrepareTime() {
        return mPrepareRemaining;
    }

    ///xxx: read comment for this in gamepublic.d
    TeamMemberControl getControl() {
        return control;
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

    void getLastMessage(out char[] msgid, out char[][] msg) {
        msgid = mLastMessage.id;
        msg = mLastMessage.args;
    }

    int getWeaponListChangeCounter() {
        return mWeaponListChangeCounter;
    }

    //--- end GameLogicPublic

    void updateClientRoundStateTime() {
    }

    void updateWeaponStats(TeamMember m) {
        changeWeaponList(m ? m.team : null);
    }

    private void changeWeaponList(Team t) {
        mWeaponListChangeCounter++;
    }

    GameEngine engine() {
        return mEngine;
    }

    private void messageAdd(char[] msg, char[][] args = null) {
        mMessages.push(Message(msg, args));
    }

    private void changeMessageStatus(Message msg) {
        mMessageChangeCounter++;
        mLastMessage = msg;
    }

    private bool messageIsIdle() {
        return mMessages.empty;
    }

    void startGame() {
        mIsAnythingGoingOn = true;
        //nothing happening? start a round
        messageAdd("msggamestart", null);

        deactivateAll();
    }

    void simulate() {
        Time diffT = mEngine.gameTime.difference;

        if (!mIsAnythingGoingOn) {
            startGame();
        } else {
            RoundState next = doState(diffT);
            if (next != mCurrentRoundState)
                transition(next);

            foreach (t; mTeams)
                t.simulate();

            //process messages
            if (mLastMsgTime < mEngine.gameTime.current && !mMessages.empty()) {
                //show one
                Message msg = mMessages.pop();
                //note that messages will get lost if callback is not set,
                //this is intended
                changeMessageStatus(msg);
                mLastMsgTime = mEngine.gameTime.current;
            }
        }


        updateClientRoundStateTime();
    }

    private void deactivateAll() {
        foreach (t; mTeams) {
            t.setActive(false);
        }
        mCurrentTeam = null;
        mLastTeam = null;
    }

    //return true if there are dying worms
    private bool checkDyingWorms() {
        foreach (t; mTeams) {
            //death is in no hurry, one worm a frame
            if (t.checkDyingMembers())
                return true;
        }
        return false;
    }

    //send clients new health values
    private void updateHealth() {
        foreach (t; mTeams) {
            t.updateHealth();
        }
    }

    private RoundState doState(Time deltaT) {
        switch (mCurrentRoundState) {
            case RoundState.prepare:
                mPrepareRemaining = mPrepareRemaining - deltaT;
                if (mCurrentTeam.teamAction())
                    //worm moved -> exit prepare phase
                    return RoundState.playing;
                if (mPrepareRemaining < timeMusecs(0))
                    return RoundState.playing;
                break;
            case RoundState.playing:
                mRoundRemaining = max(mRoundRemaining - deltaT, timeNull);
                if (!mCurrentTeam.current)
                    return RoundState.waitForSilence;
                if (mRoundRemaining <= timeMusecs(0))   //timeout
                {
                    //check if we need to wait because worm is performing
                    //a non-abortable action
                    if (!mCurrentTeam.current.delayedAction)
                        return RoundState.waitForSilence;
                }
                if (!mCurrentTeam.current.isAlive       //active worm dead
                    || mCurrentTeam.current.lifeLost)   //active worm damaged
                {
                    mCurrentTeam.current.forceAbort();
                    return RoundState.waitForSilence;
                }
                break;
            case RoundState.waitForSilence:
                if (!mEngine.checkForActivity) {
                    //hope the game stays inactive
                    return RoundState.cleaningUp;
                }
                break;
            case RoundState.cleaningUp:
                mRoundRemaining = timeSecs(0);
                mCleanupWait = max(mCleanupWait - deltaT, timeNull);
                //not yet
                if (mCleanupWait <= timeMusecs(0))
                    return checkDyingWorms()
                        ? RoundState.waitForSilence : RoundState.nextOnHold;
                break;
            case RoundState.nextOnHold:
                if (messageIsIdle() && objectsIdle())
                    return RoundState.prepare;
                break;
            case RoundState.winning:
                mWinRemaining -= deltaT;
                if (mWinRemaining < timeMusecs(0))
                    return RoundState.end;
                break;
            case RoundState.end:
                break;
        }
        return mCurrentRoundState;
    }

    private void transition(RoundState st) {
    again:
        assert(st != mCurrentRoundState);
        mLog("state transition %s -> %s", cast(int)mCurrentRoundState,
            cast(int)st);
        mCurrentRoundState = st;
        switch (st) {
            case RoundState.prepare:
                mRoundRemaining = mTimePerRound;
                mPrepareRemaining = mHotseatSwitchTime;

                //select next team/worm
                ServerTeam next = arrayFindNextPred(mTeams, mLastTeam,
                    (ServerTeam t) {
                        return t.isAlive();
                    }
                );
                currentTeam = null;

                //check if at least two teams are alive
                int aliveTeams;
                foreach (t; mTeams) {
                    aliveTeams += t.isAlive() ? 1 : 0;
                }

                assert((aliveTeams == 0) != !!next); //no teams, no next

                if (aliveTeams < 2) {
                    if (aliveTeams == 0) {
                        messageAdd("msgnowin");
                        st = RoundState.end;
                    } else {
                        next.youWinNow();
                        messageAdd("msgwin", [next.name]);
                        st = RoundState.winning;
                    }
                    //very sry
                    goto again;
                }

                mLastTeam = next;
                currentTeam = next;
                mLog("active: %s", next);

                break;
            case RoundState.playing:
                if (mCurrentTeam)
                    mCurrentTeam.setOnHold(false);
                mPrepareRemaining = timeMusecs(0);
                break;
            case RoundState.waitForSilence:
                //no control while blowing up worms
                if (mCurrentTeam)
                    mCurrentTeam.setOnHold(true);
                //if it's the round's end, also take control early enough
                currentTeam = null;
                break;
            case RoundState.cleaningUp:
                mCleanupWait = timeMsecs(400);
                updateHealth(); //hmmm
                //see doState()
                break;
            case RoundState.nextOnHold:
                currentTeam = null;
                messageAdd("msgnextround");
                mRoundRemaining = timeMusecs(0);
                break;
            case RoundState.winning:
                //how long winning animation is showed
                mWinRemaining = timeSecs(5);
                break;
            case RoundState.end:
                messageAdd("msggameend");
                currentTeam = null;
                break;
        }
    }

    void currentTeam(ServerTeam t) {
        if (mCurrentTeam is t)
            return;
        if (mCurrentTeam)
            mCurrentTeam.setActive(false);
        mCurrentTeam = t;
        if (mCurrentTeam)
            mCurrentTeam.setActive(true);
        //xxx: not sure
        changeWeaponList(mCurrentTeam);
    }
    ServerTeam currentTeam() {
        return mCurrentTeam;
    }

    bool objectsIdle() {
        foreach (t; mTeams) {
            if (!t.isIdle())
                return false;
        }
        return true;
    }

    public Team[] activeTeams() {
        Team[] res;
        foreach (t; mTeams) {
            if (t.isActive) {
                res ~= t;
            }
        }
        return res;
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
                engine.mLog("Error in crate list: "~e.msg);
            }
        }
    }

    //create and place worms when necessary
    private void placeWorms() {
        mLog("placing worms...");

        foreach (t; mTeams) {
            t.placeMembers();
        }

        mLog("placing worms done.");
    }

    private void loadLevelObjects(ConfigNode objs) {
        mLog("placing level objects");
        foreach (ConfigNode sub; objs) {
            auto mode = sub.getStringValue("mode", "unknown");
            if (mode == "random") {
                auto cnt = sub.getIntValue("count");
                mLog("count %s type %s", cnt, sub["type"]);
                for (int n = 0; n < cnt; n++) {
                    try {
                        placeOnLandscape(mEngine.createSprite(sub["type"]));
                    } catch {
                        mLog("Warning: Placing %s objects failed", sub["type"]);
                        continue;
                    }
                }
            } else {
                mLog("warning: unknown placing mode: '%s'", sub["mode"]);
            }
        }
        mLog("done placing level objects");
    }

    void selectWeapon(WeaponClass weaponId) {
        if (mCurrentTeam)
            mCurrentTeam.selectWeapon(weaponId);
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

    void reportViolence(GameObject cause, GameObject victim, float damage) {
        assert(!!cause && !!victim);
        auto m1 = memberFromGameObject(cause, true);
        auto m2 = memberFromGameObject(victim, false);
        if (!m1 || !m2) {
            mLog("unknown damage %s/%s %s/%s %s", cause, victim, m1, m2, damage);
        } else {
            mLog("worm %s injured %s by %s", m1, m2, damage);
        }
    }

    //place anywhere on landscape
    //returns success
    //  must_place = if true, this must not return false
    bool placeOnLandscape(GObjectSprite sprite, bool must_place = true) {
        Vector2f npos, tmp;
        auto water_y = mEngine.waterOffset;
        //first 10: minimum distance from water
        //second 10: retry count
        if (!mEngine.placeObject(water_y-10, 10, tmp, npos,
            sprite.physics.posp.radius))
        {
            //placement unsuccessful
            //the original game blows a hole into the level at a random
            //position, and then places a small bridge for the worm
            //but for now... just barf and complain
            //auto level = mEngine.gamelevel;
            //npos = toVector2f(level.offset + level.size / 2);
            npos = toVector2f(mEngine.worldSize)/2; //yyy
            mLog("couldn't place '%s'!", sprite);
            if (!must_place)
                return false;
        }
        mLog("placed '%s' at %s", sprite, npos);
        sprite.setPos(npos);
        sprite.active = true;
        return true;
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

    void dropCrate() {
        Vector2f from, to;
        float water = engine.waterOffset - 10;
        if (!engine.placeObject(water, 10, from, to, 5)) {
            mLog("couldn't find a safe drop-position");
            return;
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
            mLog("drop %s -> %s", from, to);
        } else {
            mLog("failed to create crate contents");
        }
    }
}
