module game.controller;
import game.game;
import game.worm;
import game.sprite;
import game.weapon;
import game.gamepublic;
import utils.vector2;
import utils.configfile;
import utils.log;
import utils.time;
import utils.misc;
import utils.array;
import utils.queue;
import common.common;

import framework.i18n;

import str = std.string;
import math = std.math;

//nasty proxy to the currently active TeamMember
//this is per client (and not per-team)
class ServerMemberControl : TeamMemberControl {
    private {
        TeamMemberControlCallback mBack;
        //xxx the controller needs to be replaced by sth. "better" hahaha
        GameController ctl;

        this(GameController c) {
            ctl = c;
        }
    }

    void setTeamMemberControlCallback(TeamMemberControlCallback tmcc) {
        //refuse overwriting :)
        assert(mBack is null);

        mBack = tmcc;
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

    void jetpack(bool active) {
        auto m = activemember;
        if (m) {
            m.setJetpack(active);
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

    void weaponDraw(WeaponClass w) {
        auto m = activemember;
        if (m) {
            m.selectWeapon(w);
        }
    }

    WeaponClass currentWeapon() {
        auto m = activemember;
        if (m) {
            return m.currentWeapon.weapon;
        }
    }

    void weaponSetTimer(Time timer) {
        //TODO
    }

    void weaponSetTarget(Vector2i targetPos) {
        auto m = activemember;
        if (m) {
            m.mTeam.doSetPoint(toVector2f(targetPos));
        }
    }

    void weaponFire(float strength) {
        auto m = activemember;
        if (m) {
            //TODO: strength parameter
            m.doFire();
        }
    }

    //back-proxy *g*
    void memberChanged() {
        if (mBack) {
            mBack.controlMemberChanged();
        }
    }
    void walkStateChanged() {
        if (mBack) {
            mBack.controlWalkStateChanged();
        }
    }
    void weaponModeChanged() {
        if (mBack) {
            mBack.controlWeaponModeChanged();
        }
    }
}

class ServerTeam : Team {
    char[] mName = "unnamed team";
    //this values indices into cTeamColors and the gravestone animations
    int teamColor, graveStone;
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
        bool mAllowSetPoint;

        Vector2f movementVec = {0, 0};
    }

    //node = the node describing a single team
    this(ConfigNode node, GameController parent) {
        this.parent = parent;
        mName = node.getStringValue("name", mName);
        teamColor = node.selectValueFrom("color", cTeamColors, 0);
        initialPoints = node.getIntValue("power", 100);
        graveStone = node.getIntValue("grave", 0);
        //the worms currently aren't loaded by theirselves...
        foreach (char[] name, char[] value; node.getSubNode("member_names")) {
            auto worm = new ServerTeamMember(value, this);
            mMembers ~= worm;
        }
        //xxx error handling
        weapons = parent.initWeaponSet(node["weapon_set"]);
        //yyy defaultWeapon = weapons.byId(node["default_weapon"]);
    }

    // --- start Team

    char[] name() {
        return mName;
    }

    TeamColor color() {
        return teamColor;
    }

    bool alive() {
        //xxx?
        assert(false);
    }

    bool active() {
        return mActive;
    }

    int totalHealth() {
        int h;
        foreach (t; mMembers) {
            h += t.health;
        }
        return h;
    }

    WeaponList getWeapons() {
        //convert WeaponSet to WeaponList
        WeaponItem[] items = weapons.weapons.values;
        WeaponList list;
        list.length = items.length;
        for (int n = 0; n < list.length; n++) {
            list[n].type = items[n].weapon;
            list[n].quantity = items[n].infinite ?
                WeaponListItem.QUANTITY_INFINITE : items[n].count;
        }
        return list;
    }

    TeamMember[] getMembers() {
        return arrayCastCopyImplicit!(TeamMember, ServerTeamMember)(mMembers);
    }

    // --- end Team

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
            parent.messageAdd(_("msgwormstartmove", mCurrent.name));
            forcedFinish = false;
        } else {
            //deactivating
            current = null;
            allowSetPoint(false);
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

    void allowSetPoint(bool set) {
        if (mAllowSetPoint == set)
            return;
        mAllowSetPoint = set;
        targetIsSet = false;
    }
    void doSetPoint(Vector2f where) {
        if (!mAllowSetPoint || !isControllable)
            return;

        targetIsSet = true;
        currentTarget = where;
    }

    //xxx integrate (unused yet)
    void applyDoubleTime() {
        parent.mRoundRemaining *= 2;
    }
    void dieNow() {
        mCurrent.worm.physics.applyDamage(100000);
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
                m.mWorm = null;
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
}

//member of a team, currently (and maybe always) capsulates a WormSprite object
class ServerTeamMember : TeamMember {
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
    }

    this(char[] a_name, ServerTeam a_team) {
        this.mName = a_name;
        this.mTeam = a_team;
        mEngine = mTeam.parent.engine;
    }

    // --- start TeamMember

    char[] name() {
        return mName;
    }

    Team team() {
        return mTeam;
    }

    bool alive() {
        //xxx this is fishy
        return isAlive;
    }

    bool active() {
        return mActive;
    }

    int health() {
        return mWorm ? cast(int)mWorm.physics.lifepower : 0;
    }

    long getGraphic() {
        if (sprite && sprite.graphic) {
            return sprite.graphic.getUID();
        }
        return cInvalidUID;
    }

    // --- end TemaMember

    private void place() {
        if (mWorm)
            return;
        //create and place into the landscape
        //habemus lumbricus
        mWorm = cast(WormSprite)mEngine.createSprite("worm");
        assert(mWorm !is null);
        mWorm.physics.lifepower = mTeam.initialPoints;
        lastKnownLifepower = health;
        //take control over dying, so we can let them die on round end
        mWorm.delayedDeath = true;
        mWorm.gravestone = mTeam.graveStone;
        Vector2f npos, tmp;
        auto water_y = mEngine.waterOffset;
        //first 10: minimum distance from water
        //second 10: retry count
        if (!mEngine.placeObject(water_y-10, 10, tmp, npos,
            mWorm.physics.posp.radius))
        {
            //placement unsuccessful
            //the original game blows a hole into the level at a random
            //position, and then places a small bridge for the worm
            //but for now... just barf and complain
            npos = toVector2f(mEngine.gamelevel.offset
                + mEngine.gamelevel.size / 2);
            mTeam.parent.mLog("couldn't place worm!");
        }
        mWorm.setPos(npos);
        mWorm.active = true;
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
        return mWorm.physics.lifepower < lastKnownLifepower;
    }

    void setActive(bool act) {
        if (mActive == act)
            return;
        if (act) {
            //member is being activated
            mActive = act;
            mWormAction = false;
            mLastAction = timeMusecs(0);
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
                mWorm.drawWeapon(false);
            }
            mActive = act;
        }
    }

    void jump(JumpMode j) {
        if (!isControllable)
            return;
        mWorm.drawWeapon(false);
        switch (j) {
            case JumpMode.normal:
                mWorm.jump();
                break;
            default:
                assert(false, "Implement");
        }
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

    void setJetpack(bool state) {
        if (!isControllable)
            return;
        mWorm.activateJetpack(state);
        wormAction();
    }

    WeaponItem currentWeapon() {
        return mCurrentWeapon;
    }

    void selectWeapon(WeaponItem weapon) {
        if (!isControllable)
            return;
        mCurrentWeapon = weapon;
        if (mCurrentWeapon)
            if (!mCurrentWeapon.haveAtLeastOne())
                mCurrentWeapon = null;
        updateWeapon();
    }

    void selectWeapon(WeaponClass id) {
        selectWeapon(mTeam.weapons.byId(id));
    }

    //update weapon state of current worm (when new weapon selected)
    void updateWeapon() {
        if (!mActive || !isAlive)
            return;

        WeaponClass selected;
        if (mCurrentWeapon) {
            if (!mCurrentWeapon.haveAtLeastOne())
                return;
            if (currentWeapon.weapon) {
                selected = mCurrentWeapon.weapon;
            }
        }
        /*if (selected) {
            messageAdd(_("msgselweapon", _("weapons." ~ selected.name)));
        } else {
            messageAdd(_("msgnoweapon"));
        }*/
        Shooter nshooter;
        if (selected) {
            nshooter = selected.createShooter();
            mTeam.allowSetPoint = selected.canPoint;
        }
        mWorm.shooter = nshooter;
    }

    void doFire() {
        if (!isControllable)
            return;

        auto shooter = worm.shooter;

        if (!worm.weaponDrawn || !worm.shooter)
            return; //go away

        mTeam.parent.mLog("fire: %s", shooter.weapon.name);

        FireInfo info;
        //-1 for left, 1 for right
        auto w = math.copysign(1.0f, Vector2f.fromPolar(1,worm.physics.lookey).x);
        //weaponAngle will be -PI/2 - PI/2, -PI/2 meaning down
        //-> Invert for screen, and add PI/2 if looking left
        info.dir = Vector2f.fromPolar(1.0f, (1-w)*PI/2 - w*worm.weaponAngle);
        info.shootby = worm.physics;
        info.strength = shooter.weapon.throwStrength;
        info.timer = shooter.weapon.timerFrom;
        info.pointto = mTeam.currentTarget;
        shooter.fire(info);

        didFire();
        wormAction();
    }

    void didFire() {
        assert(mCurrentWeapon !is null);
        mCurrentWeapon.decrease();
        mTeam.parent.updateWeaponStats(this);
        if (!mCurrentWeapon.haveAtLeastOne())
            //nothing left? put away
            selectWeapon(cast(WeaponItem)null);
        //xxx select next weapon when current is empty... oh sigh
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

        if (vec.x != 0) {
            //requested walk -> put away weapon
            mWorm.drawWeapon(false);
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
        if (mWorm.isStanding())
            //worms are not standing, they are FIGHTING!
            mWorm.drawWeapon(true);
    }
}

class WeaponSet {
    WeaponItem[WeaponClass] weapons;
    char[] name;

    //config = item from "weapon_sets"
    void readFromConfig(ConfigNode config, GameEngine engine) {
        name = config.name;
        foreach (ConfigNode node; config.getSubNode("weapon_list")) {
            auto weapon = new WeaponItem();
            weapon.loadFromConfig(node, engine);
            weapons[weapon.weapon] = weapon;
        }
    }

    WeaponItem byId(WeaponClass weaponId) {
        if (weaponId in weapons)
            return weapons[weaponId];
        return null;
    }
}

class WeaponItem {
    private {
        WeaponSet mContainer;
        WeaponClass mWeapon;
        int mQuantity;
        bool mInfiniteQuantity;
    }

    bool haveAtLeastOne() {
        return mQuantity > 0 || mInfiniteQuantity;
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

    //an item in "weapon_list"
    void loadFromConfig(ConfigNode config, GameEngine engine) {
        //xxx error handling
        auto w = config["type"];
        mWeapon = engine.findWeaponClass(w);
        if (config.valueIs("quantity", "inf")) {
            mInfiniteQuantity = true;
        } else {
            mQuantity = config.getIntValue("quantity", 0);
        }
    }

    //only instantiated from WeaponSet
    private this() {
    }
}

//the GameController controlls the game play; especially, it converts keyboard
//events into worm moves (or weapon moves!), controlls which object is focused
//by the "camera", and also manages worm teams
//xxx: move gui parts out of this
class GameController : GameLogicPublic {
    private {
        GameEngine mEngine;
        Log mLog;

        ServerTeam[] mTeams;
        ServerTeam mCurrentTeam;
        ServerTeam mLastTeam;

        //xxx for loading only
        ConfigNode[char[]] mWeaponSets;

        Time mRoundRemaining, mPrepareRemaining;
        //time a round takes
        Time mTimePerRound;
        //extra time before round time to switch seats etc
        Time mHotseatSwitchTime;
        bool mIsAnythingGoingOn; // (= hack)

        Queue!(char[]) mMessages;
        //time between messages, how they are actually displayed
        //is up to the gui
        const cMessageTime = 1.5f;
        Time mLastMsgTime;
        //called whenever a message should be sent to the gui, which
        //will show it asap
        void delegate(char[]) mMessageCb;

        RoundState mCurrentRoundState = RoundState.nextOnHold;

        ServerMemberControl control;
        GameLogicPublicCallback controlBack;
        //state associated with controlBack
        bool lastReportedPauseState;
        RoundState lastReportedRoundState;
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

        mTimePerRound = timeSecs(config.gamemode.getIntValue("roundtime",15));
        mHotseatSwitchTime = timeSecs(
            config.gamemode.getIntValue("hotseattime",5));

        mMessages = new Queue!(char[]);
        mLastMsgTime = timeSecs(-cMessageTime);
    }

    //--- start GameLogicPublic

    void setGameLogicCallback(GameLogicPublicCallback glpc) {
        assert(controlBack is null);
        controlBack = glpc;
    }

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

    //--- end GameLogicPublic

    void updateClientRoundStateTime() {
        if (!controlBack)
            return;

        if (currentRoundState() != lastReportedRoundState) {
            lastReportedRoundState = currentRoundState();
            controlBack.gameLogicUpdateRoundState();
        }

        if (mEngine.gameTime.paused != lastReportedPauseState) {
            lastReportedPauseState = mEngine.gameTime.paused;
            controlBack.gameLogicRoundTimeUpdate(currentRoundTime,
                lastReportedPauseState);
        }
    }

    void updateWeaponStats(TeamMember m) {
        if (controlBack) {
            controlBack.gameLogicWeaponListUpdated(m ? m.team : null);
        }
    }

    GameEngine engine() {
        return mEngine;
    }

    void delegate(char[]) messageCb() {
        return mMessageCb;
    }
    void messageCb(void delegate(char[]) cb) {
        mMessageCb = cb;
    }

    private void messageAdd(char[] msg) {
        mMessages.push(msg);
    }

    private bool messageIsIdle() {
        return mMessages.empty;
    }

    void startGame() {
        mIsAnythingGoingOn = true;
        //nothing happening? start a round
        messageAdd(_("msggamestart"));

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
                char[] msg = mMessages.pop();
                //note that messages will get lost if callback is not set,
                //this is intended
                if (mMessageCb)
                    mMessageCb(msg);
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
                mRoundRemaining = mRoundRemaining - deltaT;
                if (mRoundRemaining < timeMusecs(0))
                    return RoundState.cleaningUp;
                if (!mCurrentTeam.current)
                    return RoundState.cleaningUp;
                if (!mCurrentTeam.current.isAlive
                    || mCurrentTeam.current.lifeLost)
                    return RoundState.cleaningUp;
                break;
            case RoundState.cleaningUp:
                mRoundRemaining = timeSecs(0);
                //not yet
                return checkDyingWorms()
                    ? RoundState.cleaningUp : RoundState.nextOnHold;
                break;
            case RoundState.nextOnHold:
                if (messageIsIdle() && objectsIdle())
                    return RoundState.prepare;
                break;
            case RoundState.end:
                break;
        }
        return mCurrentRoundState;
    }

    private void transition(RoundState st) {
        assert(st != mCurrentRoundState);
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
                currentTeam = next;
                mLastTeam = next;
                if (!next) {
                    messageAdd("omg! all dead!");
                    //sry
                    //transition(RoundState.end);
                    mCurrentRoundState = RoundState.end;
                    goto case RoundState.end;
                }

                break;
            case RoundState.playing:
                if (mCurrentTeam)
                    mCurrentTeam.setOnHold(false);
                mPrepareRemaining = timeMusecs(0);
                break;
            case RoundState.cleaningUp:
                //no control while blowing up worms
                if (mCurrentTeam)
                    mCurrentTeam.setOnHold(true);
                //see doState()
                break;
            case RoundState.nextOnHold:
                currentTeam = null;
                messageAdd(_("msgnextround"));
                mRoundRemaining = timeMusecs(0);
                break;
            case RoundState.end:
                messageAdd(_("msggameend"));
                currentTeam = null;
                break;
        }

        //report it! but not too early, the changes must first have been made
        if (controlBack) {
            controlBack.gameLogicUpdateRoundState();
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
        control.memberChanged();
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
        auto set = new WeaponSet();
        set.readFromConfig(ws, mEngine);
        return set;
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
    }

    //create and place worms when necessary
    private void placeWorms() {
        mLog("placing worms...");

        foreach (t; mTeams) {
            t.placeMembers();
        }

        mLog("placing worms done.");
    }

    void selectWeapon(WeaponClass weaponId) {
        if (mCurrentTeam)
            mCurrentTeam.selectWeapon(weaponId);
    }
}
