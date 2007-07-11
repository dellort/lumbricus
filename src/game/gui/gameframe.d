module gui.gameframe;
import gui.frame;
import gui.gui;
import gui.guiobject;
import gui.loadingscreen;
import gui.gametimer;
import gui.windmeter;
import gui.preparedisplay;
import gui.messageviewer;
import gui.layout;
import game.common;
import game.scene;
import game.game;
import game.visual;
import game.clientengine;
import game.loader;
import game.loader_game;
import gui.gameview;
import framework.commandline : CommandBucket, Command;
import utils.mybox;
import utils.output;
import utils.time;
import utils.vector2;
import levelgen.generator;
import genlevel = levelgen.generator;
import utils.configfile;

//xxx include so that module constructors (static this) are actually called
import game.projectile;
import game.special_weapon;

class GameFrame : GuiFrame {
    GameEngine thegame;
    ClientGameEngine clientengine;
    /*private*/ GameLoader mGameLoader;
    /+private+/ GameConfig mGameConfig;
    private LoadingScreen mLoadScreen;
    private bool mGameGuiOpened;
    private GuiLayouterAlign mLayoutAlign;
    private GuiLayouterNull mLayoutClient;

    //temporary between constructor and loadConfig...
    private LevelGeometry mGeo;

    private CommandBucket mCmds;

    GameView gameView;

    bool gamePaused() {
        return thegame.gameTime.paused;
    }
    void gamePaused(bool set) {
        thegame.gameTime.paused = set;
        clientengine.engineTime.paused = set;
    }

    this(LevelGeometry geo = null) {
        mGeo = geo;

        virtualFrame = true;

        mCmds = new CommandBucket();
        registerCommands();
        mCmds.bind(globals.cmdLine);

        mLoadScreen = new LoadingScreen();
        //meh...
        auto lay = new GuiLayouterNull();
        lay.frame = this;
        addLayouter(lay);
        lay.add(mLoadScreen);

        mLoadScreen.zorder = GUIZOrder.Loading;

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
        //log("initializeGameGui");
        mGameGuiOpened = true;

        mLayoutAlign = new GuiLayouterAlign();
        addLayouter(mLayoutAlign);
        mLayoutClient = new GuiLayouterNull();
        addLayouter(mLayoutClient);

        mLayoutAlign.add(new WindMeter(clientengine), 1, 1, Vector2i(10, 10));
        mLayoutAlign.add(new GameTimer(clientengine), -1, 1, Vector2i(5,5));

        mLayoutClient.add(new PrepareDisplay(clientengine));
        auto msg = new MessageViewer();
        mLayoutClient.add(msg);

        thegame.controller.messageCb = &msg.addMessage;
        thegame.controller.messageIdleCb = &msg.idle;

        gameView = new GameView(clientengine);
        gameView.zorder = GUIZOrder.Game;
        gameView.loadBindings(globals.loadConfig("wormbinds")
            .getSubNode("binds"));
        mLayoutClient.add(gameView);
        //gameView.zorder = GUIZOrder.Game;

        gameView.controller = thegame.controller;
        gameView.gamescene = clientengine.scene;

        //start at level center
        gameView.view.scrollCenterOn(thegame.gamelevel.offset
            + thegame.gamelevel.size/2, true);

        return true;
    }

    bool unloadGui() {
        //log("unloadGui");
        if (mGameGuiOpened) {
            assert(gameView !is null);
            gameView.gamescene = null;
            gameView.controller = null;
            remove();
            gameView = null;

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

    //xxx: rethink
    protected void remove() {
        mGameLoader.unload();
        mCmds.kill();
        super.remove();
    }

    void simulate(Time curTime, Time deltaT) {
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
        if (gameView)
            gameView.view.setCameraFocus(null);
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
