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
import str = utils.string;

import game.serialize_register : initGameSerialization;

import utils.stream;
import tango.io.device.File : File;

//these imports register classes in a factory on module initialization
import game.action.common;
import game.action.list;
import game.action.spawn;
import game.action.weaponactions;
import game.action.spriteactions;
import game.weapon.projectile;
import game.weapon.rope;
import game.weapon.jetpack;
import game.weapon.drill;
import game.weapon.ray;
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

class Fader : Spacer {
    private {
        Time mFadeStartTime;
        int mFadeDur;
        Color mStartCol = {0,0,0,0};
        Color mEndCol = {0,0,0,1};
    }

    bool done;

    this(Time fadeTime, bool fadeIn) {
        if (fadeIn)
            swap(mStartCol, mEndCol);
        color = mStartCol;
        mFadeStartTime = timeCurrentTime;
        mFadeDur = fadeTime.msecs;
    }

    override bool onTestMouse(Vector2i pos) {
        return false;
    }

    override void simulate() {
        super.simulate();
        int mstime = (timeCurrentTime - mFadeStartTime).msecs;
        if (mstime > mFadeDur) {
            //end of fade
            done = true;
        } else {
            float scale = 1.0f*mstime/mFadeDur;
            color = mStartCol + (mEndCol - mStartCol) * scale;
        }
    }
}

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

        Fader mFader;
        const cFadeOutDuration = timeSecs(2);
        const cFadeInDuration = timeMsecs(500);

        bool mDelayedFirstFrame; //draw screen before loading first chunk

        //temporary when loading a game
        SerializeInConfig mSaveGame;
        Vector2i mSavedViewPosition;
        bool mSavedSetViewPosition;
        ConfigNode mGamePersist;
    }

    //not happy with this; but who cares
    //this _really_ should be considered to be a debugging features
    //(to use it from the factory)
    //use the other constructor and pass it a useful GameConfig
    this(TaskManager tm, char[] args = "") {
        super(tm);

        createWindow();

        if (str.eatStart(args, "demo:")) {
            mGameLoader = GameLoader.CreateFromDemo(args);
            doInit();
            return;
        } else if (args == "") {
            //sorry for this hack... definitely needs to be cleaned up
            ConfigNode node = gConf.loadConfig("newgame");
            initGame(loadGameConfig(node));
            return;
        }

        throw new Exception("unknown commandline params"); //???
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
        auto guiconf = tehfile.readConfigStream("gui.conf");

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
        if (mGameShell) {
            mCmds.removeSub(mGameShell.commands());
            mGameShell.terminate();
        }
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
            mCmds.addSub(mGameShell.commands());
            mGameShell.OnRestoreGuiAfterSnapshot = &guiRestoreSnapshot;
            mGame = mGameShell.serverEngine;

            //ShowObject.CreateWindow(this, mGameShell.getSerializeContext.types,
            //    mGameShell.serverEngine);
        }
        if (mConnection) {
            if (!mControl)
                return false;
        }

        if (mGameShell && !mControl) {
            //xxx (well, you know)
            mControl = new ClientControl(mGameShell, "local");
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
            debug gResources.showStats();
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

        mFader = new Fader(cFadeInDuration, true);
        mWindow.add(mFader);
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
        if (!mFader) {
            mFader = new Fader(cFadeOutDuration, false);
            mWindow.add(mFader);
        }
    }

    private void doFade() {
        if (mFader && mFader.done) {
            mFader.remove();
            mFader = null;
            if (mGame.logic.gameEnded)
                kill();
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
        auto zwriter = tehfile.openWriteStream("gui.conf");
        guiconf.writeFile(zwriter);
        zwriter.close();
    }

    //game specific commands
    private void registerCommands() {
        if (!mConnection) {
            mCmds.register(Command("slow", &cmdSlow, "set slowdown",
                ["float:slow down",
                 "text?:ani or game"]));
            mCmds.register(Command("ser_dump", &cmdSerDump,
                "serialiation dump"));
            mCmds.register(Command("snap", &cmdSnapTest, "snapshot test",
                ["int:1=store, 2=load, 3=store+load"]));
            mCmds.register(Command("replay", &cmdReplay,
                "start recording or replay from last snapshot",
                ["text?:any text to start recording"]));
            mCmds.register(Command("demo_stop", &cmdDemoStop,
                "stop demo recorder"));
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
        Stream s = gFS.open(filename, File.WriteCreate);
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

    private void cmdDemoStop(MyBox[], Output) {
        if (mGameShell)
            mGameShell.stopDemoRecorder();
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
        auto ctx = mGameShell.getSerializeContext();
        char[] res = ctx.dumpGraph(mGameShell.serverEngine());
        File.set("dump_graph.dot", res);
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

class ShowObject : Container {
    private {
        Types mTypes;
        UpdateText[] mTexts;
        Time mLastUpdate;

        struct UpdateText {
            Label lbl;
            SafePtr ptr;
            char[] delegate(SafePtr p) updater;
        }
    }

    static void CreateWindow(Task task, Types types, Object o) {
        auto wnd = gWindowManager.createWindow(task, new ShowObject(types, o),
            "Muh", Vector2i(0,0));
        auto props = wnd.properties;
        props.zorder = WindowZOrder.High;
        wnd.properties = props;
        wnd.onClose = (Window sender) {return true;};
    }

    this(Types t, Object o) {
        mTypes = t;
        assert(!!o);
        SafePtr p = mTypes.objPtr(o);
        addChild(createStructured(p));
    }

    void update() {
        foreach (t; mTexts) {
            t.lbl.textMarkup = t.updater(t.ptr);
        }
    }

    override void simulate() {
        auto cur = timeCurrentTime();
        if (cur - mLastUpdate > timeSecs(1.0)) {
            mLastUpdate = cur;
            update();
        }
    }

    private Widget createSub(SafePtr ptr) {
        if (cast(StructType)ptr.type) {
            return createStructured(ptr);
        }
        //default conversion, which uses the stdlib's format()
        UpdateText t;
        t.lbl = new Label();
        //t.lbl.shrink = true;
        t.ptr = ptr;
        t.updater = &conv_def;
        mTexts ~= t;
        return t.lbl;
    }

    private Widget createStructured(SafePtr ptr) {
        auto stuff = new TableContainer(2, 0, Vector2i(3, 0));
        auto cur = castStrict!(StructuredType)(ptr.type).klass();
        if (!cur)
            return null; //xxx: ?

        while (cur) {
            foreach (ClassMember m; cur.members) {
                SafePtr sub = m.get(ptr);
                Widget w = createSub(sub);
                if (!w) {
                    auto lbl = new Label();
                    lbl.textMarkup = "\\c(red)?";
                    w = lbl;
                }
                WidgetLayout lay;
                lay.expand[] = [true, false];
                w.setLayout(lay);
                auto namelbl = new Label();
                namelbl.setLayout(WidgetLayout.Aligned(-1, 0));
                namelbl.text = m.name();
                int r = stuff.addRow();
                stuff.add(namelbl, 0, r);
                stuff.add(w, 1, r);
            }

            if (!cur.superClass())
                break;

            cur = cur.superClass();
            ptr.type = cur.type();
            int r = stuff.addRow();
            auto spacer = new Spacer();
            stuff.add(spacer, 0, r, 2, 1);
        }

        return stuff;
    }

    private char[] conv_def(SafePtr p) {
        //the lit is for not making it interpreted as markup
        char[] txt = p.type.dataToString(p);
        const cMax = 50;
        if (txt.length > cMax) {
            return "\"\\lit\0" ~ txt[0..cMax] ~ "\0\\{\\c(red)...\\}\"";
        } else {
            return "\"\\lit\0" ~ txt ~ "\0\"";
        }
    }
}
