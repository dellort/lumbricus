module game.controller;
import game.game;
import game.worm;
import game.sprite;
import game.scene;
import game.animation;
import game.visual;
import game.weapon;
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
    //this values indices into cTeamColors
    int teamColor;
    WeaponSet weapons;
    int initialPoints; //on loading

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
}

//member of a team, currently (and maybe always) capsulates a WormSprite object
class TeamMember {
    private WormSprite mWorm;
    Team team;
    char[] name = "unnamed worm";
    private WeaponItem mCurrentWeapon;

    GObjectSprite sprite() {
        return mWorm;
    }

    WormSprite worm() {
        return mWorm;
    }

    bool isAlive() {
        //currently by havingwormspriteness... since dead worms haven't
        return mWorm !is null;
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
}

//the GameController controlls the game play; especially, it converts keyboard
//events into worm moves (or weapon moves!), controlls which object is focused
//by the "camera", and also manages worm teams
//xxx: move gui parts out of this
class GameController {
    private GameEngine mEngine;
    private Team[] mTeams;
    //xxx for loading only
    private ConfigNode[char[]] mWeaponSets;

    private TeamMember mCurrent; //currently active worm
    private TeamMember mLastActive; //last active worm

    private WormNameDrawer mDrawer;

    private EventSink mEvents;
    private KeyBindings mBindings;

    //key state for LEFT/RIGHT and UP/DOWN
    private Vector2f dirKeyState_lu = {0, 0};  //left/up
    private Vector2f dirKeyState_rd = {0, 0};  //right/down
    private Vector2f movementVec = {0, 0};

    private Log mLog;

    //parts of the Gui
    private SceneObjectPositioned mForArrow;
    private Vector2i mForArrowPos;
    private Animation[] mArrowAnims;
    private Animator mArrow;

    private Time mRoundRemaining, mPrepareRemaining;
    //to select next worm
    private TeamMember[Team] mTeamCurrentOne;
    //time a round takes
    private Time mTimePerRound;
    //extra time before round time to switch seats etc
    private Time mHotseatSwitchTime;
    private bool mIsAnythingGoingOn; // (= hack)
    private bool mWormAction;

    public void delegate(char[]) messageCb;
    public bool delegate() messageIdleCb;

    public SceneView sceneview; //set by someone else (= hack)
    public SceneObject eventcatcher; //r/o, for focus (= also a hack)

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

            hideArrow();

            mLastActive = mCurrent;
        }
        mCurrent = worm;
        if (mCurrent) {
            mLastActive = mCurrent;

            //set camera
            if (mCurrent.mWorm) {
                sceneview.setCameraFocus(mCurrent.mWorm.graphic);
            }
            showArrow();
            messageAdd(_("msgselectworm", mCurrent.name));
        }
    }
    TeamMember current() {
        return mCurrent;
    }

    this(GameEngine engine, GameConfig config) {
        mEngine = engine;

        mLog = registerLog("gamecontroller");

        if (config.weapons) {
            loadWeapons(config.weapons);
        }
        if (config.teams) {
            loadTeams(config.teams);
        }

        mTimePerRound = timeSecs(10);
        mHotseatSwitchTime = timeSecs(5);

        //draws the worm names
        mDrawer = new WormNameDrawer(this);
        mDrawer.setScene(mEngine.scene, GameZOrder.Names);

        mBindings = new KeyBindings();
        mBindings.loadFrom(globals.loadConfig("wormbinds").getSubNode("binds"));

        mEngine.loadAnimations(globals.loadConfig("teamanims"));
        mArrowAnims.length = cTeamColors.length;
        foreach (int n, char[] color; cTeamColors) {
            mArrowAnims[n] = mEngine.findAnimation("darrow_" ~ color);
        }
        mArrow = new Animator();
        mArrow.scene = mEngine.scene;
        mArrow.zorder = GameZOrder.Names;

        //the stupid!
        //xxx sucks!
        eventcatcher = new EventCatcher();
        eventcatcher.setScene(mEngine.scene, 0);
        mEvents = eventcatcher.getEventSink();
        //mEvents.onMouseMove = &onMouseMove;
        mEvents.onKeyDown = &onKeyDown;
        mEvents.onKeyUp = &onKeyUp;
    }

    //currently needed to deinitialize the gui
    void kill() {
    }

    void simulate(float deltaT) {
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

                //object moved -> arrow disappears
                if (mForArrow && mForArrowPos != mForArrow.pos)
                    hideArrow();

                break;
            case RoundState.cleaningUp:
                //not yet
                return RoundState.nextOnHold;
                break;
            case RoundState.nextOnHold:
                if (messageIsIdle())
                    return RoundState.prepare;
                break;
        }
        return mCurrentRoundState;
    }

    private void transition(RoundState st) {
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
                }
                break;
            case RoundState.playing:
                mPrepareRemaining = timeMusecs(0);
                break;
            case RoundState.cleaningUp:
                break;
            case RoundState.nextOnHold:
                current = null;
                messageAdd(_("msgnextround"));
                mRoundRemaining = timeMusecs(0);
                break;
        }
        mCurrentRoundState = st;
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

    void showArrow() {
        if (mCurrent && mCurrent.mWorm) {
            mForArrow = mCurrent.mWorm.graphic;
            mForArrowPos = mForArrow.pos;
            mArrow.setAnimation(mArrowAnims[mCurrent.team.teamColor]);
            //15 pixels above object
            //xxx: center and should know about this worm label...
            mArrow.pos = mForArrowPos - mArrow.size.Y - Vector2i(0, 15);
            mArrow.active = true;
        }
    }
    void hideArrow() {
        mArrow.active = false;
    }
    //called if any action is issued, i.e. key pressed to control worm
    void currentWormAction() {
        mWormAction = true;
        hideArrow();
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
            }
            mCurrent.mWorm.shooter = nshooter;
        }
    }

    private TeamMember selectNext() {
        if (!mCurrent) {
            //hum? this is debug code
            return mTeams ? mTeams[0].findNext(null) : null;
        } else {
            return selectNextFromTeam(mCurrent);
        }
    }

    private TeamMember selectNextFromTeam(TeamMember cur) {
        if (!cur)
            return null;
        return cur.team.findNext(cur);
    }

    //actually still stupid debugging code
    private void spawnWorm(Vector2i pos) {
        /*auto obj = new TeamMember();
        obj.mWorm = cast(WormSprite)mEngine.createSprite("worm");
        assert(obj.mWorm !is null);
        obj.mWorm.setPos(toVector2f(pos));
        if (!mTeams) {
            mTeams ~= new Team();
        }
        obj.name = "worm " ~ str.toString(mTeams[0].mWorms.length+1);
        mTeams[0].mWorms ~= obj;
        obj.team = mTeams[0];
        mCurrent = obj;*/
        //now stupid debug code in another way
        auto w = mEngine.createSprite("worm");
        w.setPos(toVector2f(pos));
        w.active = true;
    }

    private bool canControlWorm() {
        return mCurrentRoundState == RoundState.prepare
            || mCurrentRoundState == RoundState.playing;
    }

    private void moveWorm(Vector2f v) {
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

    private bool onKeyDown(EventSink sender, KeyInfo info) {
        char[] bind = mBindings.findBinding(info);
        switch (bind) {
            case "debug2": {
                mEngine.gamelevel.damage(sender.mousePos, 100);
                return true;
            }
            case "debug1": {
                spawnWorm(sender.mousePos);
                return true;
            }
            case "debug3": {
                mRoundRemaining *= 4;
                break;
            }
            case "selectworm": {
                current = selectNext();
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
                currentWormAction();
                return true;
            }
            case "fire": {
                worm.fireWeapon();
                mCurrent.didFire();
                currentWormAction();
                return true;
            }
            case "weapon_prev": {
                mCurrent.cycleThroughWeapons(-1);
                updateWeapon();
                return true;
            }
            case "weapon_next": {
                mCurrent.cycleThroughWeapons(+1);
                updateWeapon();
                return true;
            }
            default:

        }
        //nothing found
        return false;
    }

    private bool onKeyUp(EventSink sender, KeyInfo info) {
        char[] bind = mBindings.findBinding(info);
        if (handleDirKey(bind, true))
            return true;
        return false;
    }

    //config = the "teams" node, i.e. from data/data/teams.conf
    private void loadTeams(ConfigNode config) {
        current = null;
        mTeams = null;
        foreach (ConfigNode sub; config) {
            mTeams ~= new Team(sub);
            //xxx shouldn't it load itself?
            //xxx error handling
            ConfigNode ws = mWeaponSets[sub["weapon_set"]];
            auto set = new WeaponSet();
            set.readFromConfig(ws, mEngine);
            mTeams[$-1].weapons = set;
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
                m.mWorm = cast(WormSprite)mEngine.createSprite("worm");
                assert(m.mWorm !is null);
                m.mWorm.physics.lifepower = t.initialPoints;
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

private class EventCatcher : SceneObject {
    void draw(Canvas canvas, SceneView parentView) {
        //nop
    }
}

private class WormNameDrawer : SceneObject {
    private GameController mController;
    private Font[Team] mWormFont;

    this(GameController controller) {
        mController = controller;

        //create team fonts (expects teams are already loaded)
        foreach (Team t; controller.mTeams) {
            mWormFont[t] = globals.framework.fontManager.loadFont("wormfont_"
                ~ cTeamColors[t.teamColor]);
        }
    }

    void draw(Canvas canvas, SceneView parentView) {
        //xxx: add code to i.e. move the worm-name labels

        foreach (Team t; mController.mTeams) {
            auto pfont = t in mWormFont;
            if (!pfont)
                continue;
            Font font = *pfont;
            foreach (TeamMember w; t.mWorms) {
                if (!w.mWorm || !w.mWorm.graphic.active)
                    continue;

                char[] text = str.format("%s (%s)", w.name, w.mWorm.physics.lifepowerInt);

                auto wp = w.mWorm.graphic.pos;
                auto sz = w.mWorm.graphic.size;
                //draw 3 pixels above, centered
                auto tsz = font.textSize(text);
                auto pos = wp+Vector2i(sz.x/2 - tsz.x/2, -tsz.y - 3);

                auto border = Vector2i(4, 2);
                //auto b = getBox(tsz+border*2, Color(1,1,1), Color(0,0,0));
                //canvas.draw(b, pos-border);
                if (mController.mEngine.enableSpiffyGui)
                    drawBox(canvas, pos-border, tsz+border*2);
                font.drawText(canvas, pos, text);
            }
        }
    }
}
