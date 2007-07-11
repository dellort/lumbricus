module game.gui.gameframe;
import gui.container;
import gui.widget;
import game.gui.loadingscreen;
import game.gui.gametimer;
import game.gui.windmeter;
import game.gui.preparedisplay;
import gui.messageviewer;
import gui.mousescroller;
import game.common;
import game.scene;
import game.game;
import game.visual;
import game.clientengine;
import game.loader;
import game.loader_game;
import game.gui.gameview;
import framework.commandline : CommandBucket, Command;
import utils.mybox;
import utils.output;
import utils.time;
import utils.vector2;
import utils.log;
import levelgen.generator;
import genlevel = levelgen.generator;
import utils.configfile;

//xxx include so that module constructors (static this) are actually called
import game.projectile;
import game.special_weapon;

class GameFrame : SimpleContainer {
    GameEngine thegame;
    ClientGameEngine clientengine;
    /*private*/ GameLoader mGameLoader;
    /+private+/ GameConfig mGameConfig;
    private LoadingScreen mLoadScreen;
    private bool mGameGuiOpened;

    //temporary between constructor and loadConfig...
    private LevelGeometry mGeo;

    private CommandBucket mCmds;

    private MouseScroller mScroller;
    private Container mGui;
    GameView gameView;

    bool gamePaused() {
        return thegame.gameTime.paused;
    }
    void gamePaused(bool set) {
        thegame.gameTime.paused = set;
        clientengine.engineTime.paused = set;
    }

    this(LevelGeometry geo = null) {
        super();
        mGeo = geo;

        mCmds = new CommandBucket();
        registerCommands();
        mCmds.bind(globals.cmdLine);

        mLoadScreen = new LoadingScreen();
        add(mLoadScreen);

        mLoadScreen.zorder = 10;

        mGameLoader = new GameLoader(globals.anyConfig.getSubNode("newgame"),
            this);
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

        return true;
    }

    bool initClientEngine() {
        //log("initClientEngine");
        clientengine = new ClientGameEngine(thegame);

        return true;
    }

    bool loadConfig() {
        auto mConfig = mGameLoader.mConfig;
        //log("loadConfig");
        auto x = new genlevel.LevelGenerator();
        GameConfig cfg;
        //hack: ignore what's in the configfile and generate a random level
        //      with the geometry from the previewer...
        //old behaviour still works with geo==null
        bool load = mConfig.selectValueFrom("level", ["generate", "load"]) == 1;
        if (!mGeo && load) {
            cfg.level =
                x.renderSavedLevel(globals.loadConfig(mConfig["level_load"]));
        } else {
            genlevel.LevelTemplate templ =
                x.findRandomTemplate(mConfig["level_template"]);
            genlevel.LevelTheme gfx = x.findRandomGfx(mConfig["level_gfx"]);

            //be so friendly and save it
            ConfigNode saveto = new ConfigNode();
            cfg.level = x.renderLevelGeometry(templ, mGeo, gfx, saveto);
            saveConfig(saveto, "lastlevel.conf");
        }
        auto teamconf = globals.loadConfig("teams");
        cfg.teams = teamconf.getSubNode("teams");

        auto gamemodecfg = globals.loadConfig("gamemode");
        auto modes = gamemodecfg.getSubNode("modes");
        cfg.gamemode = modes.getSubNode(
            mConfig.getStringValue("gamemode",""));
        cfg.weapons = gamemodecfg.getSubNode("weapon_sets");

        mGameConfig = cfg;

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
        thegame.controller.messageIdleCb = &msg.idle;

        gameView = new GameView(clientengine);
        gameView.loadBindings(globals.loadConfig("wormbinds")
            .getSubNode("binds"));

        gameView.controller = thegame.controller;

        mScroller = new MouseScroller();
        mScroller.add(gameView);
        add(mScroller);
        add(mGui);

        //start at level center
        //gameView.view.scrollCenterOn(thegame.gamelevel.offset
          //yyy  + thegame.gamelevel.size/2, true);

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
            globals.gameTimeAnimations.update();

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
        thegame.windSpeed = args[0].unbox!(float)();
    }

    private void cmdRaiseWater(MyBox[] args, Output write) {
        thegame.raiseWater(args[0].unbox!(int)());
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
        float g = setgame ? val : thegame.gameTime.slowDown;
        float a = setani ? val : globals.gameTimeAnimations.slowDown;
        write.writefln("set slowdown: game=%s animations=%s", g, a);
        thegame.gameTime.slowDown = g;
        clientengine.engineTime.slowDown = g;
        globals.gameTimeAnimations.slowDown = a;
    }

    private void cmdPause(MyBox[], Output) {
        gamePaused = !gamePaused;
        globals.gameTimeAnimations.paused = !globals.gameTimeAnimations.paused;
    }
}
