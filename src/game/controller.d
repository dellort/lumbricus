module game.controller;
import game.game;
import game.worm;
import game.sprite;
import game.scene;
import game.animation;
import utils.vector2;
import utils.configfile;
import utils.log;
import utils.time;
import utils.misc;
import game.common;

import framework.framework;
import framework.font;

import std.string : toString;

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

//return next after w, wraps around, if w==null, return first element, if any
private T arrayFindNext(T)(T[] arr, T w) {
    if (!arr)
        return null;

    int found = -1;
    foreach (int i, T c; arr) {
        if (w is c) {
            found = i;
            break;
        }
    }
    found = (found + 1) % arr.length;
    return arr[found];
}

//searches for next element with pred(element)==true, wraps around, if w is null
//start search with first element, if no element found, return null
private T arrayFindNextPred(T)(T[] arr, T w, bool delegate(T t) pred) {
    T c = arrayFindNext(arr, w);
    while (c) {
        if (pred(c))
            return c;
        if (c is w)
            break;
        c = arrayFindNext(arr, c);
    }
    return null;
}

class Team {
    char[] name = "unnamed team";
    private TeamMember[] mWorms;
    //this values indices into cTeamColors
    int teamColor;

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

//member of a team, currently (and maybe always) capsulates a Worm object
class TeamMember {
    private Worm mWorm;
    Team team;
    char[] name = "unnamed worm";

    GObjectSprite sprite() {
        return mWorm;
    }

    Worm worm() {
        return mWorm;
    }

    bool isAlive() {
        //currently by havingwormspriteness... since dead worms haven't
        return mWorm !is null;
    }

    char[] toString() {
        return "[tworm " ~ (team ? team.toString() : null) ~ ":'" ~ name ~ "']";
    }
}

//the GameController controlls the game play; especially, it converts keyboard
//events into worm moves (or weapon moves!), controlls which object is focused
//by the "camera", and also manages worm teams
//xxx: move gui parts out of this
class GameController {
    private GameEngine mEngine;
    private Team[] mTeams;

    private TeamMember mCurrent; //currently active worm
    private TeamMember mLastActive; //last active worm

    private WormNameDrawer mDrawer;

    private EventSink mEvents;
    private KeyBindings mBindings;
    //key state for LEFT/RIGHT and UP/DOWN
    private Vector2f dirKeyState = {0, 0};

    private Log mLog;

    //parts of the Gui
    private SceneObjectPositioned mForArrow;
    private Vector2i mForArrowPos;
    private Animation[] mArrowAnims;
    private Animator mArrow;
    private MessageViewer mMessages;
    private FontLabel mTimeView;

    private Time mRoundStarted;
    private int mCurrentRoundTime;
    private bool mNextRoundOnHold, mRoundStarting;
    //to select next worm
    private TeamMember[Team] mTeamCurrentOne;

    //of course needs to be configureable etc.
    private const cRoundTime = 10;

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
                //xxx use controller-specific scene view
                globals.toplevel.sceneview.setCameraFocus(mCurrent.mWorm.graphic);
            }
            showArrow();
            mMessages.addMessage("select worm: " ~ mCurrent.name);
        }
    }
    TeamMember current() {
        return mCurrent;
    }

    this(GameEngine engine, GameConfig config) {
        mEngine = engine;

        mLog = registerLog("gamecontroller");

        if (config.teams) {
            loadTeams(config.teams);
        }

        //draws the worm names
        mDrawer = new WormNameDrawer(this);
        mDrawer.setScene(mEngine.scene, GameZOrder.Names);

        mMessages = new MessageViewer();
        //xxx: !
        mMessages.setScene(globals.toplevel.guiscene, game.toplevel.GUIZOrder.Gui);

        mTimeView = new FontLabelBoxed(globals.framework.fontManager.loadFont("time"));
        mTimeView.setScene(globals.toplevel.guiscene, game.toplevel.GUIZOrder.Gui);
        mTimeView.border = Vector2i(7, 5);

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
        auto eventcatcher = new EventCatcher();
        eventcatcher.setScene(mEngine.scene, 0);
        mEvents = eventcatcher.getEventSink();
        //mEvents.onMouseMove = &onMouseMove;
        mEvents.onKeyDown = &onKeyDown;
        mEvents.onKeyUp = &onKeyUp;

        //xxx sucks!
        globals.toplevel.screen.setFocus(eventcatcher);

        //actually start the game
        mMessages.addMessage("start of the game");
        attemptNextRound();
        //don't wait for messages, so force it to actually start now
        //else the round counter will look strange
        startNextRound();
    }

    //currently needed to deinitialize the gui
    void kill() {
        mMessages.active = false;
        mTimeView.active = false;
    }

    void simulate(float deltaT) {
        //object moved -> arrow disappears
        if (mForArrow && mForArrowPos != mForArrow.pos)
            hideArrow();

        //currently mNextRoundOnHold means: next round to start, but must
        //display all messages first
        if (mNextRoundOnHold) {
            if (!mMessages.working) {
                //round is actually now started
                startNextRound();
            }
        }

        auto newrtime = timeSecs(cRoundTime)
            - (globals.gameTime - mRoundStarted);
        auto secs = newrtime.secs;
        if (mCurrentRoundTime != secs) {
            mTimeView.text = str.format("%.2s", secs >= 0 ? secs : 0);
        }
        mCurrentRoundTime = secs;

        //NOTE: might yield to false even if newrtime.secs==0, which is wanted
        if (!mNextRoundOnHold && newrtime <= timeSecs(0)) {
            attemptNextRound();
            mMessages.addMessage("next round!");
        }

        //even more xxx (a gui layouter or so would be better...)
        mTimeView.pos = mTimeView.scene.size.Y - mTimeView.size.Y
            - Vector2i(-20,20);
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
        hideArrow();
    }

    //waits until all messages showed, and then calls nextRound()
    private void attemptNextRound() {
        assert(!mNextRoundOnHold);
        mNextRoundOnHold = true;
        //already deselect old worm
        current = null;
    }

    //called by simulate() only
    private void startNextRound() {
        assert(mNextRoundOnHold);
        mNextRoundOnHold = false;
        mRoundStarted = globals.gameTime;

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
            mMessages.addMessage("omg! all dead!");
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
        auto obj = new TeamMember();
        obj.mWorm = new Worm(mEngine);
        obj.mWorm.setPos(toVector2f(pos));
        if (!mTeams) {
            mTeams ~= new Team();
        }
        obj.name = "worm " ~ str.toString(mTeams[0].mWorms.length+1);
        mTeams[0].mWorms ~= obj;
        obj.team = mTeams[0];
        mCurrent = obj;
    }

    private bool handleDirKey(char[] bind, bool up) {
        float v = up ? 0 : 1;
        switch (bind) {
            case "left":
                dirKeyState.x = -v;
                break;
            case "right":
                dirKeyState.x = +v;
                break;
            case "up":
                dirKeyState.y = -v;
                break;
            case "down":
                dirKeyState.y = +v;
                break;
            default:
                return false;
        }

        //control the worm (better only on state change)
        mCurrent.worm.move(dirKeyState);
        currentWormAction();

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
            case "selectworm": {
                current = selectNext();
                return true;
            }
            default:
        }

        if (!mCurrent)
            return false;
        auto worm = mCurrent.worm;

        if (handleDirKey(bind, false))
            return true;

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
                currentWormAction();
                return true;
            }
            default:

        }
        //nothing found
        return false;
    }

    private bool onKeyUp(EventSink sender, KeyInfo info) {
        char[] bind = mBindings.findBinding(info);
        if (mCurrent) {
            if (handleDirKey(bind, true))
                return true;
        }
        return false;
    }

    //config = the "teams" node, i.e. from data/data/teams.conf
    private void loadTeams(ConfigNode config) {
        current = null;
        mTeams = null;
        foreach (ConfigNode sub; config) {
            mTeams ~= new Team(sub);
        }
        placeWorms();
    }

    //create and place worms when necessary
    private void placeWorms() {
        mLog("placing worms...");

        foreach (Team t; mTeams) {
            foreach (TeamMember m; t.mWorms) {
                if (m.mWorm)
                    continue;
                //create and place into the landscape
                m.mWorm = new Worm(mEngine);
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

                char[] text = w.name;

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

private class FontLabelBoxed : FontLabel {
    this(Font font) {
        super(font);
    }
    void draw(Canvas canvas, SceneView parentView) {
        drawBox(canvas, pos, size);
        super.draw(canvas, parentView);
    }
}

private class MessageViewer : SceneObject {
    private Queue!(char[]) mMessages;
    private char[] mCurrentMessage;
    private Font mFont;
    private Time mLastFrame;
    private int mPhase; //0 = nothing, 1 = blend in, 2 = show, 3 = blend out, 4 = wait
    private Time mPhaseStart; //start of current phase
    private Vector2i mMessageSize;
    private float mMessagePos;
    private float mMessageDelta; //speed of message box

    static const int cPhaseTimingsMs[] = [0, 300, 1000, 300, 400];

    //offset of message from upper border
    const cMessageOffset = 12;
    const Vector2i cMessageBorders = {7, 3};

    this() {
        mFont = globals.framework.fontManager.loadFont("messages");
        mMessages = new Queue!(char[]);
        mLastFrame = globals.gameTimeAnimations;
    }

    void addMessage(char[] msg) {
        mMessages.push(msg);
    }

    //return true as long messages are displayed
    bool working() {
        return !mMessages.empty || mPhase != 0;
    }

    void simulate(Time t, float deltaT) {
        Time phaseT = timeMsecs(cPhaseTimingsMs[mPhase]);
        Time diff = t - mPhaseStart;
        if (diff >= phaseT) {
            //end of current phase
            if (mPhase != 0) {
                mPhase++;
                mPhaseStart = t;
            }
            if (mPhase > 4) {
                //done, no current message anymore
                mCurrentMessage = null;
                mPhase = 0;
            }
        }

        //make some progress
        switch (mPhase) {
            case 0:
                if (!mMessages.empty) {
                    //put new message
                    mPhase = 1;
                    mPhaseStart = t;
                    mCurrentMessage = mMessages.pop();
                    mMessageSize = mFont.textSize(mCurrentMessage);
                    mMessagePos = -mMessageSize.y - cMessageBorders.y*2;
                    mMessageDelta = (-mMessagePos + cMessageOffset)
                        / (cPhaseTimingsMs[mPhase]/1000.0f);
                }
                break;
            case 3:
                mMessagePos -= mMessageDelta * deltaT;
                break;
            case 1:
                mMessagePos += mMessageDelta * deltaT;
                break;
            case 4:
                //nothing
                break;
            case 2:
                mMessagePos = cMessageOffset;
                break;
        }
    }

    void draw(Canvas canvas, SceneView parentView) {
        //argh
        Time now = globals.gameTime;
        float delta = (now - mLastFrame).toFloat();
        mLastFrame = now;
        simulate(now, delta);

        if (mPhase == 1 || mPhase == 2 || mPhase == 3) {
            auto org = scene.size.X / 2 - (mMessageSize+cMessageBorders*2).X / 2;
            org.y += cast(int)mMessagePos;
            drawBox(canvas, org, mMessageSize+cMessageBorders*2);
            mFont.drawText(canvas, org+cMessageBorders, mCurrentMessage);
        }
    }
}

/+
  0 -- 1 -- 2
  |         |
  3   (4)   5
  |         |
  6 -- 7 -- 8
  (png files start with 1)
+/
Texture[9] boxParts;
bool boxesLoaded;

//NOTE: won't work correctly for sizes below the two corner boxes
void drawBox(Canvas c, Vector2i pos, Vector2i size) {
    if (!boxesLoaded) {
        for (int n = 0; n < 9; n++) {
            auto s = globals.loadGraphic("box" ~ toString(n+1) ~ ".png");
            s.enableAlpha();
            boxParts[n] = s.createTexture();
        }
        boxesLoaded = true;
    }
    //corners
    c.draw(boxParts[0], pos);
    c.draw(boxParts[2], pos+size.X-boxParts[2].size.X);
    c.draw(boxParts[6], pos+size.Y-boxParts[6].size.Y);
    c.draw(boxParts[8], pos+size-boxParts[8].size);
    //border lines
    c.drawTiled(boxParts[1], pos+boxParts[0].size.X,
        size.X-boxParts[2].size.X-boxParts[0].size.X+boxParts[1].size.Y);
    c.drawTiled(boxParts[3], pos+boxParts[0].size.Y,
        size.Y-boxParts[6].size.Y-boxParts[0].size.Y+boxParts[3].size.X);
    c.drawTiled(boxParts[5], pos+size.X-boxParts[8].size.X+boxParts[2].size.Y,
        size.Y-boxParts[2].size.Y-boxParts[8].size.Y+boxParts[8].size.X);
    c.drawTiled(boxParts[7], pos+size.Y-boxParts[7].size.Y+boxParts[6].size.X,
        size.X-boxParts[6].size.X-boxParts[8].size.X+boxParts[7].size.Y);
    //fill
    c.drawTiled(boxParts[4], pos+boxParts[0].size,
        size-boxParts[0].size-boxParts[8].size);
}

/+
//quite a hack to draw boxes with rounded borders...
struct BoxProps {
    Vector2i size;
    Color border, back;
}

Texture[BoxProps] boxes;

import utils.drawing;

Texture getBox(Vector2i size, Color border, Color back) {
    BoxProps box;
    box.size = size; box.border = border; box.back = back;
    auto t = box in boxes;
    if (t)
        return *t;
    //create it
    auto surface = globals.framework.createSurface(size, DisplayFormat.Screen,
        Transparency.None);
    auto c = surface.startDraw();
    c.drawFilledRect(Vector2i(0),size,back);
    int radius = 20;
    c.drawFilledRect(Vector2i(0, radius), Vector2i(1, size.y-radius), border);
    c.drawFilledRect(Vector2i(size.x-1, radius),
        Vector2i(size.x, size.y-radius), border);
    circle(radius, radius, radius,
        (int x1, int x2, int y) {
            if (y >= radius)
                y += size.y - radius*2;
            x2 += size.x - radius*2;
            auto p1 = Vector2i(x1, y);
            auto p2 = Vector2i(x2, y);
            //transparency on the side
            c.drawFilledRect(Vector2i(0, y), p1, surface.colorkey);
            c.drawFilledRect(p2, Vector2i(size.x, y), surface.colorkey);
            //circle pixels
            c.drawFilledRect(p1, p1+Vector2i(1), border);
            c.drawFilledRect(p2, p2+Vector2i(1), border);
        }
    );
    c.endDraw();
    boxes[box] = surface.createTexture();
    return boxes[box];
}
+/