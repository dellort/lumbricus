module game.controller;
import game.game;
import game.worm;
import game.sprite;
import game.scene;
import utils.vector2;
import utils.configfile;
import utils.log;
import game.common;

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
        teamColor = node.selectValueFrom("teamColor", cTeamColors, 0);
        //the worms currently aren't loaded by theirselves...
        foreach (char[] value; node.getSubNode("member_names")) {
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
                mEngine.setCameraFocus(mCurrent.mWorm.graphic);
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

    private void handleDirKey(Keycode c, bool up) {
        float v = up ? 0 : 1;
        switch (c) {
            case Keycode.LEFT:
                dirKeyState.x = -v;
                break;
            case Keycode.RIGHT:
                dirKeyState.x = +v;
                break;
            case Keycode.UP:
                dirKeyState.y = -v;
                break;
            case Keycode.DOWN:
                dirKeyState.y = +v;
                break;
            default:
                return;
        }

        //control the worm (better only on state change)
        mCurrent.worm.move(dirKeyState);
    }

    private bool onKeyDown(EventSink sender, KeyInfo info) {
        if (info.code == Keycode.MOUSE_LEFT) {
            mEngine.gamelevel.damage(sender.mousePos, 100);
        }
        if (mCurrent) {
            auto worm = mCurrent.worm;
            handleDirKey(info.code, false);
            if (info.code == Keycode.RETURN) {
                worm.jump();
            } else if (info.code == Keycode.J) {
                //jetpack
                worm.activateJetpack(!worm.jetpackActivated);
            } else if (info.code == Keycode.W) {
                worm.drawWeapon(!worm.weaponDrawn);
            } else if (info.code == Keycode.SPACE) {
                worm.fireWeapon();
            }
        }
        if (info.code == Keycode.S) {
            spawnWorm(sender.mousePos);
        }
        if (info.code == Keycode.TAB) {
            current = selectNext();
        }
        return true;
    }

    private bool onKeyUp(EventSink sender, KeyInfo info) {
        if (mCurrent) {
            handleDirKey(info.code, true);
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
