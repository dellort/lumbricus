module game.gui.gameframe;

import common.common;
import common.scene;
import common.visual;
import framework.framework;
import framework.event;
import gui.container;
import gui.label;
import gui.tablecontainer;
import gui.widget;
import gui.messageviewer;
import gui.mousescroller;
import game.gui.loadingscreen;
import game.gui.gametimer;
import game.gui.gameview;
import game.gui.windmeter;
import game.gui.preparedisplay;
import game.gui.weaponsel;
import game.clientengine;
import game.gamepublic;
import game.game;
import game.weapon;
import levelgen.level;
import utils.time;
import utils.misc;
import utils.vector2;
import utils.log;

//special gui element used to display team-bars (for showing the team health)
class Foobar : Widget {
    BoxProperties border;
    Vector2i spacing = {2, 2};
    float percent = 1.0f; //aliveness
    private BoxProperties mFill;

    void fill(Color c) {
        mFill.back = c;
    }

    this() {
        mFill.borderWidth = 0;
    }

    Vector2i layoutSizeRequest() {
        return Vector2i(100, 0);
    }

    override protected void onDraw(Canvas c) {
        auto s = widgetBounds();
        s.p2.x = s.p1.x + cast(int)((s.p2.x - s.p1.x) * percent);
        drawBox(c, s, border);
        s.extendBorder(-spacing);
        drawBox(c, s, mFill);
    }
}

class GameFrame : SimpleContainer, GameLogicPublicCallback {
    ClientGameEngine clientengine;

    private MouseScroller mScroller;
    private SimpleContainer mGui;
    GameView gameView;

    private WeaponSelWindow mWeaponSel;
    private WeaponClass mLastWeapon;

    private TeamWindow mTeamWindow;

    //the team-bars on the bottom of the screen
    private class TeamWindow : Container {
        int mMaxHealth;
        Foobar[Team] mBars;

        this(Team[] teams) {
            auto table = new TableContainer(2, teams.length, Vector2i(3));
            for (int n = 0; n < teams.length; n++) {
                auto teamname = new Label();
                //xxx proper font and color etc.
                teamname.text = teams[n].name;
                teamname.border = Vector2i(3,3);
                //xxx code duplication with gameview.d
                teamname.font = globals.framework.fontManager.loadFont("wormfont_"
                    ~ cTeamColors[teams[n].color]);
                table.add(teamname, 0, n, WidgetLayout.Aligned(1, 0));
                auto bar = new Foobar();
                //xxx again code duplication from gameview.d
                Color c;
                bool res = parseColor(cTeamColors[teams[n].color], c);
                assert(res);
                bar.fill = c;
                mBars[teams[n]] = bar;
                table.add(bar, 1, n);

                mMaxHealth = max(mMaxHealth, teams[n].totalHealth);
            }

            add(table, WidgetLayout.Aligned(0, 1, Vector2i(0, 7)));
        }

        void update() {
            foreach (Team team, Foobar bar; mBars) {
                bar.percent = mMaxHealth ? 1.0f*team.totalHealth/mMaxHealth : 0;
            }
        }

        //don't eat mouse events
        override bool testMouse(Vector2i pos) {
            return false;
        }
    }

    //xxx this be awful hack
    void gameLogicRoundTimeUpdate(Time t, bool timePaused) {
    }
    void gameLogicUpdateRoundState() {
        mTeamWindow.update();
    }
    void gameLogicWeaponListUpdated(Team team) {
        updateWeapons();
    }

    private void updateWeapons() {
        Team t = clientengine.logic.getControl.getActiveTeam();
        if (t) {
            mWeaponSel.update(t.getWeapons());
        }
    }

    private void teamChanged() {
        updateWeapons();
    }

    private void selectWeapon(WeaponClass c) {
        //xxx nasty again
        mLastWeapon = c;
        clientengine.logic.getControl.weaponDraw(c);
    }

    //could be unclean: catch weapon selection shortcut before passing it down
    //to GameView (the GUI does that part)
    protected override bool onKeyDown(char[] bind, KeyInfo k) {
        //noone knows why it doesn't simply pass the bind, instead of k
        auto c = mLastWeapon; //xxx should read the weapon from controller
        if (mWeaponSel.checkNextWeaponInCategoryShortcut(k, c))
            return true;
        return super.onKeyDown(bind, k);
    }

    //scroll to level center
    void scrollToCenter() {
        mScroller.scrollCenterOn(clientengine.engine.gamelevel.offset
            + clientengine.engine.gamelevel.size/2, true);
    }

    this(ClientGameEngine ce) {
        clientengine = ce;

        clientengine.logic.setGameLogicCallback(this);

        gDefaultLog("initializeGameGui");

        auto wormbinds = new KeyBindings();
        wormbinds.loadFrom(globals.loadConfig("wormbinds").getSubNode("binds"));

        mGui = new SimpleContainer();

        mGui.add(new WindMeter(clientengine),
            WidgetLayout.Aligned(1, 1, Vector2i(10, 10)));
        mGui.add(new GameTimer(clientengine),
            WidgetLayout.Aligned(-1, 1, Vector2i(5,5)));

        mGui.add(new PrepareDisplay(clientengine));

        auto msg = new MessageViewer();
        mGui.add(msg);

        gameView = new GameView(clientengine);
        gameView.onTeamChange = &teamChanged;
        gameView.bindings = wormbinds;

        mScroller = new MouseScroller();
        mScroller.add(gameView);
        mScroller.zorder = -1; //don't hide the game GUI
        add(mScroller);
        add(mGui);

        mWeaponSel = new WeaponSelWindow();
        mWeaponSel.onSelectWeapon = &selectWeapon;

        mWeaponSel.selectionBindings = wormbinds;

        add(mWeaponSel, WidgetLayout.Aligned(1, 1, Vector2i(10, 40)));

        mTeamWindow = new TeamWindow(clientengine.logic.getTeams());
        add(mTeamWindow);
    }
}
