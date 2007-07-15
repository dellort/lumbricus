module game.gametask;

import common.common;
import common.task;
import framework.commandline : CommandBucket, Command;
import game.gui.loadingscreen;
import game.gui.gameframe;
import game.clientengine;
import game.loader;
import game.gamepublic;
import game.gui.gameview;
import game.game;
import levelgen.level;
import levelgen.generator;
import utils.mybox;
import utils.output;
import utils.time;
import utils.vector2;
import utils.log;
import utils.configfile;

//these imports register classes in a factory on module initialization
import game.projectile;
import game.special_weapon;

class GameTask : Task {
    private {
        GameConfig mGameConfig;
        GameEngine mServerEngine;
        GameEnginePublic mGame;
        GameEngineAdmin mGameAdmin;
        ClientGameEngine mClientEngine;

        GameFrame mWindow;

        LoadingScreen mLoadScreen;
        Loader mGameLoader;

        CommandBucket mCmds;
    }

    //just for the paused-command?
    private bool gamePaused() {
        return mGame.paused;
    }
    private void gamePaused(bool set) {
        mGameAdmin.setPaused(set);
        mClientEngine.engineTime.paused = set;
    }

    //not happy with this; but who cares
    //this _really_ should be considered to be a debugging features
    //(to use it from the factory)
    //use the other constructor and pass it a useful GameConfig
    this(TaskManager tm) {
        super(tm);
        initGame(loadGameConfig(globals.anyConfig.getSubNode("newgame")));
    }

    //start a game
    this(TaskManager tm, GameConfig cfg) {
        super(tm);
        initGame(cfg);
    }

    //start game intialization
    //it's not clear when initialization is finished (but it shows a loader gui)
    private void initGame(GameConfig cfg) {
        mGameConfig = cfg;

        mCmds = new CommandBucket();
        registerCommands();
        mCmds.bind(globals.cmdLine);

        mLoadScreen = new LoadingScreen();
        mLoadScreen.zorder = 10;
        manager.guiMain.mainFrame.add(mLoadScreen);

        mGameLoader = new Loader();
        mGameLoader.registerChunk(&initGameEngine);
        mGameLoader.registerChunk(&initClientEngine);
        mGameLoader.registerChunk(&initGameGui);
        mGameLoader.onFinish = &gameLoaded;

        //creaton of this frame -> start new game
        mLoadScreen.startLoad(mGameLoader);
    }

    private void unloadGame() {
        //log("unloadGame");
        if (mServerEngine) {
            mServerEngine.kill();
            mServerEngine = null;
        }
        if (mClientEngine) {
            mClientEngine.kill();
            mClientEngine = null;
        }
    }

    private bool initGameGui() {
        mWindow = new GameFrame(mClientEngine);
        manager.guiMain.mainFrame.add(mWindow);

        return true;
    }

    private bool initGameEngine() {
        //log("initGameEngine");
        mServerEngine = new GameEngine(mGameConfig);
        mServerEngine.gameTime.paused = true;
        mGame = mServerEngine;
        mGameAdmin = mServerEngine.requestAdmin();
        return true;
    }

    private bool initClientEngine() {
        //log("initClientEngine");
        mClientEngine = new ClientGameEngine(mServerEngine);
        return true;
    }

    private void gameLoaded(Loader sender) {
        //idea: start in paused mode, release poause at end to not need to
        //      reset the gametime
        mServerEngine.gameTime.paused = false;
        //xxx! this is evul!
        globals.gameTimeAnimations.resetTime();
    }

    override protected void onKill() {
        //smash it up (forced kill; unforced goes into terminate())
        unloadGame();
        mCmds.kill();
        mWindow.remove(); //from GUI
    }

    override protected void onFrame() {
        if (mGameLoader.fullyLoaded) {
            if (mServerEngine) {
                mServerEngine.doFrame();
            }

            if (mClientEngine) {
                mClientEngine.doFrame();
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
        //yyy mGame.controller.selectWeapon(wid);
    }

    private void cmdCameraDisable(MyBox[] args, Output write) {
        //if (gameView)
          //  gameView.view.setCameraFocus(null);
    }

    private void cmdDetail(MyBox[] args, Output write) {
        if (!mClientEngine)
            return;
        int c = args[0].unboxMaybe!(int)(-1);
        mClientEngine.detailLevel = c >= 0 ? c : mClientEngine.detailLevel + 1;
        write.writefln("set detailLevel to %s", mClientEngine.detailLevel);
    }

    private void cmdSetWind(MyBox[] args, Output write) {
        mGameAdmin.setWindSpeed(args[0].unbox!(float)());
    }

    private void cmdRaiseWater(MyBox[] args, Output write) {
        mGameAdmin.raiseWater(args[0].unbox!(int)());
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
        float g = setgame ? val : mGame.slowDown;
        float a = setani ? val : globals.gameTimeAnimations.slowDown;
        write.writefln("set slowdown: game=%s animations=%s", g, a);
        mGameAdmin.setSlowDown(g);
        mClientEngine.engineTime.slowDown = g;
        globals.gameTimeAnimations.slowDown = a;
    }

    private void cmdPause(MyBox[], Output) {
        gamePaused = !gamePaused;
        globals.gameTimeAnimations.paused = !globals.gameTimeAnimations.paused;
    }

    static this() {
        TaskFactory.register!(typeof(this))("game");
    }
}

//xxx doesn't really belong here
//not to be called by GameTask; instead, anyone who wants to start a game can
//call this to the params out from a configfile
//GameTask shoiuld not be responsible to choose any game configuration for you
GameConfig loadGameConfig(ConfigNode mConfig, Level level = null) {
    //log("loadConfig");
    GameConfig cfg;
    if (level) {
        cfg.level = level;
    } else {
        bool load = mConfig.selectValueFrom("level", ["generate", "load"]) == 1;
        auto x = new LevelGenerator();
        if (load) {
            cfg.level =
                x.renderSavedLevel(globals.loadConfig(mConfig["level_load"]));
        } else {
            LevelTemplate templ =
                x.findRandomTemplate(mConfig["level_template"]);
            LevelTheme gfx = x.findRandomGfx(mConfig["level_gfx"]);

            cfg.level = generateAndSaveLevel(x, templ, null, gfx);
        }
    }
    auto teamconf = globals.loadConfig("teams");
    cfg.teams = teamconf.getSubNode("teams");

    auto gamemodecfg = globals.loadConfig("gamemode");
    auto modes = gamemodecfg.getSubNode("modes");
    cfg.gamemode = modes.getSubNode(
        mConfig.getStringValue("gamemode",""));
    cfg.weapons = gamemodecfg.getSubNode("weapon_sets");

    return cfg;
}

//xxx doesn't really belong here
//generate level and save generated level as lastlevel.conf
//any param other than gen can be null
Level generateAndSaveLevel(LevelGenerator gen, LevelTemplate templ,
    LevelGeometry geo, LevelTheme gfx)
{
    templ = templ ? templ : gen.findRandomTemplate("");
    gfx = gfx ? gfx : gen.findRandomGfx("");
    //be so friendly and save it
    ConfigNode saveto = new ConfigNode();
    auto res = gen.renderLevelGeometry(templ, geo, gfx, saveto);
    saveConfig(saveto, "lastlevel.conf");
    return res;
}
