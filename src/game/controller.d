module game.controller;
import game.game;
import game.worm;
import game.sprite;
import game.scene;
import game.animation;
import game.visual;
import game.weapon;
import game.resources;
import game.baseengine;
import utils.vector2;
import utils.configfile;
import utils.log;
import utils.time;
import utils.misc;
import game.common;

import framework.framework;
import framework.font;
import framework.i18n;

import str = std.string;

//Hint: there's a limited number of predefined colors; that's because sometimes
//colors are hardcoded in animations, etc.
//so, these are not just color names, but also linked to these animations
static const char[][] cTeamColors = [
    "red",
    "blue",
    "green",
    "yellow",
    "magenta",
    "cyan",
];

class Team {
    char[] name = "unnamed team";
    private TeamMember[] mWorms;
    //this values indices into cTeamColors and the gravestone animations
    int teamColor, graveStone;
    WeaponSet weapons;
    int initialPoints; //on loading

    Vector2f currentTarget;
    bool targetIsSet;

    //wraps around, if w==null, return first element, if any
    private TeamMember doFindNext(TeamMember w) {
        return arrayFindNext(mWorms, w);
    }

    TeamMember findNext(TeamMember w, bool must_be_alive = false) {
        return arrayFindNextPred(mWorms, w,
            (TeamMember t) {
                return !must_be_alive || t.isAlive;
            }
        );
    }

    //if there's any alive worm
    bool isAlive() {
        return findNext(null, true) !is null;
    }

    private this() {
    }

    //node = the node describing a single team
    this(ConfigNode node) {
        name = node.getStringValue("name", name);
        teamColor = node.selectValueFrom("color", cTeamColors, 0);
        initialPoints = node.getIntValue("power", 100);
        graveStone = node.getIntValue("grave", 0);
        //the worms currently aren't loaded by theirselves...
        foreach (char[] name, char[] value; node.getSubNode("member_names")) {
            auto worm = new TeamMember();
            worm.name = value;
            worm.team = this;
            mWorms ~= worm;
        }
    }

    char[] toString() {
        return "[team '" ~ name ~ "']";
    }

    int opApply(int delegate(inout TeamMember member) del) {
        foreach (TeamMember m; mWorms) {
            int res = del(m);
            if (res)
                return res;
        }
        return 0;
    }
}

//member of a team, currently (and maybe always) capsulates a WormSprite object
class TeamMember {
    private WormSprite mWorm;
    Team team;
    char[] name = "unnamed worm";
    int lastKnownLifepower;
    private WeaponItem mCurrentWeapon;

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

    char[] toString() {
        return "[tworm " ~ (team ? team.toString() : null) ~ ":'" ~ name ~ "']";
    }

    WeaponItem currentWeapon() {
        return mCurrentWeapon;
    }
    //dir = +1 or -1
    void cycleThroughWeapons(int dir) {
        if (dir > 0) {
            mCurrentWeapon = arrayFindNext(team.weapons.weapons, mCurrentWeapon);
        } else if (dir < 0) {
            mCurrentWeapon = arrayFindPrev(team.weapons.weapons, mCurrentWeapon);
        }
    }

    void didFire() {
        assert(mCurrentWeapon !is null);
        mCurrentWeapon.decrease();
        //xxx select next weapon when current is empty... oh sigh
    }
}

class WeaponSet {
    WeaponItem[] weapons;
    char[] name;

    //config = item from "weapon_sets"
    void readFromConfig(ConfigNode config, GameEngine engine) {
        name = config.name;
        foreach (ConfigNode node; config.getSubNode("weapon_list")) {
            auto weapon = new WeaponItem();
            weapon.loadFromConfig(node, engine);
            weapons ~= weapon;
        }
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

    //an item in "weapon_list"
    void loadFromConfig(ConfigNode config, GameEngine engine) {
        //xxx error handling
        mWeapon = engine.findWeaponClass(config["type"]);
        if (config.valueIs("quantity", "inf")) {
            mInfiniteQuantity = true;
        } else {
            mQuantity = config.getIntValue("type", 0);
        }
    }

    //only instantiated from WeaponSet
    private this() {
    }
}

enum RoundState {
    prepare,    //player ready
    playing,    //round running
    cleaningUp, //worms losing hp etc, may occur during round
    nextOnHold, //next round about to start (drop crates, ...)
    end,        //everything ended!
}

//the GameController controlls the game play; especially, it converts keyboard
//events into worm moves (or weapon moves!), controlls which object is focused
//by the "camera", and also manages worm teams
//xxx: move gui parts out of this
class GameController {
    private GameEngine mEngine;
    private Team[] mTeams;
    private TeamMember[] mAllWorms;
    //xxx for loading only
    private ConfigNode[char[]] mWeaponSets;

    private TeamMember mCurrent; //currently active worm
    //position where worm started, used to check if worm did anything (?)
    private Vector2f mCurrent_startpos;

    private TeamMember mLastActive; //last active worm

    //key state for LEFT/RIGHT and UP/DOWN
    private Vector2f dirKeyState_lu = {0, 0};  //left/up
    private Vector2f dirKeyState_rd = {0, 0};  //right/down
    private Vector2f movementVec = {0, 0};

    private Log mLog;

    //parts of the Gui
    private SceneObjectPositioned mForArrow;
    private Vector2i mForArrowPos;

    //if you can click anything, if true, also show that animation
    private bool mAllowSetPoint;

    private Time mRoundRemaining, mPrepareRemaining;
    //to select next worm
    private TeamMember[Team] mTeamCurrentOne;
    //time a round takes
    private Time mTimePerRound;
    //extra time before round time to switch seats etc
    private Time mHotseatSwitchTime;
    private bool mIsAnythingGoingOn; // (= hack)
    private bool mWormAction;
    private Time mCurrentLastAction;
    private Time cLongAgo;

    public void delegate(char[]) messageCb;
    public bool delegate() messageIdleCb;

    public SceneView sceneview; //set by someone else (= hack)

    private RoundState mCurrentRoundState;

    void current(TeamMember worm) {
        if (mCurrent) {
            auto old = mCurrent.worm;
            if (old) {
                //switch all off!
                old.activateJetpack(false);
                old.move(Vector2f(0));
                old.drawWeapon(false);
            }

            //possibly was focused on it, release camera focus then
            sceneview.setCameraFocus(null, CameraStyle.Reset);

            allowSetPoint = false;
            mCurrentLastAction = cLongAgo;

            mLastActive = mCurrent;
        }
        mCurrent = worm;
        if (mCurrent) {
            mLastActive = mCurrent;

            //set camera
            if (mCurrent.mWorm) {
                sceneview.setCameraFocus(mCurrent.mWorm.graphic);
                mCurrent_startpos = mCurrent.mWorm.physics.pos;
            }
            mCurrentLastAction = cLongAgo;
            messageAdd(_("msgselectworm", mCurrent.name));
        }
    }
    TeamMember current() {
        return mCurrent;
    }

    bool haveCurrentControl() {
        auto worm = mCurrent ? mCurrent.mWorm : null;
        if (!worm)
            return false;
        return worm.haveAnyControl();
    }

    this(GameEngine engine, GameConfig config) {
        cLongAgo = timeHours(-24);

        mEngine = engine;

        mLog = registerLog("gamecontroller");

        if (config.weapons) {
            loadWeapons(config.weapons);
        }
        if (config.teams) {
            loadTeams(config.teams);
        }

        mTimePerRound = timeSecs(config.gamemode.getIntValue("roundtime",15));
        mHotseatSwitchTime = timeSecs(
            config.gamemode.getIntValue("hotseattime",5));
    }

    //currently needed to deinitialize the gui
    void kill() {
    }

    GameEngine engine() {
        return mEngine;
    }

    void simulate(float deltaT) {
        if (current && current.mWorm) {
            if (mCurrent_startpos != current.mWorm.physics.pos)
                currentWormAction(false);
        }
        if (!mIsAnythingGoingOn) {
            mIsAnythingGoingOn = true;
            //nothing happening? start a round
            messageAdd(_("msggamestart"));

            mCurrentRoundState = RoundState.nextOnHold;
            current = null;
            transition(RoundState.prepare);
        }

        RoundState next = doState(deltaT);
        if (next != mCurrentRoundState)
            transition(next);

        if (mCurrentRoundState == RoundState.playing) {
            if (!current || current.dead()) {
                messageAdd("bad luck!");
                transition(RoundState.cleaningUp);
            }
        }
    }

    Time currentLastAction() {
        return mCurrentLastAction;
    }

    //return true if there are dying worms
    private bool checkDyingWorms() {
        bool morework;
        foreach (TeamMember m; mAllWorms) {
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
                morework = true;
            } else if (worm.isDelayedDying()) {
                //suiciding
                morework = true;
            }
        }
        return morework;
    }

    private RoundState doState(float deltaT) {
        switch (mCurrentRoundState) {
            case RoundState.prepare:
                mPrepareRemaining = mPrepareRemaining - timeSecs(deltaT);
                moveWorm(movementVec);
                if (mWormAction)
                    //worm moved -> exit prepare phase
                    return RoundState.playing;
                if (mPrepareRemaining < timeMusecs(0))
                    return RoundState.playing;
                break;
            case RoundState.playing:
                mRoundRemaining = mRoundRemaining - timeSecs(deltaT);
                if (mRoundRemaining < timeMusecs(0))
                    return RoundState.cleaningUp;

                moveWorm(movementVec);

                break;
            case RoundState.cleaningUp:
                mRoundRemaining = timeSecs(0);
                //not yet
                return checkDyingWorms()
                    ? RoundState.cleaningUp : RoundState.nextOnHold;
                break;
            case RoundState.nextOnHold:
                if (messageIsIdle())
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
                mWormAction = false;
                mRoundRemaining = mTimePerRound;
                mPrepareRemaining = mHotseatSwitchTime;

                auto old = mLastActive;

                //save that
                if (old) {
                    mTeamCurrentOne[old.team] = old;
                }

                //select next team/worm
                Team currentTeam = old ? old.team : null;
                Team next = arrayFindNextPred(mTeams, currentTeam,
                    (Team t) {
                        return t.isAlive();
                    }
                );
                TeamMember nextworm;
                if (next) {
                    auto w = next in mTeamCurrentOne;
                    TeamMember cur = w ? *w : null;
                    nextworm = next.findNext(cur, true);
                }

                current = nextworm;

                if (!mCurrent) {
                    messageAdd("omg! all dead!");
                    transition(RoundState.end);
                }
                break;
            case RoundState.playing:
                mPrepareRemaining = timeMusecs(0);
                break;
            case RoundState.cleaningUp:
                //see doState()
                break;
            case RoundState.nextOnHold:
                current = null;
                messageAdd(_("msgnextround"));
                mRoundRemaining = timeMusecs(0);
                break;
            case RoundState.end:
                messageAdd(_("msggameend"));
                current = null;
                break;
        }
    }

    public RoundState currentRoundState() {
        return mCurrentRoundState;
    }

    public Team currentTeam() {
        if (current)
            return current.team;
        else
            return null;
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

    private void messageAdd(char[] msg) {
        if (messageCb)
            messageCb(msg);
    }

    private bool messageIsIdle() {
        if (messageIdleCb)
            return messageIdleCb();
        else
            return true;
    }

    void allowSetPoint(bool set) {
        if (mAllowSetPoint == set)
            return;
        mAllowSetPoint = set;
        mCurrent.team.targetIsSet = false;
    }
    void doSetPoint(Vector2f where) {
        if (!mAllowSetPoint)
            return;

        if (mCurrent) {
            mCurrent.team.targetIsSet = true;
            mCurrent.team.currentTarget = where;
        }
    }

    //called if any action is issued, i.e. key pressed to control worm
    //or if it was moved by sth. else
    void currentWormAction(bool fromkeys = true) {
        if (fromkeys) {
            mWormAction = true;
            mCurrentLastAction = mEngine.currentTime;
        }
    }

    //update weapon state of current worm (when new weapon selected)
    void updateWeapon() {
        if (!mCurrent)
            return;
        //argh
        if (mCurrent.mWorm) {
            WeaponClass selected;
            if (mCurrent.currentWeapon) {
                if (mCurrent.currentWeapon.weapon) {
                    selected = mCurrent.currentWeapon.weapon;
                }
            }
            if (selected) {
                messageAdd(_("msgselweapon", _("weapons." ~ selected.name)));
            } else {
                messageAdd(_("msgnoweapon"));
            }
            Shooter nshooter;
            if (selected) {
                nshooter = selected.createShooter();
                allowSetPoint = selected.canPoint;
            }
            mCurrent.mWorm.shooter = nshooter;
        }
    }

    //xxx code duplication with code that selects worm for next round
    private TeamMember selectNext() {
        if (!mCurrent) {
            //hum? this is debug code
            //return mTeams ? mTeams[0].findNext(null) : null;
            return null;
        } else {
            return selectNextFromTeam(mCurrent);
        }
    }
    private TeamMember selectNextFromTeam(TeamMember cur) {
        if (!cur)
            return null;
        return cur.team.findNext(cur, true);
    }

    //actually still stupid debugging code
    private void spawnWorm(Vector2i pos) {
        //now stupid debug code in another way
        auto w = mEngine.createSprite("worm");
        w.setPos(toVector2f(pos));
        w.active = true;
    }

    private bool canControlWorm() {
        return mCurrent !is null
            && (mCurrentRoundState == RoundState.prepare
                || mCurrentRoundState == RoundState.playing)
            && mCurrent.mWorm
            && mCurrent.mWorm.haveAnyControl();
    }

    private void moveWorm(Vector2f v) {
        if (!mCurrent || !mCurrent.worm)
            return;

        if (canControlWorm() && movementVec != Vector2f(0)) {
            mCurrent.worm.move(movementVec);
            currentWormAction();
        } else {
            mCurrent.worm.move(Vector2f(0));
        }
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

        return true;
    }

    bool onKeyDown(char[] bind, KeyInfo info, Vector2i mousePos) {
        switch (bind) {
            case "debug2": {
                mEngine.gamelevel.damage(mousePos, 100);
                return true;
            }
            case "debug1": {
                spawnWorm(mousePos);
                return true;
            }
            case "debug3": {
                mRoundRemaining *= 4;
                return true;
            }
            case "selectworm": {
                current = selectNext();
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

        if (!mCurrent || !canControlWorm())
            return false;
        auto worm = mCurrent.worm;

        switch (bind) {
            case "jump": {
                worm.jump();
                currentWormAction();
                return true;
            }
            case "jetpack": {
                worm.activateJetpack(!worm.jetpackActivated);
                currentWormAction();
                return true;
            }
            case "weapon": {
                worm.drawWeapon(!worm.weaponDrawn);
                updateWeapon();
                currentWormAction();
                return true;
            }
            case "fire": {
                doFire();
                return true;
            }
            case "weapon_prev": {
                mCurrent.cycleThroughWeapons(-1);
                updateWeapon();
                currentWormAction();
                return true;
            }
            case "weapon_next": {
                mCurrent.cycleThroughWeapons(+1);
                updateWeapon();
                currentWormAction();
                return true;
            }
            case "debug4": {
                worm.physics.applyDamage(100000);
                currentWormAction();
                return true;
            }
            default:

        }
        //nothing found
        return false;
    }

    private void doFire() {
        if (!mCurrent || !mCurrent.worm)
            return;

        auto worm = mCurrent.worm;
        auto shooter = worm.shooter;

        if (!worm.weaponDrawn || !worm.shooter)
            return; //go away

        mLog("fire: %s", shooter.weapon.name);

        FireInfo info;
        info.dir = Vector2f.fromPolar(1.0f, worm.weaponAngle);
        info.shootby = worm.physics;
        info.strength = shooter.weapon.throwStrength;
        info.timer = shooter.weapon.timerFrom;
        info.pointto = mCurrent.team.currentTarget;
        shooter.fire(info);

        mCurrent.didFire();
        currentWormAction();
    }

    bool onKeyUp(char[] bind, KeyInfo info, Vector2i mousePos) {
        if (handleDirKey(bind, true))
            return true;
        return false;
    }

    //config = the "teams" node, i.e. from data/data/teams.conf
    private void loadTeams(ConfigNode config) {
        current = null;
        mTeams = null;
        mAllWorms = null;
        foreach (ConfigNode sub; config) {
            auto team = new Team(sub);
            //xxx shouldn't it load itself?
            //xxx error handling
            ConfigNode ws = mWeaponSets[sub["weapon_set"]];
            auto set = new WeaponSet();
            set.readFromConfig(ws, mEngine);
            team.weapons = set;
            mTeams ~= team;
            mAllWorms ~= team.mWorms;
        }
        placeWorms();
    }

    //"weapon_sets" in teams.conf
    private void loadWeapons(ConfigNode config) {
        foreach (ConfigNode item; config) {
            mWeaponSets[item.name] = item;
        }
    }

    //create and place worms when necessary
    private void placeWorms() {
        mLog("placing worms...");

        foreach (Team t; mTeams) {
            foreach (TeamMember m; t.mWorms) {
                if (m.mWorm)
                    continue;
                //create and place into the landscape
                //habemus lumbricus
                m.mWorm = cast(WormSprite)mEngine.createSprite("worm");
                assert(m.mWorm !is null);
                m.mWorm.physics.lifepower = t.initialPoints;
                m.lastKnownLifepower = t.initialPoints;
                //take control over dying, so we can let them die on round end
                m.mWorm.delayedDeath = true;
                m.mWorm.gravestone = t.graveStone;
                Vector2f npos, tmp;
                auto water_y = mEngine.waterOffset;
                //first 10: minimum distance from water
                //second 10: retry count
                if (!mEngine.placeObject(water_y-10, 10, tmp, npos,
                    m.mWorm.physics.posp.radius))
                {
                    //placement unsuccessful
                    //the original game blows a hole into the level at a random
                    //position, and then places a small bridge for the worm
                    //but for now... just barf and complain
                    npos = toVector2f(mEngine.gamelevel.offset
                        + Vector2i(mEngine.gamelevel.width / 2, 0));
                    mLog("couldn't place worm!");
                }
                m.mWorm.setPos(npos);
                m.mWorm.active = true;
            }
        }

        mLog("placing worms done.");
    }
}
