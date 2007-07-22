module game.gametask;

import common.common;
import common.task;
import framework.commandline;
import framework.framework;
import framework.filesystem;
import game.gui.loadingscreen;
import game.gui.gameframe;
import game.clientengine;
import game.loader;
import game.gamepublic;
import game.gui.gameview;
import game.game;
import game.sprite;
import game.crate;
import gui.widget;
import levelgen.level;
import levelgen.generator;
import utils.mybox;
import utils.output;
import utils.time;
import utils.vector2;
import utils.log;
import utils.configfile;

import std.stream;
import std.outbuffer;

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

        Spacer mFadeOut;
        const Color cFadeStart = {0,0,0,0};
        const Color cFadeEnd = {0,0,0,1};
        const cFadeDurationMs = 3000;
        Time mFadeStartTime;
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

        //start at level center
        mWindow.scrollToCenter();
    }

    override protected void onKill() {
        //smash it up (forced kill; unforced goes into terminate())
        unloadGame();
        mCmds.kill();
        mWindow.remove(); //from GUI
    }

    override void terminate() {
        if (!mFadeOut) {
            mFadeOut = new Spacer();
            mFadeOut.color = cFadeStart;
            mFadeOut.enableAlpha = true;
            manager.guiMain.mainFrame.add(mFadeOut);
            mFadeStartTime = timeCurrentTime;
        }
    }

    private void doFade() {
        if (!mFadeOut)
            return;
        int mstime = (timeCurrentTime - mFadeStartTime).msecs;
        if (mstime > cFadeDurationMs) {
            //end of fade
            mFadeOut.remove();
            kill();
        } else {
            float scale = 1.0f*mstime/cFadeDurationMs;
            mFadeOut.color = cFadeStart + (cFadeEnd - cFadeStart) * scale;
        }
    }

    override protected void onFrame() {
        if (mGameLoader.fullyLoaded) {
            if (mServerEngine) {
                mServerEngine.doFrame();
            }

            if (mClientEngine) {
                mClientEngine.doFrame();

                //maybe
                if (mClientEngine.gameEnded)
                    terminate();
            }
        }

        if (!mLoadScreen.loading)
            //xxx can't deactivate this from delegate because it would crash
            //the list
            mLoadScreen.remove();

        //he-he
        doFade();
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
        mCmds.register(Command("saveleveltga", &cmdSafeLevelTGA, "dump TGA",
            ["text:filename"]));
        mCmds.register(Command("crate_test", &cmdCrateTest, "drop a crate"));
    }

    private void cmdSafeLevelTGA(MyBox[] args, Output write) {
        char[] filename = args[0].unbox!(char[])();
        Stream s = getFramework.fs.open(filename, FileMode.OutNew);
        saveSurfaceToTGA(mServerEngine.gamelevel.image, s);
        s.close();
    }

    private void cmdWeapon(MyBox[] args, Output write) {
        char[] wid = args[0].unboxMaybe!(char[])("");
        write.writefln("xxx reimplement if you want this");
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

    private void cmdCrateTest(MyBox[] args, Output write) {
        Vector2f from, to;
        float water = mServerEngine.waterOffset - 10;
        if (!mServerEngine.placeObject(water, 10, from, to, 5)) {
            write.writefln("couldn't find a safe drop-position");
            return;
        }
        GObjectSprite s = mServerEngine.createSprite("crate");
        CrateSprite crate = cast(CrateSprite)s;
        assert(!!crate);
        //put stuffies into it
        Object esel = mServerEngine.findWeaponClass("esel");
        crate.stuffies = [esel, esel];
        //actually start it
        crate.setPos(from);
        crate.active = true;
        write.writefln("drop %s -> %s", from, to);
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
        int what = mConfig.selectValueFrom("level",
            ["generate", "load", "loadbmp"]);
        auto x = new LevelGenerator();
        if (what == 0) {
            cfg.level =
                x.renderSavedLevel(globals.loadConfig(mConfig["level_load"]));
        } else if (what == 1) {
            LevelTemplate templ =
                x.findRandomTemplate(mConfig["level_template"]);
            LevelTheme gfx = x.findRandomGfx(mConfig["level_gfx"]);

            cfg.level = generateAndSaveLevel(x, templ, null, gfx);
        } else if (what == 2) {
            auto bmp = globals.loadGraphic(mConfig["level_load_bitmap"]);
            auto gfx = mConfig["level_gfx"];
            cfg.level = x.generateFromImage(bmp, false, gfx);
        } else {
            //wrong string in configfile or internal error
            throw new Exception("noes noes noes!");
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

//dirty hacky lib to dump a surface to a file
//as far as I've seen we're not linked to any library which can write images
void saveSurfaceToTGA(Surface s, OutputStream stream) {
    OutBuffer to = new OutBuffer;
    try {
        void* pvdata;
        uint pitch;
        s.lockPixelsRGBA32(pvdata, pitch);
        ubyte b;
        b = 0;
        to.write(b); //image id, whatever
        to.write(b); //no palette
        b = 2;
        to.write(b); //uncompressed 24 bit RGB
        short sh;
        sh = 0;
        to.write(sh); //skip plalette
        to.write(sh);
        b = 0;
        to.write(b);
        to.write(sh); //x/y coordinates
        to.write(sh);
        sh = s.size.x; to.write(sh); //w/h
        sh = s.size.y; to.write(sh);
        b = 24;
        to.write(b);
        b = 0;
        to.write(b); //??
        //dump picture data as 24 bbp
        //TGA seems to be upside down
        for (int y = s.size.y-1; y >= 0; y--) {
            uint* data = cast(uint*)(pvdata+pitch*y);
            for (int x = 0; x < s.size.x; x++) {
                //trivial alpha check... and if so, write a colorkey
                //this, of course, is a dirty hack
                if (*data >> 24) {
                    b = *data; to.write(b);
                    b = *data >> 8; to.write(b);
                    b = *data >> 16; to.write(b);
                } else {
                    b = 255; to.write(b);
                    b = 0; to.write(b);
                    b = 255; to.write(b);
                }
                data++;
            }
        }
    } finally {
        s.unlockPixels();
    }
    stream.write(to.toBytes);
}
