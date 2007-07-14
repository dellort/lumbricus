module game.gui.gameframe;

import common.common;
import common.scene;
import common.visual;
import framework.commandline : CommandBucket, Command;
import gui.container;
import gui.widget;
import gui.messageviewer;
import gui.mousescroller;
import game.gui.loadingscreen;
import game.gui.gametimer;
import game.gui.windmeter;
import game.gui.preparedisplay;
import game.clientengine;
import game.loader;
import game.loader_game;
import game.gamepublic;
import game.gui.gameview;
import game.game;
import levelgen.level;
import levelgen.generator;
import genlevel = levelgen.generator;
import utils.mybox;
import utils.output;
import utils.time;
import utils.vector2;
import utils.log;
import utils.configfile;

//xxx include so that module constructors (static this) are actually called
import game.projectile;
import game.special_weapon;

class GameFrame : SimpleContainer {
    GameEngine thegame;
    GameEnginePublic gameifc;
    GameEngineAdmin gameadmin;
    ClientGameEngine clientengine;
    /*private*/ GameLoader mGameLoader;
    private GameConfig mGameConfig;
    private LoadingScreen mLoadScreen;
    private bool mGameGuiOpened;

    private CommandBucket mCmds;

    private MouseScroller mScroller;
    private SimpleContainer mGui;
    GameView gameView;

    bool gamePaused() {
        return gameifc.paused;
    }
    void gamePaused(bool set) {
        gameadmin.setPaused(set);
        clientengine.engineTime.paused = set;
    }

    this(GameConfig cfg) {
        super();
        mGameConfig = cfg;

        mCmds = new CommandBucket();
        registerCommands();
        mCmds.bind(globals.cmdLine);

        mLoadScreen = new LoadingScreen();
        add(mLoadScreen);

        mLoadScreen.zorder = 10;

        mGameLoader = new GameLoader(this);
        mGameLoader.onFinish = &gameLoaded;
        mGameLoader.onUnload = &gameUnloaded;

        //creaton of this frame -> start new game
        mLoadScreen.startLoad(mGameLoader);
    }

    bool unloadGame() {
        //log("unloadGame");
        if (thegame) {
            thegame.kill();
            thegame = null;
        }
        if (clientengine) {
            clientengine.kill();
            clientengine = null;
        }

        return true;
    }

    bool initGameEngine() {
        //log("initGameEngine");
        thegame = new GameEngine(mGameConfig);
        gameifc = thegame;
        gameadmin = thegame.requestAdmin();
        return true;
    }

    bool initClientEngine() {
        //log("initClientEngine");
        clientengine = new ClientGameEngine(thegame);
        return true;
    }

    bool loadConfig() {
        //moved to gametask.d
        return true;
    }

    bool initializeGameGui() {
        gDefaultLog("initializeGameGui");
        mGameGuiOpened = true;

        mGui = new SimpleContainer();

        mGui.add(new WindMeter(clientengine),
            WidgetLayout.Aligned(1, 1, Vector2i(10, 10)));
        mGui.add(new GameTimer(clientengine),
            WidgetLayout.Aligned(-1, 1, Vector2i(5,5)));

        mGui.add(new PrepareDisplay(clientengine));

        auto msg = new MessageViewer();
        mGui.add(msg);

        thegame.controller.messageCb = &msg.addMessage;

        gameView = new GameView(clientengine);
        gameView.loadBindings(globals.loadConfig("wormbinds")
            .getSubNode("binds"));

        gameView.controller = thegame.controller;

        mScroller = new MouseScroller();
        mScroller.add(gameView);
        add(mScroller);
        add(mGui);

        //start at level center
        mScroller.scrollCenterOn(thegame.gamelevel.offset
            + thegame.gamelevel.size/2, true);

        return true;
    }

    bool unloadGui() {
        //log("unloadGui");
        if (mGameGuiOpened) {
            assert(gameView !is null);
            gameView.controller = null;
            mScroller.clear();
            gameView = null;
            mGui = null;

            mGameGuiOpened = false;
        }

        return true;
    }

    void gameLoaded(Loader sender) {
        //thegame = mGameLoader.thegame;
        thegame.gameTime.resetTime;
        //yyy?? resetTime();
        globals.gameTimeAnimations.resetTime(); //yyy
        //clientengine = mGameLoader.clientengine;
    }
    void gameUnloaded(Loader sender) {
        thegame = null;
        clientengine = null;
    }

    void kill() {
        mGameLoader.unload();
        mCmds.kill();
    }

    override void simulate(Time curTime, Time deltaT) {
        if (mGameLoader.fullyLoaded) {
            if (thegame) {
                thegame.doFrame();
            }

            if (clientengine) {
                clientengine.doFrame();
            }
        }

        if (!mLoadScreen.loading)
            //xxx can't deactivate this from delegate because it would crash
            //the list
            mLoadScreen.remove();
    }

    //game specific commands
    private void registerCommands() {
        mCmds.register(Command("raisewater", &cmdRaiseWater,
            "increase waterline", ["int:water level"]));
        mCmds.register(Command("wind", &cmdSetWind,
            "Change wind speed", ["float:wind speed"]));
        mCmds.register(Command("cameradisable", &cmdCameraDisable,
            "disable game camera"));
        mCmds.register(Command("detail", &cmdDetail,
            "switch detail level", ["int?:detail level (if not given: cycle)"]));
        mCmds.register(Command("slow", &cmdSlow, "set slowdown",
            ["float:slow down",
             "text?:ani or game"]));
        mCmds.register(Command("pause", &cmdPause, "pause"));
        mCmds.register(Command("weapon", &cmdWeapon,
            "Debug: Select a weapon by id", ["text:Weapon ID"]));
    }

    private void cmdWeapon(MyBox[] args, Output write) {
        char[] wid = args[0].unboxMaybe!(char[])("");
        gameifc.controller.selectWeapon(wid);
    }

    private void cmdCameraDisable(MyBox[] args, Output write) {
        //if (gameView)
          //  gameView.view.setCameraFocus(null);
    }

    private void cmdDetail(MyBox[] args, Output write) {
        if (!clientengine)
            return;
        int c = args[0].unboxMaybe!(int)(-1);
        clientengine.detailLevel = c >= 0 ? c : clientengine.detailLevel + 1;
        write.writefln("set detailLevel to %s", clientengine.detailLevel);
    }

    private void cmdSetWind(MyBox[] args, Output write) {
        gameadmin.setWindSpeed(args[0].unbox!(float)());
    }

    private void cmdRaiseWater(MyBox[] args, Output write) {
        gameadmin.raiseWater(args[0].unbox!(int)());
    }

    //slow time <whatever>
    //whatever can be "game", "ani" or left out
    private void cmdSlow(MyBox[] args, Output write) {
        bool setgame, setani;
        switch (args[1].unboxMaybe!(char[])) {
            case "game": setgame = true; break;
            case "ani": setani = true; break;
            default:
                setgame = setani = true;
        }
        float val = args[0].unbox!(float);
        float g = setgame ? val : gameifc.slowDown;
        float a = setani ? val : globals.gameTimeAnimations.slowDown;
        write.writefln("set slowdown: game=%s animations=%s", g, a);
        gameadmin.setSlowDown(g);
        clientengine.engineTime.slowDown = g;
        globals.gameTimeAnimations.slowDown = a;
    }

    private void cmdPause(MyBox[], Output) {
        gamePaused = !gamePaused;
        globals.gameTimeAnimations.paused = !globals.gameTimeAnimations.paused;
    }
}
