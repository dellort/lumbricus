module game.controller;
import game.game;
import game.worm;
import game.sprite;
import game.scene;
import utils.vector2;
import utils.configfile;
import utils.log;
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
];

class Team {
    char[] name = "unnamed team";
    private TeamMember[] mWorms;
    //this values indices into cTeamColors
    int teamColor;

    TeamMember findNext(TeamMember w) {
        if (!mWorms)
            return null;

        int found = -1;
        foreach (int i, TeamMember c; mWorms) {
            if (w is c) {
                found = i;
                break;
            }
        }
        found = (found + 1) % mWorms.length;
        return mWorms[found];
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

    char[] toString() {
        return "[tworm " ~ (team ? team.toString() : null) ~ ":'" ~ name ~ "']";
    }
}

//the GameController controlls the game play; especially, it converts keyboard
//events into worm moves (or weapon moves!), controlls which object is focused
//by the "camera", and also manages worm teams
class GameController {
    private GameEngine mEngine;
    private Team[] mTeams;

    private TeamMember mCurrent; //currently active worm

    private EventSink mEvents;
    private KeyBindings mBindings;
    //key state for LEFT/RIGHT and UP/DOWN
    private Vector2f dirKeyState = {0, 0};

    private Log mLog;

    void current(TeamMember worm) {
        auto old = mCurrent ? mCurrent.worm : null;
        if (old) {
            //switch all off!
            old.activateJetpack(false);
            old.move(Vector2f(0));
            old.drawWeapon(false);
        }
        mCurrent = worm;
        if (mCurrent) {
            //set camera
            if (mCurrent.mWorm) {
                //xxx use controller-specific scene view
                globals.toplevel.sceneview.setCameraFocus(mCurrent.mWorm.graphic);
            }
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
        auto names = new WormNameDrawer(this);
        names.setScene(mEngine.scene, GameZOrder.Names);

        mBindings = new KeyBindings();
        mBindings.loadFrom(globals.loadConfig("wormbinds").getSubNode("binds"));

        //the stupid!
        auto eventcatcher = new EventCatcher();
        eventcatcher.setScene(mEngine.scene, 0);
        mEvents = eventcatcher.getEventSink();
        //mEvents.onMouseMove = &onMouseMove;
        mEvents.onKeyDown = &onKeyDown;
        mEvents.onKeyUp = &onKeyUp;

        //xxx sucks!
        globals.toplevel.screen.setFocus(eventcatcher);
    }

    private TeamMember selectNext() {
        if (!mCurrent) {
            //hum?
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
                return true;
            }
            case "jetpack": {
                worm.activateJetpack(!worm.jetpackActivated);
                return true;
            }
            case "weapon": {
                worm.drawWeapon(!worm.weaponDrawn);
                return true;
            }
            case "fire": {
                worm.fireWeapon();
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
                auto sz = w.mWorm.graphic.thesize;
                //draw 3 pixels above, centered
                auto tsz = font.textSize(text);
                auto pos = wp+Vector2i(sz.x/2 - tsz.x/2, -tsz.y - 3);

                auto border = Vector2i(4, 2);
                //auto b = getBox(tsz+border*2, Color(1,1,1), Color(0,0,0));
                //canvas.draw(b, pos-border);
                drawBox(canvas, pos-border, tsz+border*2);
                font.drawText(canvas, pos, text);
            }
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
            boxParts[n] = globals.framework.loadImage("box"
                ~ toString(n+1) ~ ".png", Transparency.Alpha).createTexture();
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