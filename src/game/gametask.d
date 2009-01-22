module game.gametask;

import common.common;
import common.task;
import framework.resources;
import framework.resset;
import framework.commandline;
import framework.framework;
import framework.filesystem;
import framework.i18n;
import framework.timesource;
import game.gui.loadingscreen;
import game.gui.gameframe;
import game.gui.teaminfo;
import game.clientengine;
import game.loader;
import game.gamepublic;
import game.sequence;
import game.gui.gameview;
import game.game;
import game.controller;
import game.gfxset;
import game.sprite;
import game.crate;
import game.gobject;
import game.setup;
import game.netclient;
import game.netshared;
import game.netserver;
import game.levelgen.landscape;
import game.levelgen.level;
import game.levelgen.generator;
import game.levelgen.renderer;
import gui.container;
import gui.label;
import gui.tablecontainer;
import gui.widget;
import gui.wm;
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

import stdx.stream;
import str = stdx.string;

//these imports register classes in a factory on module initialization
import game.weapon.projectile;
import game.weapon.special_weapon;
import game.weapon.tools;
import game.weapon.ray;
import game.weapon.spawn;
import game.weapon.napalm;
import game.gamemodes.roundbased;

//initialized by serialize_register.d
Types serialize_types;

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
                    nls.name = str.format("%s_%s_%s", nls.name, x, y);
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

class GameTask : Task {
    private {
        GameConfig mGameConfig;
        GameEngine mServerEngine; //can be null, if a client in a network game!
        GameEnginePublic mGame;
        ClientGameEngine mClientEngine;
        ClientControl mControl;
        GameInfo mGameInfo;
        NetClient mNetClient;
        NetServer mNetServer;
        GfxSet mGfx;

        GameFrame mGameFrame;
        //argh, another step of indirection :/
        SimpleContainer mWindow;

        LoadingScreen mLoadScreen;
        Loader mGameLoader;
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
        RNGState mSavedRandomSeed;
        Time mSavedTime;
        Vector2i mSavedViewPosition;
        bool mSavedSetViewPosition;
    }

    //just for the paused-command?
    private bool gamePaused() {
        return mGame.paused;
    }
    private void gamePaused(bool set) {
        mControl.executeCommand("set_paused "~str.toString(set));
    }

    //not happy with this; but who cares
    //this _really_ should be considered to be a debugging features
    //(to use it from the factory)
    //use the other constructor and pass it a useful GameConfig
    this(TaskManager tm) {
        super(tm);

        createWindow();
        initGame(loadGameConfig(globals.anyConfig.getSubNode("newgame")));
    }

    //start a game
    this(TaskManager tm, GameConfig cfg) {
        super(tm);

        createWindow();
        initGame(cfg);
    }

    //sorry for this hack... definitely needs to be cleaned up
    this(TaskManager tm, bool pseudonet) {
        super(tm);

        createWindow();

        ConfigNode node = globals.anyConfig.getSubNode("newgame");
        node.setBoolValue("as_pseudo_server", pseudonet);
        initGame(loadGameConfig(node));
    }

    this(TaskManager tm, PseudoNetwork pseudo_client) {
        super(tm);

        createWindow();

        //real network: probably has to wait some time until config is
        //available? (wait for server)
        mNetClient = new NetClient(pseudo_client);
        mGameConfig = mNetClient.gameConfig();
        assert (!!mGameConfig);
        //xxx: rendering should be done elsewhere
        if (!mGameConfig.level) {
            auto gen = new GenerateFromSaved(new LevelGeneratorShared(),
                mGameConfig.saved_level);
            mGameConfig.level = gen.render();
            assert (!!mGameConfig.level);
        }
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

    struct BmpHeader {
        int sx, sy;
    }

    //start game intialization
    //it's not clear when initialization is finished (but it shows a loader gui)
    private void initGame(GameConfig cfg) {
        if (!cfg.load_savegame) {
            mGameConfig = cfg;

            //save last played level functionality
            if (mGameConfig.level.saved) {
                saveConfig(mGameConfig.level.saved, "lastlevel.conf");
            }

            mGameConfig.level = fuzzleLevel(mGameConfig.level);
        } else {
            scope st = gFramework.fs.open(cfg.load_savegame, FileMode.In);
            scope tehfile = new TarArchive(st, true);

            //------ bitmaps
            LandscapeBitmap[] bitmaps;
            int bmp_count;
            for (;;) {
                ZReader reader = tehfile.openReadStream(str.format("bitmap_%s",
                    bitmaps.length), true);
                if (!reader)
                    break;
                //xxx: idea: write the bitmap as a png; this either can be an
                //     uncompressed png stored as a .gz stream, or a png that
                //     just deflates scanlines or so (it's probably possible,
                //     but I don't know png good enough)
                //     the loader code can use gFramework.loadImage() (but that
                //     requires a seekable stream)
                BmpHeader bheader;
                reader.read_ptr(&bheader, bheader.sizeof);
                auto size = Vector2i(bheader.sx, bheader.sy);
                //xxx: transparency, colorkey?
                Surface s = gFramework.createSurface(size, Transparency.Colorkey);
                LandscapeBitmap lb = new LandscapeBitmap(s, false);
                bitmaps ~= lb;
                auto lexels = lb.levelData();
                reader.read_ptr(lexels.ptr, Lexel.sizeof*lexels.length);
                void* pixels;
                uint pitch;
                s.lockPixelsRGBA32(pixels, pitch);
                uint linesize = size.x*uint.sizeof;
                for (int i = 0; i < size.y; i++) {
                    reader.read_ptr(pixels, linesize);
                    pixels += pitch;
                }
                s.unlockPixels(Rect2i(size));
                reader.close();
            }

            //------- game data
            ZReader reader = tehfile.openReadStream("gamedata.conf");
            ConfigNode savegame = reader.readConfigFile();
            serialize_types.registerClass!(SaveGameHeader);
            auto ctx = new SerializeContext(serialize_types);
            mSaveGame = new SerializeInConfig(ctx, savegame);
            auto sg = mSaveGame.readObjectT!(SaveGameHeader)();
            auto configfile = new ConfigFile(sg.config, "gamedata.conf", null);
            mGameConfig = new GameConfig();
            mGameConfig.load(configfile.rootnode());
            auto gen = new GenerateFromSaved(new LevelGeneratorShared(),
                mGameConfig.saved_level);
            //false parameter prevents re-rendering
            Level level = gen.render(false);
            mGameConfig.level = level;
            mSaveGame.addExternal(level, "level");
            mSaveGame.addExternal(mGameConfig, "gameconfig");
            mSavedTime = sg.gametime;
            mSavedRandomSeed = sg.randomstate;
            //urgh
            foreach (int n, LandscapeBitmap lb; bitmaps) {
                mSaveGame.addExternal(lb, str.format("landscape_%s", n));
            }
            mSavedViewPosition = sg.viewpos;
            mSavedSetViewPosition = true;

            reader.close();
            tehfile.close();
        }

        doInit();
    }

    void doInit() {
        assert (!!mGameConfig);
        assert (!!mGameConfig.level);

        mLoadScreen = new LoadingScreen();
        mLoadScreen.zorder = 10;
        assert (!!mWindow);
        mWindow.add(mLoadScreen);

        auto load_txt = Translator.ByNamespace("loading.game");
        char[][] chunks;

        void addChunk(LoadChunkDg cb, char[] txt_id) {
            chunks ~= load_txt(txt_id);
            mGameLoader.registerChunk(cb);
        }

        mGameLoader = new Loader();
        addChunk(&initLoadResources, "resources");
        addChunk(&initGameEngine, "gameengine");
        addChunk(&initClientEngine, "clientengine");
        addChunk(&initGameGui, "gui");
        mGameLoader.onFinish = &gameLoaded;

        mLoadScreen.setPrimaryChunks(chunks);
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
        mGame = null;
        mControl = null;
    }

    private bool initGameGui() {
        mGameInfo = new GameInfo(mClientEngine, mControl);
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
        if (mNetClient) {
            //must wait until server ready (I think it's always ready on the
            //first try with pseudo networking)
            if (!mNetClient.game())
                return false; //wait for next frame (busy waiting)
            mGame = mNetClient.game();
            mControl = mNetClient.control();
        } else if (!mSaveGame) {
            mServerEngine = new GameEngine(mGameConfig, mGfx);
            mGame = mServerEngine;
        } else {
            //analogous to saveGame()
            addResources(mSaveGame);
            foreach (int index, LevelItem o; mGameConfig.level.objects) {
                mSaveGame.addExternal(o, str.format("levelobject_%s", index));
            }
            auto ntime = new TimeSource();
            ntime.initTime(mSavedTime);
            ntime.paused = true;
            mSaveGame.addExternal(ntime, "gametime");
            //
            auto rnd = new Random();
            rnd.state = mSavedRandomSeed;
            mSaveGame.addExternal(rnd, "random");
            //sucks, need other solution etc.
            mSaveGame.addExternal(registerLog("gameengine"), "engine_log");
            mSaveGame.addExternal(registerLog("gamecontroller"), "controller_log");
            mSaveGame.addExternal(registerLog("physlog"), "physic_log");
            //
            mServerEngine = mSaveGame.readObjectT!(GameEngine)();
            mGame = mServerEngine;
        }

        if (mGameConfig.as_pseudo_server && !mNetServer) {
            mNetServer = new NetServer(mServerEngine);
            new GameTask(manager(), mNetServer.connect());
        }
        //xxx (well, you know)
        if (!mControl)
            mControl = new ClientControlImpl(mServerEngine.controller);

        return true;
    }

    private bool initClientEngine() {
        //log("initClientEngine");
        mClientEngine = new ClientGameEngine(mGame, mGfx);
        return true;
    }

    //periodically called by loader (stopped when we return true)
    private bool initLoadResources() {
        if (!mResPreloader) {
            mGfx = new GfxSet(mGameConfig.gfx);
            loadWeaponSets();

            //load all items in reslist
            mResPreloader = gFramework.resources.createPreloader(mGfx.resources);
            mLoadScreen.secondaryActive = true;
        }
        mLoadScreen.secondaryCount = mResPreloader.totalCount();
        mLoadScreen.secondaryPos = mResPreloader.loadedCount();
        //the use in returning after some time is to redraw the screen
        mResPreloader.progressTimed(timeMsecs(300));
        if (!mResPreloader.done) {
            return false;
        } else {
            mLoadScreen.secondaryActive = false;
            mResPreloader = null;
            mGfx.finishLoading();
            return true;
        }
    }

    private void loadWeaponSets() {
        //xxx for weapon set stuff:
        //    weapon ids are assumed to be unique between sets
        foreach (char[] ws; mGameConfig.weaponsets) {
            char[] dir = "weapons/"~ws;
            //load set.conf as gfx set (resources and sequences)
            auto conf = gFramework.resources.loadConfigForRes(dir
                ~ "/set.conf");
            mGfx.addGfxSet(conf);
            //load mapping file matching gfx set, if it exists
            auto mappingsNode = conf.getSubNode("mappings");
            char[] mappingFile = mappingsNode.getStringValue(mGfx.gfxId);
            auto mapConf = gFramework.loadConfig(dir~"/"~mappingFile,true,true);
            if (mapConf) {
                mGfx.addSequenceNode(mapConf.getSubNode("sequences"));
            }
            //load weaponset locale
            localeRoot.addLocaleDir("weapons", dir ~ "/locale");
        }
    }

    private void addResources(SerializeBase sb) {
        //support game save/restore: add all resources and some stuff from gfx
        // as external objects
        sb.addExternal(mGfx, "gfx");
        foreach (char[] key, TeamTheme tt; mGfx.teamThemes) {
            sb.addExternal(tt, "gfx_theme::" ~ key);
        }
        foreach (ResourceSet.Entry res; mGfx.resources.resourceList()) {
            //this depends from resset.d's struct Resource
            //currently, the user has the direct resource object, so this must
            //be added as external object reference
            sb.addExternal(res.wrapper.get(), "res::" ~ res.name());
        }
    }

    private void gameLoaded(Loader sender) {
        //idea: start in paused mode, release poause at end to not need to
        //      reset the gametime
        if (mServerEngine)
            mServerEngine.start();
        //a small wtf: why does client engine have its own time??
        mClientEngine.start();

        //remove this, so the game becomes visible
        mLoadScreen.remove();
    }

    override protected void onKill() {
        //smash it up (forced kill; unforced goes into terminate())
        unloadGame();
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
        if (mGameLoader.fullyLoaded) {
            if (mNetServer) {
                mNetServer.frame_receive();
            }
            if (mServerEngine) {
                mServerEngine.doFrame();
            }
            if (mNetServer) {
                mNetServer.frame_send();
            }

            if (mNetClient) {
                mNetClient.frame_receive();
            }
            if (mClientEngine) {
                mClientEngine.doFrame();

                //maybe
                if (mGame.logic.gameEnded)
                    terminateWithFadeOut();
            }
            if (mNetClient) {
                mNetClient.frame_send();
            }
        } else {
            if (mDelayedFirstFrame) {
                mGameLoader.loadStep();
            }
            mDelayedFirstFrame = true;
            //update GUI (Loader/LoadingScreen aren't connected anymore)
            mLoadScreen.primaryPos = mGameLoader.currentChunk;
        }

        //he-he
        doFade();
    }

    void saveGame(TarArchive tehfile) {
        if (!mServerEngine)
            throw new Exception("can't save network game as client");
        GameEngine engine = mServerEngine;

        //---- bitmaps
        auto bitmaps = engine.landscapeBitmaps();
        foreach (int index, LandscapeBitmap lb; bitmaps) {
            ZWriter zwriter = tehfile.openWriteStream(str.format("bitmap_%s",
                index));
            BmpHeader bheader;
            bheader.sx = lb.size.x;
            bheader.sy = lb.size.y;
            zwriter.write_ptr(&bheader, bheader.sizeof);
            auto size = lb.size();
            Lexel[] lexels = lb.levelData();
            zwriter.write_ptr(lexels.ptr, Lexel.sizeof*lexels.length);
            auto bmp = lb.image();
            assert (bmp.size == size);
            void* pixels;
            uint pitch;
            bmp.lockPixelsRGBA32(pixels, pitch);
            uint linesize = size.x*uint.sizeof;
            for (int i = 0; i < size.y; i++) {
                zwriter.write_ptr(pixels, linesize);
                pixels += pitch;
            }
            bmp.unlockPixels(Rect2i.Empty);
            zwriter.close();
        }

        serialize_types.registerClass!(SaveGameHeader);
        auto ctx = new SerializeContext(serialize_types);
        auto writer = new SerializeOutConfig(ctx);

        auto sg = new SaveGameHeader();
        auto gameconfig = engine.gameConfig;
        ConfigNode conf = gameconfig.save();
        sg.config = conf.writeAsString();
        Level level = gameconfig.level;
        writer.addExternal(level, "level");
        writer.addExternal(gameconfig, "gameconfig");

        sg.gametime = engine.gameTime.current;
        //manually save each landscape bitmap
        //this is a special case, because unlike all other bitmaps (and
        //animations etc.), these are modified by the game
        for (int n = 0; n < bitmaps.length; n++) {
            LandscapeBitmap lb = bitmaps[n];
            writer.addExternal(lb, str.format("landscape_%s", n));
        }
        sg.viewpos = mGameFrame.getPosition();
        sg.randomstate = engine.rnd.state;
        writer.writeObject(sg);

        //resources
        addResources(writer);
        //this sucks, currently only needed to get the LandscapeTheme (glevel.d)
        foreach (int index, LevelItem o; level.objects) {
            writer.addExternal(o, str.format("levelobject_%s", index));
        }
        //new TimeSource is created manually on loading
        writer.addExternal(engine.gameTime, "gametime");
        //random seed saved in sg2.randomstate
        writer.addExternal(engine.rnd, "random");
        //no, this can't be done so, another solution is needed
        writer.addExternal(engine.mLog, "engine_log");
        writer.addExternal(engine.controller.mLog, "controller_log");
        writer.addExternal(engine.physicworld.mLog, "physic_log");
        //actually serialize
        writer.writeObject(engine);
        //loading: based on sg2.config, load all required resources; recreate
        //gameTime (by using the time stored in sg2), create something for
        //"random", add them as externals; load the GameEngine and done.

        ConfigNode g = writer.finish();
        ZWriter zwriter = tehfile.openWriteStream("gamedata.conf");
        zwriter.writeConfigFile(g);
        zwriter.close();
    }

    static class SaveGameHeader {
        char[] config; //saved GameConfig
        Time gametime;
        Vector2i viewpos;
        RNGState randomstate;

        this() {
        }
        this(ReflectCtor c) {
        }
    }

    //game specific commands
    private void registerCommands() {
        mCmds.register(Command("slow", &cmdSlow, "set slowdown",
            ["float:slow down",
             "text?:ani or game"]));
        mCmds.register(Command("pause", &cmdPause, "pause"));
        mCmds.register(Command("saveleveltga", &cmdSafeLevelTGA, "dump TGA",
            ["text:filename"]));
        mCmds.register(Command("show_collide", &cmdShowCollide, "show collision"
            " bitmaps"));
        mCmds.register(Command("ser_dump", &cmdSerDump, "serialiation dump"));
        mCmds.register(Command("savetest", &cmdSaveTest, "save and reload"));
        mCmds.register(Command("save", &cmdSaveGame, "save game",
            ["text?:name of the savegame (/savegames/<name>.conf)"]));
        Command load = Command("load", &cmdLoadGame, "load game",
            ["text?:name of the savegame, if none given, list all available"]);
        load.setCompletionHandler(0, &listSavegames);
        mCmds.register(load);
        mCmds.register(Command("snap", &cmdSnapTest, "snapshot test",
            ["int:1=store, 2=load, 3=store+load"]));
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
            auto ph = mServerEngine.physicworld;
            auto types = ph.collide.collisionTypes;
            auto table = new TableContainer(types.length+1, types.length+1,
                Vector2i(2));
            void addc(int x, int y, Label l) {
                Cell c = new Cell();
                c.bla = (y>0) && (x > y);
                c.blu = (y>0) && (x==y);
                l.drawBorder = false;
                l.font = gFramework.getFont("normal");
                c.add(l, WidgetLayout.Aligned(0, 0, Vector2i(1)));
                table.add(c, x, y);
            }
            //column/row headers
            for (int n = 0; n < types.length; n++) {
                auto l = new Label();
                l.text = str.format("%s: %s", n, types[n].name);
                addc(0, n+1, l);
                l = new Label();
                l.text = str.format("%s", n);//types[n].name;
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
        if (!mServerEngine)
            return;
        gWindowManager.createWindow(this, new ShowCollide(),
            "Collision matrix");
    }

    private void cmdSafeLevelTGA(MyBox[] args, Output write) {
        if (!mServerEngine)
            return;
        char[] filename = args[0].unbox!(char[])();
        Stream s = gFramework.fs.open(filename, FileMode.OutNew);
        mServerEngine.gameLandscapes[0].image.saveImage(s);
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
        float g = setgame ? val : mGame.slowDown;
        float a = setani ? val : globals.gameTimeAnimations.slowDown;
        write.writefln("set slowdown: game=%s animations=%s", g, a);
        mControl.executeCommand("slow_down" ~ str.toString(g));
        mClientEngine.engineTime.slowDown = g;
        globals.gameTimeAnimations.slowDown = a;
    }

    private void cmdPause(MyBox[], Output) {
        gamePaused = !gamePaused;
        globals.gameTimeAnimations.paused = !globals.gameTimeAnimations.paused;
    }

    private void cmdExecServer(MyBox[] args, Output write) {
        //send command to the server
        char[] srvCmd = args[0].unbox!(char[]);
        mControl.executeCommand(srvCmd);
    }

    private void cmdSnapTest(MyBox[] args, Output write) {
        if (!mServerEngine)
            return;
        int arg = args[0].unbox!(int);
        if (arg & 1) {
            doEngineSnap();
        }
        if (arg & 2) {
            doEngineUnsnap();
        }
    }

    Time snap_game_time;

    private void doEngineSnap() {
        snap_game_time = mServerEngine.gameTime.current();
        snap(serialize_types, mServerEngine);
    }

    private void doEngineUnsnap() {
        unsnap(serialize_types);
        //important: readd graphics, because they could have changed
        mClientEngine.readd_graphics();
        mServerEngine.gameTime.initTime(snap_game_time);
    }

    private void cmdSerDump(MyBox[] args, Output write) {
        debug debugDumpTypeInfos(serialize_types);
        //debugDumpClassGraph(serialize_types, mServerEngine);
        //char[] res = dumpGraph(serialize_types, mServerEngine, mExternalObjects);
        //std.file.write("dump_graph.dot", res);
        //ConfigNode cfg = saveGame();
        //saveConfig(cfg, "savegame.conf");
    }

    private void cmdSaveTest(MyBox[] args, Output write) {
        doSave("test_temp");
        doLoad("test_temp");
    }

    private void unloadResetAndRestart(GameConfig cfg) {
        unloadGame();
        if (mWindow) mWindow.remove();
        mWindow = null;
        mGameConfig = mGameConfig.init;
        mGfx = null;
        if (mLoadScreen) mLoadScreen.remove();
        mLoadScreen = null;
        mGameLoader = null;
        mResPreloader = null;
        mSaveGame = null;
        mControl = null;
        createWindow(); //???
        initGame(cfg);
    }

    void doSave(char[] name) {
        //xxx detect invalid characters in name etc., but not now
        char[] path = cSavegamePath ~ name ~ cSavegameExt;
        //ConfigNode saved = saveGame();
        //saveConfigGz(saved, path);
        scope st = gFramework.fs.open(path, FileMode.OutNew);
        scope writer = new TarArchive(st, false);
        saveGame(writer);
        writer.close();
    }

    bool doLoad(char[] name) {
        GameConfig ncfg;
        if (!loadSavegame(name, ncfg))
            return false;
        //xxx catch exceptions etc.
        unloadResetAndRestart(ncfg);
        return true;
    }

    char[][] listSavegames() {
        return listAvailableSavegames();
    }

    private void cmdSaveGame(MyBox[] args, Output write) {
        auto name = args[0].unboxMaybe!(char[]);
        if (name.length == 0) {
            //guess name
            int i = 1;
            while (gFramework.fs.exists(VFSPath(cSavegamePath
                ~ cSavegameDefName ~ str.toString(i) ~ cSavegameExt)))
                i++;
            name = cSavegameDefName ~ str.toString(i);
        }
        doSave(name);
        write.writefln("saved game as '%s'.",name);
    }

    private void cmdLoadGame(MyBox[] args, Output write) {
        auto name = args[0].unboxMaybe!(char[]);
        if (name == "") {
            //list all savegames
            write.writefln("Savegames:");
            foreach (s; listSavegames()) {
                write.writefln("  %s", s);
            }
            write.writefln("done.");
        } else {
            write.writefln("Loading: %s", name);
            bool success = doLoad(name);
            if (!success)
                write.writefln("loading failed!");
        }
    }

    static this() {
        TaskFactory.register!(typeof(this))("game");
    }
}
