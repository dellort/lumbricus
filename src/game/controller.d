module game.controller;
import game.game;
import game.worm;
import game.sprite;
import common.scene;
import game.animation;
import common.visual;
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

import framework.framework;
import framework.font;
import framework.i18n;

import str = std.string;
import math = std.math;

///which style a worm should jump
enum JumpMode {
    normal,      ///standard forward jump (return)
    smallBack,   ///little backwards jump (double return)
    backFlip,    ///large backwards jump/flip (double backspace)
    straightUp,  ///jump straight up (backspace)
}

class Team {
    char[] name = "unnamed team";
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
        TeamMember[] mMembers;  //all members (will not change in-game)
        TeamMember mCurrent;  //active worm that will receive user input
        TeamMember mLastActive;  //worm that played last (to choose next)
        bool mActive;         //is this team playing?
        bool mOnHold;

        //if you can click anything, if true, also show that animation
        bool mAllowSetPoint;

        //key state for LEFT/RIGHT and UP/DOWN
        Vector2f dirKeyState_lu = {0, 0};  //left/up
        Vector2f dirKeyState_rd = {0, 0};  //right/down
        Vector2f movementVec = {0, 0};
    }

    //node = the node describing a single team
    this(ConfigNode node, GameController parent) {
        this.parent = parent;
        name = node.getStringValue("name", name);
        teamColor = node.selectValueFrom("color", cTeamColors, 0);
        initialPoints = node.getIntValue("power", 100);
        graveStone = node.getIntValue("grave", 0);
        //the worms currently aren't loaded by theirselves...
        foreach (char[] name, char[] value; node.getSubNode("member_names")) {
            auto worm = new TeamMember(value, this);
            mMembers ~= worm;
        }
        //xxx error handling
        weapons = parent.initWeaponSet(node["weapon_set"]);
        defaultWeapon = weapons.byId(node["default_weapon"]);
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
                return !must_be_alive || t.isAlive;
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

    int opApply(int delegate(inout TeamMember member) del) {
        foreach (TeamMember m; mMembers) {
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

    private bool handleDirKey(char[] bind, bool up) {
        float v = up ? 0 : 1;
        switch (bind) {
            case "left":
                dirKeyState_lu.x = v;
                break;
            case "right":
                dirKeyState_rd.x = v;
                break;
            case "up":
                dirKeyState_lu.y = v;
                break;
            case "down":
                dirKeyState_rd.y = v;
                break;
            default:
                return false;
        }

        movementVec = dirKeyState_rd-dirKeyState_lu;
        if (mCurrent)
            mCurrent.move(movementVec);

        return true;
    }

    bool onKeyDown(char[] bind, KeyInfo info, Vector2i mousePos) {
        switch (bind) {
            case "debug2": {
                parent.engine.gamelevel.damage(mousePos, 100);
                return true;
            }
            case "debug1": {
                parent.spawnWorm(mousePos);
                return true;
            }
            case "debug3": {
                parent.mRoundRemaining *= 4;
                return true;
            }
            case "selectworm": {
                doChooseWorm();
                return true;
            }
            case "pointy": {
                doSetPoint(toVector2f(mousePos));
                return true;
            }
            default:
        }

        if (handleDirKey(bind, false))
            return true;

        if (!mCurrent)
            return false;

        switch (bind) {
            case "jump": {
                mCurrent.jump(JumpMode.normal);
                return true;
            }
            case "jetpack": {
                mCurrent.toggleJetpack();
                return true;
            }
            case "fire": {
                mCurrent.doFire();
                return true;
            }
            case "debug4": {
                mCurrent.worm.physics.applyDamage(100000);
                return true;
            }
            default:

        }
        //nothing found
        return false;
    }

    bool onKeyUp(char[] bind, KeyInfo info, Vector2i mousePos) {
        if (handleDirKey(bind, true))
            return true;
        return false;
    }

    //select (and draw) a weapon by its id
    void selectWeapon(char[] weaponId) {
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
        foreach (TeamMember m; mMembers) {
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
class TeamMember {
    Team team;
    char[] name = "unnamed worm";
    int lastKnownLifepower;
    private {
        WeaponItem mCurrentWeapon;
        bool mActive;
        Time mLastAction;
        WormSprite mWorm;
        bool mWormAction;
        Vector2f mLastMoveVector;
        GameEngine mEngine;
    }

    this(char[] name, Team team) {
        this.name = name;
        this.team = team;
        mEngine = team.parent.engine;
    }

    private void place() {
        if (mWorm)
            return;
        //create and place into the landscape
        //habemus lumbricus
        mWorm = cast(WormSprite)mEngine.createSprite("worm");
        assert(mWorm !is null);
        mWorm.physics.lifepower = team.initialPoints;
        lastKnownLifepower = team.initialPoints;
        //take control over dying, so we can let them die on round end
        mWorm.delayedDeath = true;
        mWorm.gravestone = team.graveStone;
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
            team.parent.mLog("couldn't place worm!");
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
        return mActive && isAlive() && team.isControllable();
    }

    char[] toString() {
        return "[tworm " ~ (team ? team.toString() : null) ~ ":'" ~ name ~ "']";
    }

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
            lastKnownLifepower = cast(int)mWorm.physics.lifepower;
            //select last used weapon, select default if none
            if (!mCurrentWeapon)
                mCurrentWeapon = team.defaultWeapon;
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

    void toggleJetpack() {
        if (!isControllable)
            return;
        mWorm.activateJetpack(!mWorm.jetpackActivated());
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
            team.allowSetPoint = selected.canPoint;
        }
        mWorm.shooter = nshooter;
    }

    void doFire() {
        if (!isControllable)
            return;

        auto shooter = worm.shooter;

        if (!worm.weaponDrawn || !worm.shooter)
            return; //go away

        team.parent.mLog("fire: %s", shooter.weapon.name);

        FireInfo info;
        //-1 for left, 1 for right
        auto w = math.copysign(1.0f, Vector2f.fromPolar(1,worm.physics.lookey).x);
        //weaponAngle will be -PI/2 - PI/2, -PI/2 meaning down
        //-> Invert for screen, and add PI/2 if looking left
        info.dir = Vector2f.fromPolar(1.0f, (1-w)*PI/2 - w*worm.weaponAngle);
        info.shootby = worm.physics;
        info.strength = shooter.weapon.throwStrength;
        info.timer = shooter.weapon.timerFrom;
        info.pointto = team.currentTarget;
        shooter.fire(info);

        didFire();
        wormAction();
    }

    void didFire() {
        assert(mCurrentWeapon !is null);
        mCurrentWeapon.decrease();
        if (!mCurrentWeapon.haveAtLeastOne())
            //nothing left? put away
            selectWeapon(null);
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
            mLastAction = team.parent.engine.gameTime.current;
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
    WeaponItem[char[]] weapons;
    char[] name;

    //config = item from "weapon_sets"
    void readFromConfig(ConfigNode config, GameEngine engine) {
        name = config.name;
        foreach (ConfigNode node; config.getSubNode("weapon_list")) {
            auto weapon = new WeaponItem();
            weapon.loadFromConfig(node, engine);
            weapons[weapon.weaponId] = weapon;
        }
    }

    WeaponItem byId(char[] weaponId) {
        if (weaponId in weapons)
            return weapons[weaponId];
        return null;
    }
}

class WeaponItem {
    private {
        WeaponSet mContainer;
        WeaponClass mWeapon;
        char[] weaponId;
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

    //an item in "weapon_list"
    void loadFromConfig(ConfigNode config, GameEngine engine) {
        //xxx error handling
        weaponId = config["type"];
        mWeapon = engine.findWeaponClass(weaponId);
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
class GameController : ControllerPublic {
    private {
        GameEngine mEngine;
        Log mLog;

        Team[] mTeams;
        Team mCurrentTeam;
        Team mLastTeam;

        //xxx for loading only
        ConfigNode[char[]] mWeaponSets;

        Time mRoundRemaining, mPrepareRemaining;
        //time a round takes
        Time mTimePerRound;
        //extra time before round time to switch seats etc
        Time mHotseatSwitchTime;
        bool mIsAnythingGoingOn; // (= hack)
        Time mCurrentLastAction;

        Queue!(char[]) mMessages;
        //time between messages, how they are actually displayed
        //is up to the gui
        const cMessageTime = 1.5f;
        Time mLastMsgTime;
        //called whenever a message should be sent to the gui, which
        //will show it asap
        void delegate(char[]) mMessageCb;

        RoundState mCurrentRoundState;
    }

    this(GameEngine engine, GameConfig config) {
        mEngine = engine;

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

        mCurrentRoundState = RoundState.nextOnHold;
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
        foreach (Team t; mTeams) {
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
                Team next = arrayFindNextPred(mTeams, mLastTeam,
                    (Team t) {
                        return t.isAlive();
                    }
                );
                currentTeam = next;
                mLastTeam = next;
                if (!next) {
                    messageAdd("omg! all dead!");
                    transition(RoundState.end);
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
    }

    void currentTeam(Team t) {
        if (mCurrentTeam is t)
            return;
        if (mCurrentTeam)
            mCurrentTeam.setActive(false);
        mCurrentTeam = t;
        if (mCurrentTeam)
            mCurrentTeam.setActive(true);
    }
    Team currentTeam() {
        return mCurrentTeam;
    }

    bool objectsIdle() {
        foreach (t; mTeams) {
            if (!t.isIdle())
                return false;
        }
        return true;
    }

    public RoundState currentRoundState() {
        return mCurrentRoundState;
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

    public Team[] teams() {
        return mTeams;
    }

    public Time currentRoundTime() {
        return mRoundRemaining;
    }

    public Time currentPrepareTime() {
        return mPrepareRemaining;
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
        auto team = new Team(config, this);
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

        foreach (Team t; mTeams) {
            t.placeMembers();
        }

        mLog("placing worms done.");
    }

    //xxx hacks follow

    bool onKeyDown(char[] bind, KeyInfo info, Vector2i mousePos) {
        if (mCurrentTeam)
            return mCurrentTeam.onKeyDown(bind, info, mousePos);
        return false;
    }

    bool onKeyUp(char[] bind, KeyInfo info, Vector2i mousePos) {
        if (mCurrentTeam)
            return mCurrentTeam.onKeyUp(bind, info, mousePos);
        return false;
    }

    void selectWeapon(char[] weaponId) {
        if (mCurrentTeam)
            mCurrentTeam.selectWeapon(weaponId);
    }
}
