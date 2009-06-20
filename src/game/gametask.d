module game.gametask;

import common.common;
import common.task;
import common.loadsave;
import common.resources;
import common.resset;
import framework.commandline;
import framework.framework;
import framework.filesystem;
import framework.i18n;
import framework.timesource;
import game.gui.loadingscreen;
import game.hud.gameframe;
import game.hud.teaminfo;
import game.hud.gameview;
import game.clientengine;
import game.loader;
import game.gamepublic;
import game.gameshell;
import game.sequence;
import game.game;
import game.controller;
import game.gfxset;
import game.sprite;
import game.crate;
import game.gobject;
import game.setup;
import game.levelgen.landscape;
import game.levelgen.level;
import game.levelgen.generator;
import game.levelgen.renderer;
//--> following 2 imports are not actually needed, but avoid linker errors
//    on windows with game.gui.leveledit disabled in lumbricus.d
import game.levelgen.placeobjects;
import game.levelgen.genrandom;
//<--
import gui.container;
import gui.label;
import gui.tablecontainer;
import gui.widget;
import gui.wm;
import gui.button;
import gui.dropdownlist;
import gui.boxcontainer;
import gui.list;
import utils.array;
import utils.misc;
import utils.mybox;
import utils.output;
import utils.rect2;
import utils.time;
import utils.vector2;
import utils.log;
import utils.configfile;
import utils.random;
import utils.reflection;
import utils.serialize;
import utils.path;
import utils.archive;
import utils.snapshot;
import utils.perf;

import game.serialize_register : initGameSerialization;

import stdx.stream;

//these imports register classes in a factory on module initialization
import game.weapon.projectile;
import game.weapon.special_weapon;
import game.weapon.rope;
import game.weapon.jetpack;
import game.weapon.drill;
import game.weapon.ray;
import game.weapon.spawn;
import game.weapon.napalm;
import game.weapon.melee;
//import game.weapon.luaweapon;
import game.gamemodes.turnbased;
import game.gamemodes.mdebug;
import game.gamemodes.realtime;
import game.controller_plugins;

/+

//this is a test: it explodes the landscape graphic into several smaller ones
Level fuzzleLevel(Level level) {
    return level; //comment out for testing

    const cTile = 512;
    const cSpace = 4; //even more for testing only
    const cTileSize = cTile + cSpace;

    auto rlevel = level.copy();
    //remove all landscapes from new level
    rlevel.objects = arrayFilter(rlevel.objects, (LevelItem i) {
        return !cast(LevelLandscape)i;
    });
    foreach (o; level.objects) {
        if (auto ls = cast(LevelLandscape)o) {
            auto sx = (ls.landscape.size.x + cTile - 1) / cTile;
            auto sy = (ls.landscape.size.y + cTile - 1) / cTile;
            for (int y = 0; y < sy; y++) {
                for (int x = 0; x < sx; x++) {
                    auto nls = castStrict!(LevelLandscape)(ls.copy);
                    nls.name = myformat("{}_{}_{}", nls.name, x, y);
                    auto offs = Vector2i(x, y) * cTileSize;
                    auto soffs = Vector2i(x, y) * cTile;
                    nls.position += offs;
                    nls.landscape = ls.landscape.
                        cutOutRect(Rect2i(Vector2i(cTile))+soffs);
                    nls.owner = rlevel;
                    rlevel.objects ~= nls;
                }
            }
        }
    }

    return rlevel;
}

+/

class GameTask : StatefulTask {
    private {
        GameShell mGameShell; //can be null, if a client in a network game!
        GameLoader mGameLoader; //creates a GameShell
        GameEnginePublic mGame;
        ClientGameEngine mClientEngine;
        ClientControl mControl;
        GameInfo mGameInfo;
        SimpleNetConnection mConnection;

        GameFrame mGameFrame;
        SimpleContainer mWindow;

        LoadingScreen mLoadScreen;
        Loader mGUIGameLoader;
        Resources.Preloader mResPreloader;

        CommandBucket mCmds;

        Spacer mFadeOut;
        const Color cFadeStart = {0,0,0,0};
        const Color cFadeEnd = {0,0,0,1};
        const cFadeDurationMs = 3000;
        Time mFadeStartTime;

        bool mDelayedFirstFrame; //draw screen before loading first chunk

        //temporary when loading a game
        SerializeInConfig mSaveGame;
        Vector2i mSavedViewPosition;
        bool mSavedSetViewPosition;
        ConfigNode mGamePersist;
    }

    //just for the paused-command?
    private bool gamePaused() {
        return mGameShell.paused;
    }
    private void gamePaused(bool set) {
        mControl.executeCommand(myformat("set_pause {}", set));
    }

    //not happy with this; but who cares
    //this _really_ should be considered to be a debugging features
    //(to use it from the factory)
    //use the other constructor and pass it a useful GameConfig
    this(TaskManager tm, char[] args = "") {
        super(tm);

        createWindow();

        //sorry for this hack... definitely needs to be cleaned up
        ConfigNode node = gConf.loadConfig("newgame");
        initGame(loadGameConfig(node));
    }

    //start a game
    this(TaskManager tm, GameConfig cfg) {
        super(tm);

        createWindow();
        initGame(cfg);
    }

    this(TaskManager tm, TarArchive savedState) {
        super(tm);

        createWindow();
        initFromSave(savedState);
    }

    this(TaskManager tm, GameLoader loader, SimpleNetConnection con) {
        super(tm);

        mGameLoader = loader;
        mConnection = con;
        mConnection.onGameStart = &netGameStart;

        createWindow();
        doInit();
    }

    private void createWindow() {
        mWindow = new SimpleContainer();
        auto wnd = gWindowManager.createWindowFullscreen(this, mWindow,
            "lumbricus");
        //background is mostly invisible, except when loading and at low
        //detail levels (where the background isn't completely overdrawn)
        auto props = wnd.properties;
        props.background = Color(0); //black :)
        wnd.properties = props;

        mCmds = new CommandBucket();
        registerCommands();
        mCmds.bind(globals.cmdLine);
    }

    private void netGameStart(SimpleNetConnection sender, ClientControl control)
    {
        mControl = control;
    }

    //start game intialization
    //it's not clear when initialization is finished (but it shows a loader gui)
    private void initGame(GameConfig cfg) {
        mGameLoader = GameLoader.CreateNewGame(cfg);
        doInit();
    }

    private void initFromSave(TarArchive tehfile) {
        ZReader reader = tehfile.openReadStream("gui.conf");
        ConfigNode guiconf = reader.readConfigFile();
        reader.close();

        mSavedViewPosition = guiconf.getValue!(Vector2i)("viewpos");
        mSavedSetViewPosition = true;

        mGameLoader = GameLoader.CreateFromSavegame(tehfile);
        doInit();
    }

    void doInit() {
        mLoadScreen = new LoadingScreen();
        mLoadScreen.zorder = 10;
        assert (!!mWindow);
        mWindow.add(mLoadScreen);

        auto load_txt = localeRoot.bindNamespace("loading.game");
        char[][] chunks;

        void addChunk(LoadChunkDg cb, char[] txt_id) {
            chunks ~= load_txt(txt_id);
            mGUIGameLoader.registerChunk(cb);
        }

        mGUIGameLoader = new Loader();
        addChunk(&initLoadResources, "resources");
        addChunk(&initGameEngine, "gameengine");
        addChunk(&initClientEngine, "clientengine");
        addChunk(&initGameGui, "gui");
        mGUIGameLoader.onFinish = &gameLoaded;

        mLoadScreen.setPrimaryChunks(chunks);
    }

    private void unloadGame() {
        //log("unloadGame");
        /+if (mServerEngine) {
            mServerEngine.kill();
            mServerEngine = null;
        }+/
        mGameShell = null;
        if (mClientEngine) {
            mClientEngine.kill();
            mClientEngine = null;
        }
        mGame = null;
        mControl = null;
    }

    private bool initGameGui() {
        mGameInfo = new GameInfo(mClientEngine, mControl);
        mGameInfo.connection = mConnection;
        mGameFrame = new GameFrame(mGameInfo);
        mWindow.add(mGameFrame);
        if (mSavedSetViewPosition) {
            mSavedSetViewPosition = false;
            mGameFrame.setPosition(mSavedViewPosition);
        }

        return true;
    }

    private bool initGameEngine() {
        //log("initGameEngine");
        if (!mGameShell) {
            mGameShell = mGameLoader.finish();
            mGameShell.OnRestoreGuiAfterSnapshot = &guiRestoreSnapshot;
            mGame = mGameShell.serverEngine;
        }
        if (mConnection) {
            if (!mControl)
                return false;
        }

        if (mGameShell && !mControl) {
            //xxx (well, you know)
            mControl = new GameControl(mGameShell);
        }

        return true;
    }

    private bool initClientEngine() {
        //log("initClientEngine");
        mClientEngine = new ClientGameEngine(mGame);
        return true;
    }

    //periodically called by loader (stopped when we return true)
    private bool initLoadResources() {
        if (!mGameLoader)
            return true;
        Resources.Preloader preload = mGameLoader.resPreloader;
        if (!preload)
            return true;
        //(actually would only be needed for initialization)
        mLoadScreen.secondaryActive = true;
        mLoadScreen.secondaryCount = preload.totalCount();
        mLoadScreen.secondaryPos = preload.loadedCount();
        //the use in returning after some time is to redraw the screen
        preload.progressTimed(timeMsecs(100));
        if (!preload.done) {
            return false;
        } else {
            mLoadScreen.secondaryActive = false;
            return true;
        }
    }

    private void gameLoaded(Loader sender) {
        //idea: start in paused mode, release poause at end to not need to
        //      reset the gametime
        //if (mServerEngine)
          //  mServerEngine.start();
        //a small wtf: why does client engine have its own time??
        mClientEngine.start();

        //remove this, so the game becomes visible
        mLoadScreen.remove();
    }

    private void unloadAndReset() {
        unloadGame();
        if (mWindow) mWindow.remove();
        mWindow = null;
        if (mLoadScreen) mLoadScreen.remove();
        mLoadScreen = null;
        mGUIGameLoader = null;
        mGameLoader = null;
        mResPreloader = null;
        mSaveGame = null;
        mControl = null;
    }

    override protected void onKill() {
        //smash it up (forced kill; unforced goes into terminate())
        unloadAndReset();
        mCmds.kill();
        if (mGameFrame)
            mGameFrame.remove(); //from GUI
        if (mLoadScreen)
            mLoadScreen.remove();
    }

    override void terminate() {
        //this is called when the window is closed
        //go boom
        kill();
    }

    void terminateWithFadeOut() {
        if (!mFadeOut) {
            mFadeOut = new Spacer();
            mFadeOut.color = cFadeStart;
            mWindow.add(mFadeOut);
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
            mFadeOut = null;
            kill();
        } else {
            float scale = 1.0f*mstime/cFadeDurationMs;
            mFadeOut.color = cFadeStart + (cFadeEnd - cFadeStart) * scale;
        }
    }

    override protected void onFrame() {
        if (mGUIGameLoader.fullyLoaded) {
            if (mGameShell) {
                mGameShell.frame();
                mGameInfo.replayRemain = mGameShell.replayRemain;
                if (mGameShell.terminated)
                    kill();
            }
            if (mClientEngine) {
                mClientEngine.doFrame();
                //synchronize paused state
                //still hacky, but better than GCD
                if (mGameShell)
                    mClientEngine.paused = mGameShell.paused;

                //maybe
                if (mGame.logic.gameEnded) {
                    assert(!!mGameShell && !!mGameShell.serverEngine);
                    mGamePersist = mGameShell.serverEngine.persistentState;
                    terminateWithFadeOut();
                }
            }
        } else {
            if (mDelayedFirstFrame) {
                mGUIGameLoader.loadStep();
            }
            mDelayedFirstFrame = true;
            //update GUI (Loader/LoadingScreen aren't connected anymore)
            mLoadScreen.primaryPos = mGUIGameLoader.currentChunk;
        }

        //he-he
        doFade();
    }

    //implements StatefulTask
    override void saveState(TarArchive tehfile) {
        if (!mGameShell)
            throw new Exception("can't save network game as client");

        mGameShell.saveGame(tehfile);

        auto guiconf = new ConfigNode();
        guiconf.setValue!(Vector2i)("viewpos", mGameFrame.getPosition());
        ZWriter zwriter = tehfile.openWriteStream("gui.conf");
        zwriter.writeConfigFile(guiconf);
        zwriter.close();
    }

    //game specific commands
    private void registerCommands() {
        if (!mConnection) {
            mCmds.register(Command("slow", &cmdSlow, "set slowdown",
                ["float:slow down",
                 "text?:ani or game"]));
            mCmds.register(Command("pause", &cmdPause, "pause"));
            mCmds.register(Command("ser_dump", &cmdSerDump,
                "serialiation dump"));
            mCmds.register(Command("snap", &cmdSnapTest, "snapshot test",
                ["int:1=store, 2=load, 3=store+load"]));
            mCmds.register(Command("replay", &cmdReplay,
                "start recording or replay from last snapshot",
                ["text?:any text to start recording"]));
        }
        mCmds.register(Command("saveleveltga", &cmdSafeLevelTGA, "dump TGA",
            ["text:filename"]));
        mCmds.register(Command("show_collide", &cmdShowCollide, "show collision"
            " bitmaps"));
        mCmds.register(Command("server", &cmdExecServer,
            "Run a command on the server", ["text...:command"]));
    }

    class ShowCollide : Container {
        class Cell : SimpleContainer {
            bool bla, blu;
            override void onDraw(Canvas c) {
                if (bla || blu) {
                    Color cl = bla ? Color(0.7) : Color(0.9);
                    c.drawFilledRect(widgetBounds, cl);
                }
                c.drawRect(widgetBounds, Color(0));
                super.onDraw(c);
            }
        }
        this() {
            auto ph = mGameShell.serverEngine.physicworld;
            auto types = ph.collide.collisionTypes;
            auto table = new TableContainer(types.length+1, types.length+1,
                Vector2i(2));
            void addc(int x, int y, Label l) {
                Cell c = new Cell();
                c.bla = (y>0) && (x > y);
                c.blu = (y>0) && (x==y);
                l.font = gFramework.getFont("normal");
                c.add(l, WidgetLayout.Aligned(0, 0, Vector2i(1)));
                table.add(c, x, y);
            }
            //column/row headers
            for (int n = 0; n < types.length; n++) {
                auto l = new Label();
                l.text = myformat("{}: {}", n, types[n].name);
                addc(0, n+1, l);
                l = new Label();
                l.text = myformat("{}", n);//types[n].name;
                addc(n+1, 0, l);
            }
            int y = 1;
            foreach (t; types) {
                int x = 1;
                foreach (t2; types) {
                    Label lbl = new Label();
                    if (ph.collide.canCollide(t, t2)) {
                        lbl.image = globals.guiResources.get!(Surface)
                            ("window_close"); //that icon is good enough
                    }
                    addc(x, y, lbl);
                    x++;
                }
                y++;
            }
            addChild(table);
        }
    }

    private void cmdShowCollide(MyBox[] args, Output write) {
        if (!mGameShell)
            return;
        gWindowManager.createWindow(this, new ShowCollide(),
            "Collision matrix");
    }

    private void cmdSafeLevelTGA(MyBox[] args, Output write) {
        if (!mGameShell)
            return;
        char[] filename = args[0].unbox!(char[])();
        Stream s = gFS.open(filename, FileMode.OutNew);
        mGameShell.serverEngine.gameLandscapes[0].image.saveImage(s);
        s.close();
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
        if (setgame) {
            write.writefln("set slowdown: game={}", val);
            mControl.executeCommand(myformat("slow_down {}", val));
        }
        if (setani) {
            write.writefln("set slowdown: client={}", val);
            mClientEngine.setSlowDown(val);
        }
    }

    private void cmdPause(MyBox[], Output) {
        gamePaused = !gamePaused;
    }

    private void cmdExecServer(MyBox[] args, Output write) {
        //send command to the server
        char[] srvCmd = args[0].unbox!(char[]);
        mControl.executeCommand(srvCmd);
    }

    private void cmdSnapTest(MyBox[] args, Output write) {
        if (!mGameShell)
            return;
        int arg = args[0].unbox!(int);
        if (arg & 1) {
            doEngineSnap();
        }
        if (arg & 2) {
            doEngineUnsnap();
        }
    }

    private void cmdReplay(MyBox[] args, Output write) {
        char[] arg = args[0].unboxMaybe!(char[]);
        if (mGameShell.replayMode) {
            mGameShell.replaySkip();
        } else {
            if (arg.length > 0)
                mGameShell.snapForReplay();
            else
                mGameShell.replay();
        }
    }

    GameShell.GameSnap snapshot;

    private void doEngineSnap() {
        mGameShell.doSnapshot(snapshot);
    }

    private void doEngineUnsnap() {
        mGameShell.doUnsnapshot(snapshot);
    }

    private void guiRestoreSnapshot() {
        //important: readd graphics, because they could have changed
        mClientEngine.readd_graphics();
        mGameFrame.gameView.readd_graphics();
    }

    private void cmdSerDump(MyBox[] args, Output write) {
        debug debugDumpTypeInfos(serialize_types);
        //debugDumpClassGraph(serialize_types, mServerEngine);
        //char[] res = dumpGraph(serialize_types, mServerEngine, mExternalObjects);
        //std.file.write("dump_graph.dot", res);
        //ConfigNode cfg = saveGame();
        //gConf.saveConfig(cfg, "savegame.conf");
    }

    ConfigNode gamePersist() {
        return mGamePersist;
    }

    const cSaveId = "lumbricus";

    override char[] saveId() {
        return cSaveId;
    }

    static this() {
        TaskFactory.register!(typeof(this))("game");
        StatefulFactory.register!(typeof(this))(cSaveId);
        initGameSerialization();
    }
}
