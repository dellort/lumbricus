module game.gametask;

import common.common;
import common.task;
import common.loadsave;
import common.resources;
import common.resset;
import common.resview;
import framework.commandline;
import framework.framework;
import framework.filesystem;
import framework.font;
import framework.i18n;
import framework.timesource;
import framework.lua;
import game.gui.loadingscreen;
import game.hud.gameframe;
import game.hud.teaminfo;
import game.hud.gameview;
import game.clientengine;
import game.loader;
import game.gameshell;
import game.game;
import game.setup;
//--> following 2 imports are not actually needed, but avoid linker errors
//    on windows with game.gui.leveledit disabled in lumbricus.d
import game.levelgen.placeobjects;
import game.levelgen.genrandom;
//<--
import gui.console;
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
import game.animation;
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
import game.weapon.parachute;
import game.weapon.airstrike;
//import game.weapon.luaweapon;
import game.gamemodes.turnbased;
import game.gamemodes.mdebug;
import game.gamemodes.realtime;
import game.controller_plugins;
import game.lua;


class Fader : Widget {
    private {
        Time mFadeStartTime;
        int mFadeDur;
        Color mStartCol = {0,0,0,0};
        Color mEndCol = {0,0,0,1};
        Color mColor;
    }

    bool done;

    this(Time fadeTime, bool fadeIn) {
        focusable = false;
        isClickable = false;
        if (fadeIn)
            swap(mStartCol, mEndCol);
        mColor = mStartCol;
        mFadeStartTime = timeCurrentTime;
        mFadeDur = fadeTime.msecs;
    }

    override void onDraw(Canvas c) {
        c.drawFilledRect(widgetBounds, mColor);
    }

    override void simulate() {
        super.simulate();
        int mstime = (timeCurrentTime - mFadeStartTime).msecs;
        if (mstime > mFadeDur) {
            //end of fade
            done = true;
        } else {
            float scale = 1.0f*mstime/mFadeDur;
            mColor = mStartCol + (mEndCol - mStartCol) * scale;
        }
    }
}

class GameTask : StatefulTask {
    private {
        GameShell mGameShell; //can be null, if a client in a network game!
        GameLoader mGameLoader; //creates a GameShell
        GameEngine mGame;
        ClientGameEngine mClientEngine;
        ClientControl mControl;
        GameInfo mGameInfo;
        SimpleNetConnection mConnection;

        GameFrame mGameFrame;
        WindowContainer mWindow;

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
        }

        ConfigNode node = loadConfig("newgame");

        //hack, what else
        //there should be a proper command line parser (for lumbricus.d too)
        if (args == "freegraphics") {
            args = "";
            node.getSubNode("gfx")["config"] = "freegraphics.conf";
        }

        if (args == "") {
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
        mWindow = new WindowContainer();
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
            Object e = mGameShell.serverEngine;
            //mGameShell.getSerializeContext().death_stomp(e);
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
            mClientEngine.fadeoutMusic(cFadeOutDuration);
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
        mCmds.register(Command("savelevelpng", &cmdSafeLevelPNG, "dump PNG",
            ["text:filename"]));
        mCmds.register(Command("show_collide", &cmdShowCollide, "show collision"
            " bitmaps"));
        mCmds.register(Command("server", &cmdExecServer,
            "Run a command on the server", ["text...:command"]));
        mCmds.register(Command("show_obj", &cmdShowObj, "", null));
        mCmds.register(Command("game_res", &cmdGameRes, "show in-game resources"
            " (doesn't include all global resources, but does include some"
            " game-only stuff)", null));
        mCmds.register(Command("lua", &cmdLua, "open separate window with lua"
            " interpreter bound to the game engine"));
    }

    class ShowCollide : Container {
        class Cell : SimpleContainer {
            bool bla, blu;
            override void onDraw(Canvas c) {
                if (bla || blu) {
                    Color cl = bla ? Color(0.7) : Color(1.0,0.7,0.7);
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
                l.font = gFontManager.loadFont("normal");
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
                    table.setHomogeneousGroup(0, x, 1);
                    table.setHomogeneousGroup(1, y, 1);
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

    //just for that debug-grabbing stuff...
    class WindowContainer : SimpleContainer {
        bool do_capture;

        override bool handleChildInput(InputEvent event) {
            if (!do_capture)
                return super.handleChildInput(event);
            if (event.isKeyEvent && event.keyEvent.code == Keycode.MOUSE_LEFT) {
                do_capture = false;
                auto p = mousePos;
                mGameFrame.gameView.translateCoords(this, p);
                show_obj(p);
            }
            return true;
        }

        //only used when capturing
        override MouseCursor mouseCursor() {
            MouseCursor c;
            //cross like, good enough
            c.graphic = globals.guiResources.get!(Surface)("red_x");
            c.graphic_spot = c.graphic.size/2;
            return c;
        }
    }

    private void cmdShowObj(MyBox[] args, Output write) {
        mWindow.do_capture = true;
    }

    private void show_obj(Vector2i pos) {
        if (!mGameShell)
            return;
        Object o = mGameShell.serverEngine.debug_pickObject(pos);
        if (!o)
            return;
        auto ctx = mGameShell.getSerializeContext;
        ShowObject.CreateWindow(this, ctx, ctx.types.ptrOf(o));
    }

    private void cmdGameRes(MyBox[] args, Output write) {
        if (!mGameShell)
            return;
        new ResViewerTask(manager, mGameShell.serverEngine.gfx.resources);
    }

    private void cmdLua(MyBox[] args, Output write) {
        new LuaInterpreter(manager,
            createScriptingObj(mGameShell.serverEngine));
    }

    private void cmdSafeLevelPNG(MyBox[] args, Output write) {
        if (!mGameShell)
            return;
        char[] filename = args[0].unbox!(char[])();
        Stream s = gFS.open(filename, File.WriteCreate);
        mGameShell.serverEngine.gameLandscapes[0].image.saveImage(s, "png");
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
        debug {
            debugDumpTypeInfos(serialize_types);
            auto ctx = mGameShell.getSerializeContext();
            char[] res = ctx.dumpGraph(mGameShell.serverEngine());
            File.set("dump_graph.dot", res);
        }
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
        SafePtr mP; //watched
        Task mTask;
        Types mTypes;
        SerializeContext mSCtx;
        UpdateText[] mTexts;
        Expand[] mExpanders;
        Time mLastUpdate;
        bool mEnableUpdate = true;

        struct UpdateText {
            Label lbl;
            SafePtr ptr;
            char[] delegate(SafePtr p) updater;
        }

        struct Expand {
            Button btn;
            SafePtr ptr;
            void delegate(SafePtr p) expand;
        }
    }

    static void CreateWindow(Task task, SerializeContext sctx, SafePtr p) {
        p = p.deepestType();

        char[] title;
        if (p.type.hasToString()) {
            title = p.type.dataToString(p);
        } else {
            title = myformat("{}", p.type.typeInfo);
        }

        auto wnd = gWindowManager.createWindow(task,
            new ShowObject(task, sctx, p), title, Vector2i(0,0));
        auto props = wnd.properties;
        props.zorder = WindowZOrder.High;
        wnd.properties = props;
        wnd.onClose = (Window sender) {return true;};
    }

    this(Task tsk, SerializeContext sctx, SafePtr p) {
        mP = p;
        mTask = tsk;
        mTypes = sctx.types;
        mSCtx = sctx;

        assert(mP.type && mP.ptr);

        //if s is null, the type is not registered with serialization
        //  or p.ptr is a class reference variable, that points to null
        auto s = createTop(p);
        if (s)
            addChild(s);

        update();
    }

    void update() {
        foreach (t; mTexts) {
            t.lbl.textMarkup = t.updater(t.ptr);
        }
    }

    override void simulate() {
        if (!mEnableUpdate)
            return;

        auto cur = timeCurrentTime();
        if (cur - mLastUpdate > timeSecs(1.0)) {
            mLastUpdate = cur;
            update();
        }
    }

    //for the top level element (which makes up the window)
    private Widget createTop(SafePtr ptr) {
        if (cast(StructuredType)ptr.type)
            return createStructured(ptr);
        if (cast(ArrayType)ptr.type)
            return createArray(ptr);
        if (cast(MapType)ptr.type)
            return createMap(ptr);
        //unsupported type, but we can try the sub element code
        return createSub(ptr);
    }

    //for sub elements (inside top level elements)
    private Widget createSub(SafePtr ptr) {
        if (cast(StructType)ptr.type) {
            //try to be smart, use toString() if it's implemented
            if (!ptr.type.hasToString())
                return createStructured(ptr);
        }

        Widget w = createDefault(ptr);

        void delegate(SafePtr) expander;

        /+if (cast(ReferenceType)ptr.type
            || cast(ArrayType)ptr.type
            || cast(MapType)ptr.type))
        {
            expander = &do_expand_any;
        }+/
        expander = &do_expand_any;

        if (expander) {
            auto b = new Button();
            b.setLayout(WidgetLayout.Noexpand());
            b.onClick = &expand_click;
            b.textMarkup = "...";

            mExpanders ~= Expand(b, ptr, expander);

            auto box = new BoxContainer(true);
            box.add(w);
            box.add(b);

            w = box;
        }

        return w;
    }

    private void do_expand_any(SafePtr p) {
        CreateWindow(mTask, mSCtx, p);
    }

    private void expand_click(Button b) {
        foreach (e; mExpanders) {
            if (e.btn is b) {
                e.expand(e.ptr);
                return;
            }
        }
    }

    private Widget createDefault(SafePtr ptr) {
        //default conversion, which uses the stdlib's format()
        UpdateText t;
        t.lbl = new Label();
        //t.lbl.shrink = true;
        t.ptr = ptr;
        t.updater = &conv_def;
        mTexts ~= t;
        return t.lbl;
    }

    //prevent duplicated code...
    struct RowBuilder {
        TableContainer table;
        bool line_ok; //false => line was just added
        Color line_color = Color(1,0,0);
        int side_start;
        const Color side_color = Color(0.5);

        void do_init() {
            table = new TableContainer(3, 0, Vector2i(3, 0));
            line_ok = false;
            side_start = 0;
        }

        void add(Widget left, Widget right) {
            int r = table.addRow();

            if (left) {
                left.setLayout(WidgetLayout.Aligned(-1, 0));
                table.add(left, 0, r);
            }

            if (right) {
                WidgetLayout lay;
                lay.expand[] = [true, false];
                right.setLayout(lay);
                table.add(right, 2, r);
            }

            line_ok = true;
        }

        private void close_side(int at) {
            auto end = at - 1;
            auto start = side_start;
            side_start = int.max;
            if (end < start)
                return;
            auto line = new Spacer();
            line.minSize = Vector2i(1,0);
            //line.color = side_color;
            WidgetLayout lay;
            lay.expand[] = [false, true];
            lay.padA.y = 2;
            lay.padB.y = 2;
            line.setLayout(lay);
            table.add(line, 1, start, 1, end-start+1);
        }

        void line() {
            if (!line_ok)
                return;
            int r = table.addRow();
            close_side(r);
            auto spacer = new Spacer();
            spacer.minSize = Vector2i(0,1);
            //spacer.color = line_color;
            WidgetLayout lay;
            lay.expand[] = [true, false];
            spacer.setLayout(lay);
            table.add(spacer, 0, r, 3, 1);
            line_ok = false;
            side_start = r+1;
        }

        void finish() {
            close_side(table.height);
        }
    }

    private void add_member(ref RowBuilder rows, char[] name, SafePtr p) {
        Widget w = createSub(p);
        if (!w) {
            auto lbl = new Label();
            lbl.textMarkup = "\\c(red)?";
            w = lbl;
        }
        auto namelbl = new Label();
        namelbl.text = name;

        rows.add(namelbl, w);
    }

    private Widget createStructured(SafePtr ptr) {
        auto curc = castStrict!(StructuredType)(ptr.type).klass();
        if (!curc)
            return null; //xxx: ?

        if (curc.isClass()) {
            //object reference SafePtrs are pointers to pointers
            //check for null
            if (!ptr.toObject())
                return null;
        }

        RowBuilder rows;
        rows.do_init();

        foreach (int i, cur; curc.hierarchy) {
            ptr.type = cur.type();

            rows.line();

            foreach (ClassMember m; cur.members) {
                add_member(rows, m.name(), m.get(ptr));
            }
        }

        rows.finish();

        return rows.table;
    }

    private Widget createArray(SafePtr ptr) {
        auto art = castStrict!(ArrayType)(ptr.type);
        auto arr = art.getArray(ptr);

        //doesn't make sense (or it should also track array length changes)
        mEnableUpdate = false;

        RowBuilder rows;
        rows.do_init();

        auto head = new Label();
        head.textMarkup = myformat("length = {}", arr.length);
        rows.add(head, null);

        auto len = min(arr.length, 20);

        for (int n = 0; n < len; n++) {
            //rows.line();
            add_member(rows, myformat("[{}]", n), arr.get(n));
        }

        if (len != arr.length) {
            rows.line();
            auto c = new Label();
            c.textMarkup = "\\c(red)\\b(cut)";
            rows.add(c, null);
        }

        rows.finish();

        return rows.table;
    }

    private Widget createMap(SafePtr ptr) {
        auto mapt = castStrict!(MapType)(ptr.type);

        //really doesn't make sense (items are copied)
        mEnableUpdate = false;

        RowBuilder rows;
        rows.do_init();

        int n;
        mapt.iterate(ptr, (SafePtr key, SafePtr value) {
            rows.line();

            //copy stuff, because pointers get invalid when the delegate is
            //  exited (at least key is allocated on stack)
            SafePtr copy(SafePtr p) {
                p.ptr = p.box().data.dup.ptr;
                return p;
            }

            add_member(rows, myformat("key[{}]", n), copy(key));
            add_member(rows, myformat("value[{}]", n), copy(value));
            n++;
        });

        rows.finish();

        return rows.table;
    }

    private char[] conv_def(SafePtr p) {
        if (cast(ReferenceType)p.type) {
            Object o = p.toObject();
            if (!o)
                return "\\c(red)null";

            //generally more useful than nothing or toString
            char[] ext = mSCtx.lookupExternal(o);
            if (ext.length)
                return "\\{\\c(green)" ~ ext ~ "\\}";

            //use a pointer with the "real" type of the object
            //that helps with hasToString() not returning "shadowed" information
            auto p2 = mTypes.objPtr(o, null, true);
            if (!!p2.type)
                p = p2;
        }

        if (!p.type.hasToString())
            return myformat("\\c(grey)(no .toString for {})", p.type.typeInfo);

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

class LuaInterpreter : Task {
    private {
        CommandLine mCmdLine;
        LuaState mLua;
        Output mOut;
    }

    this(TaskManager mgr, char[] args = "") {
        auto state = new LuaState();

        //copy and paste
        //don't want to put this in framework.lua (too many weird dependencies)
        void loadscript(char[] filename) {
            filename = "lua/" ~ filename;
            auto st = gFS.open(filename);
            scope(exit) st.close();
            state.loadScript(filename, cast(char[])st.readAll());
        }

        loadscript("utils.lua");

        this(mgr, state);
    }

    this(TaskManager mgr, LuaState state) {
        super(mgr);

        mLua = state;

        auto w = new GuiConsole();
        mCmdLine = w.cmdline();
        mCmdLine.setPrefix("/", "exec");
        mCmdLine.registerCommand("exec", &cmdExec, "execute a Lua command",
            ["text...:code"]);
        mOut = w.output;
        mOut.writefln("Scripting console using: {}", mLua.cLanguageAndVersion);
        gWindowManager.createWindow(this, w, "Lua Console", Vector2i(400, 200));

        //this might be a bit dangerous/unwanted
        //but we need it for this console
        //alternatively, maybe one could create a sub-environment or whatever,
        //  that just shadows the default output function, or so
        mLua.setPrintOutput(&printOutput);
    }

    private void printOutput(char[] s) {
        mOut.writef("{}", s);
    }

    private void cmdExec(MyBox[] args, Output output) {
        auto code = args[0].unbox!(char[])();
        //somehow looks less confusing to include the command in the output
        mOut.writefln("> {}", code);
        //NOTE: this doesn't implement passing several lines as one piece of
        //  code; the Lua command line interpreter uses a very hacky way to
        //  detect the end of lines (it parses the parser error message); should
        //  we also do this?
        //http://www.lua.org/source/5.1/lua.c.html
        try {
            mLua.loadScript("input", code);
        } catch (ScriptingException e) {
            mOut.writefln("Lua error: {}", e);
        }
    }

    static this() {
        TaskFactory.register!(typeof(this))("luaconsole");
    }
}
