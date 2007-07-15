module game.gui.gameframe;

import common.common;
import common.scene;
import common.visual;
import gui.container;
import gui.widget;
import gui.messageviewer;
import gui.mousescroller;
import game.gui.loadingscreen;
import game.gui.gametimer;
import game.gui.windmeter;
import game.gui.preparedisplay;
import game.clientengine;
import game.gamepublic;
import game.gui.gameview;
import game.game;
import levelgen.level;
import utils.time;
import utils.vector2;
import utils.log;

class GameFrame : SimpleContainer {
    ClientGameEngine clientengine;

    private MouseScroller mScroller;
    private SimpleContainer mGui;
    GameView gameView;

    this(ClientGameEngine ce) {
        clientengine = ce;

        gDefaultLog("initializeGameGui");

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
        gameView.loadBindings(globals.loadConfig("wormbinds")
            .getSubNode("binds"));

        //yyy gameView.controller = controller;

        mScroller = new MouseScroller();
        mScroller.add(gameView);
        add(mScroller);
        add(mGui);

        //start at level center
        mScroller.scrollCenterOn(clientengine.engine.gamelevel.offset
            + clientengine.engine.gamelevel.size/2, true);
    }
}
