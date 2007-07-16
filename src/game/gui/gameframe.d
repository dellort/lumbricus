module game.gui.gameframe;

import common.common;
import common.scene;
import common.visual;
import framework.framework;
import gui.container;
import gui.widget;
import gui.messageviewer;
import gui.mousescroller;
import game.gui.loadingscreen;
import game.gui.gametimer;
import game.gui.windmeter;
import game.gui.preparedisplay;
import game.gui.weaponsel;
import game.clientengine;
import game.gamepublic;
import game.gui.gameview;
import game.game;
import game.weapon;
import levelgen.level;
import utils.time;
import utils.vector2;
import utils.log;

class GameFrame : SimpleContainer, GameLogicPublicCallback {
    ClientGameEngine clientengine;

    private MouseScroller mScroller;
    private SimpleContainer mGui;
    GameView gameView;

    private WeaponSelWindow mWeaponSel;

    //xxx this be awful hack
    void gameLogicRoundTimeUpdate(Time t, bool timePaused) {
    }
    void gameLogicUpdateRoundState() {
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
        clientengine.logic.getControl.weaponDraw(c);
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

        //yyy auto controller = clientengine.engine.controller;

        //yyy controller.messageCb = &msg.addMessage;

        gameView = new GameView(clientengine);
        gameView.onTeamChange = &teamChanged;
        gameView.bindings = wormbinds;

        //yyy gameView.controller = controller;

        mScroller = new MouseScroller();
        mScroller.add(gameView);
        add(mScroller);
        add(mGui);

        //start at level center
        mScroller.scrollCenterOn(clientengine.engine.gamelevel.offset
            + clientengine.engine.gamelevel.size/2, true);

        mWeaponSel = new WeaponSelWindow();
        mWeaponSel.onSelectWeapon = &selectWeapon;

        //um, this is bullshit, but anyway?
        mWeaponSel.bindings = wormbinds;

        add(mWeaponSel, WidgetLayout.Aligned(1, 1, Vector2i(10, 40)));
    }
}
