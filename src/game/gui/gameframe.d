module game.gui.gameframe;

import common.common;
import common.scene;
import common.visual;
import framework.framework;
import framework.event;
import framework.i18n;
import gui.container;
import gui.label;
import gui.tablecontainer;
import gui.widget;
import gui.messageviewer;
import gui.mousescroller;
import game.gui.loadingscreen;
import game.gui.gameteams;
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

class GameFrame : SimpleContainer, GameLogicPublicCallback {
    ClientGameEngine clientengine;

    private MouseScroller mScroller;
    private SimpleContainer mGui;
    GameView gameView;

    private WeaponSelWindow mWeaponSel;

    private TeamWindow mTeamWindow;

    private MessageViewer mMessageViewer;

    //xxx this be awful hack
    void gameLogicRoundTimeUpdate(Time t, bool timePaused) {
    }
    void gameLogicUpdateRoundState() {
        mTeamWindow.update();
    }
    void gameLogicWeaponListUpdated(Team team) {
        updateWeapons();
    }
    void gameShowMessage(char[] msgid, char[][] args) {
        char[] translated = localeRoot.translateWithArray(msgid, args);
        mMessageViewer.addMessage(translated);
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
        clientengine.logic.getControl.weaponDraw(c);
    }

    //could be unclean: catch weapon selection shortcut before passing it down
    //to GameView (the GUI does that part)
    protected override bool onKeyDown(char[] bind, KeyInfo k) {
        //noone knows why it doesn't simply pass the bind, instead of k
        auto c = clientengine.logic.getControl.currentWeapon;
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

        mMessageViewer = new MessageViewer();
        mGui.add(mMessageViewer);

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
