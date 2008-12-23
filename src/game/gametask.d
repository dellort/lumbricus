module game.gametask;

import common.common;
import common.task;
import framework.resources;
import framework.resset;
import framework.commandline;
import framework.framework;
import framework.filesystem;
import framework.i18n;
import game.gui.loadingscreen;
import game.gui.gameframe;
import game.clientengine;
import game.loader;
import game.gamepublic;
import game.sequence;
import game.gui.gameview;
import game.game;
import game.gfxset;
import game.sprite;
import game.crate;
import game.gobject;
import game.levelgen.level;
import game.levelgen.generator;
import gui.container;
import gui.label;
import gui.tablecontainer;
import gui.widget;
import gui.wm;
import utils.array;
import utils.misc;
import utils.mybox;
import utils.output;
import utils.time;
import utils.vector2;
import utils.log;
import utils.configfile;
import utils.random;
import utils.reflection;

import std.stream;
import std.outbuffer;
import str = std.string;
static import std.file;

//these imports register classes in a factory on module initialization
import game.weapon.projectile;
import game.weapon.special_weapon;
import game.weapon.tools;
import game.weapon.ray;
import game.weapon.spawn;

Types serialize_types;

//this is a test: it explodes the landscape graphic into several smaller ones
Level fuzzleLevel(Level level) {
    return level; //comment out for testing

    const cTile = 128;
    const cSpace = 2; //even more for testing only
    const cTileSize = cTile + cSpace;

    auto rlevel = level.copy();
    //remove all landscapes from new level
    rlevel.objects = arrayFilter(rlevel.objects, (LevelItem i) {
        return !cast(LevelLandscape)i;
    });
    foreach (o; level.objects) {
        if (auto ls = cast(LevelLandscape)o) {
            auto sx = (ls.landscape.size.x + cTileSize - 1) / cTileSize;
            auto sy = (ls.landscape.size.y + cTileSize - 1) / cTileSize;
            for (int y = 0; y < sy; y++) {
                for (int x = 0; x < sx; x++) {
                    auto nls = castStrict!(LevelLandscape)(ls.copy);
                    nls.name = format("%s_%s_%s", nls.name, x, y);
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
        GameEngine mServerEngine;
        GameEnginePublic mGame;
        GameEngineAdmin mGameAdmin;
        ClientGameEngine mClientEngine;
        GfxSet mGfx;
        //hack
        GraphicsHandler mGraphics;

        GameFrame mWindow;

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

        //argh, another step of indirection :/
        SimpleContainer mGameFrame;

        //for save & load support
        char[][Object] mExternalObjects;
    }

    //just for the paused-command?
    private bool gamePaused() {
        return mGame.paused;
    }
    private void gamePaused(bool set) {
        mGameAdmin.setPaused(set);
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

    private void createWindow() {
        mGameFrame = new SimpleContainer();
        auto wnd = gWindowManager.createWindowFullscreen(this, mGameFrame,
            "lumbricus");
        //background is mostly invisible, except when loading and at low
        //detail levels (where the background isn't completely overdrawn)
        auto props = wnd.properties;
        props.background = Color(0); //black :)
        wnd.properties = props;
    }

    //start game intialization
    //it's not clear when initialization is finished (but it shows a loader gui)
    private void initGame(GameConfig cfg) {
        mGameConfig = cfg;

        //save last played level functionality
        saveLevel(mGameConfig.level);

        mGameConfig.level = fuzzleLevel(mGameConfig.level);

        mCmds = new CommandBucket();
        registerCommands();
        mCmds.bind(globals.cmdLine);

        mLoadScreen = new LoadingScreen();
        mLoadScreen.zorder = 10;
        mGameFrame.add(mLoadScreen);

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
    }

    private bool initGameGui() {
        mWindow = new GameFrame(mClientEngine);
        mGameFrame.add(mWindow);

        return true;
    }

    private bool initGameEngine() {
        //log("initGameEngine");
        mGraphics = new GraphicsHandler(mGfx);
        mServerEngine = new GameEngine(mGameConfig, mGfx, mGraphics);
        mGame = mServerEngine;
        mGameAdmin = mServerEngine.requestAdmin();
        return true;
    }

    private bool initClientEngine() {
        //log("initClientEngine");
        mClientEngine = new ClientGameEngine(mServerEngine, mGfx, mGraphics);
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
            finishedResourceLoading();
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

    private void finishedResourceLoading() {
        //support game save/restore: add all resources and some stuff from gfx
        // as external objects
        addExternal("gfx", mGfx);
        foreach (char[] key, TeamTheme tt; mGfx.teamThemes) {
            addExternal("gfx_theme::" ~ key, tt);
        }
        foreach (ResourceSet.Entry res; mGfx.resources.resourceList()) {
            //this depends from resset.d's struct Resource
            //currently, the user has the direct resource object, so this must
            //be added as external object reference
            addExternal("res::" ~ res.name(), res.wrapper.get());
        }
        //extra handling for SequenceState.setDisplayClass() (uarghl)
        addExternal("wsd_classinfo", WormStateDisplay.classinfo);
        addExternal("nsd_classinfo", NapalmStateDisplay.classinfo);
        //various
        // ... gametime, random generator, log...
    }

    private void externalObjects() {
        //before saving or loading a game
        addExternal("clientengine", mClientEngine);
        addExternal("graphicshandler", mGraphics);
    }

    void addExternal(char[] name, Object o) {
        //assert (!(name in mExternalObjects));
        mExternalObjects[o] = name;
    }

    private void gameLoaded(Loader sender) {
        //idea: start in paused mode, release poause at end to not need to
        //      reset the gametime
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
        if (mWindow)
            mWindow.remove(); //from GUI
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
            mGameFrame.add(mFadeOut);
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
            if (mServerEngine) {
                mServerEngine.doFrame();
            }

            if (mClientEngine) {
                mClientEngine.doFrame();

                //maybe
                if (mClientEngine.gameEnded)
                    terminateWithFadeOut();
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

    //game specific commands
    private void registerCommands() {
        mCmds.register(Command("raisewater", &cmdRaiseWater,
            "increase waterline", ["int:water level"]));
        mCmds.register(Command("wind", &cmdSetWind,
            "Change wind speed", ["float:wind speed"]));
        mCmds.register(Command("cameradisable", &cmdCameraDisable,
            "disable game camera", ["bool?:disable"]));
        mCmds.register(Command("detail", &cmdDetail,
            "switch detail level", ["int?:detail level (if not given: cycle)"]));
        mCmds.register(Command("cyclenamelabels", &cmdNames, "worm name labels",
            ["int?:how much to show (if not given: cycle)"]));
        mCmds.register(Command("slow", &cmdSlow, "set slowdown",
            ["float:slow down",
             "text?:ani or game"]));
        mCmds.register(Command("pause", &cmdPause, "pause"));
        mCmds.register(Command("weapon", &cmdWeapon,
            "Debug: Select a weapon by id", ["text:Weapon ID"]));
        mCmds.register(Command("saveleveltga", &cmdSafeLevelTGA, "dump TGA",
            ["text:filename"]));
        mCmds.register(Command("crate_test", &cmdCrateTest, "drop a crate"));
        mCmds.register(Command("shake_test", &cmdShakeTest, "earth quake test",
            ["float:strength", "float:degrade (multiplier < 1.0)"]));
        mCmds.register(Command("show_collide", &cmdShowCollide, "show collision"
            " bitmaps"));
        mCmds.register(Command("activity", &cmdActivityTest,
            "list active game objects", ["bool?:list all objects"]));
        mCmds.register(Command("ser_dump", &cmdSerDump, "serialiation dump"));
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
                l.text = format("%s", n);//types[n].name;
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
        char[] filename = args[0].unbox!(char[])();
        Stream s = gFramework.fs.open(filename, FileMode.OutNew);
        saveSurfaceToTGA(mServerEngine.gameLandscapes[0].image, s);
        s.close();
    }

    private void cmdWeapon(MyBox[] args, Output write) {
        char[] wid = args[0].unboxMaybe!(char[])("");
        write.writefln("xxx reimplement if you want this");
    }

    private void cmdCameraDisable(MyBox[] args, Output write) {
        if (mWindow) {
            mWindow.enableCamera = !args[0].unboxMaybe!(bool)
                (mWindow.enableCamera);
            write.writefln("set camera enable: %s", mWindow.enableCamera);
        }
    }

    private void cmdDetail(MyBox[] args, Output write) {
        if (!mClientEngine)
            return;
        int c = args[0].unboxMaybe!(int)(-1);
        mClientEngine.detailLevel = c >= 0 ? c : mClientEngine.detailLevel + 1;
        write.writefln("set detailLevel to %s", mClientEngine.detailLevel);
    }

    private void cmdNames(MyBox[] args, Output write) {
        if (!mWindow || !mWindow.gameView)
            return;
        auto v = mWindow.gameView;
        auto c = args[0].unboxMaybe!(int)(v.nameLabelLevel + 1);
        v.nameLabelLevel = c;
        write.writefln("set nameLabelLevel to %s", v.nameLabelLevel);
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
        mServerEngine.controller.dropCrate();
    }

    private void cmdShakeTest(MyBox[] args, Output write) {
        float strength = args[0].unbox!(float);
        float degrade = args[1].unbox!(float);
        mServerEngine.addEarthQuake(strength, degrade);
    }

    private void cmdActivityTest(MyBox[] args, Output write) {
        mServerEngine.activityDebug(args[0].unboxMaybe!(bool));
    }

    private void cmdSerDump(MyBox[] args, Output write) {
        debugDumpTypeInfos(serialize_types);
        //debugDumpClassGraph(serialize_types, mServerEngine);
        char[] res = dumpGraph(serialize_types, mServerEngine, mExternalObjects);
        std.file.write("dump_graph.dot", res);
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
            ["generate", "load", "loadbmp"], 0);
        auto x = new LevelGeneratorShared();
        if (what == 0) {
            auto gen = new GenerateFromTemplate(x, cast(LevelTemplate)null);
            cfg.level = gen.render();
        } else if (what == 1) {
            cfg.level = loadSavedLevel(x,
                gFramework.loadConfig(mConfig["level_load"], true));
        } else if (what == 2) {
            auto gen = new GenerateFromBitmap(x);
            auto fn = mConfig["level_load_bitmap"];
            gen.bitmap(gFramework.loadImage(fn), fn);
            gen.selectTheme(x.themes.findRandom(mConfig["level_gfx"]));
            cfg.level = gen.render();
        } else {
            //wrong string in configfile or internal error
            throw new Exception("noes noes noes!");
        }
    }

    auto teamconf = gFramework.loadConfig("teams");
    cfg.teams = teamconf.getSubNode("teams");

    cfg.levelobjects = mConfig.getSubNode("levelobjects");

    auto gamemodecfg = gFramework.loadConfig("gamemode");
    auto modes = gamemodecfg.getSubNode("modes");
    cfg.gamemode = modes.getSubNode(
        mConfig.getStringValue("gamemode",""));
    cfg.weapons = gamemodecfg.getSubNode("weapon_sets");

    cfg.gfx = mConfig.getSubNode("gfx");
    cfg.weaponsets = mConfig.getValueArray!(char[])("weaponsets");
    if (cfg.weaponsets.length == 0) {
        cfg.weaponsets ~= "default";
    }

    return cfg;
}

void saveLevel(Level g) {
    if (g.saved) {
        saveConfig(g.saved, "lastlevel.conf");
    }
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
                    b = *data >> 16; to.write(b);
                    b = *data >> 8; to.write(b);
                    b = *data; to.write(b);
                } else {
                    b = 255; to.write(b);
                    b = 0; to.write(b);
                    b = 255; to.write(b);
                }
                data++;
            }
        }
    } finally {
        s.unlockPixels(Rect2i.init);
    }
    stream.write(to.toBytes);
}


char[] dumpGraph(Types t, Object root, char[][Object] externals) {
    char[] r;
    int id_alloc;
    int[Object] visited; //map to id
    Object[] to_visit;
    r ~= `graph "a" {` \n;
    to_visit ~= root;
    visited[root] = ++id_alloc;
    //some other stuff
    bool[char[]] unknown, unregistered;

    void delegate(int cur, SafePtr ptr, Class c) fwdDoStructMembers;

    void doField(int cur, SafePtr ptr) {
        if (auto s = cast(StructType)ptr.type) {
            assert (!!s.klass());
            fwdDoStructMembers(cur, ptr, s.klass());
        } else if (auto rt = cast(ReferenceType)ptr.type) {
            //object reference
            Object n = ptr.toObject();
            if (!n)
                return;
            int other;
            if (auto po = n in visited) {
                other = *po;
            } else {
                other = ++id_alloc;
                visited[n] = other;
                to_visit ~= n;
            }
            r ~= str.format("%d -- %d\n", cur, other);
        } else if (auto art = cast(ArrayType)ptr.type) {
            ArrayType.Array arr = art.getArray(ptr);
            for (int i = 0; i < arr.length; i++) {
                doField(cur, arr.get(i));
            }
        }
    }

    void doStructMembers(int cur, SafePtr ptr, Class c) {
        foreach (ClassMember m; c.members()) {
            doField(cur, m.get(ptr));
        }
    }

    fwdDoStructMembers = &doStructMembers;

    while (to_visit.length) {
        Object cur = to_visit[0];
        to_visit = to_visit[1..$];
        int id = visited[cur];
        if (auto pname = cur in externals) {
            r ~= str.format(`%d [label="ext: %s"];` \n, id, *pname);
            continue;
        }
        SafePtr indirect = t.ptrOf(cur);
        void* tmp;
        SafePtr ptr = indirect.mostSpecificClass(&tmp, true);
        if (!ptr.type) {
            //the actual class was never seen at runtime
            r ~= str.format(`%d [label="unknown: %s"];` \n, id,
                cur.classinfo.name);
            unknown[cur.classinfo.name] = true;
            continue;
        }
        auto rt = castStrict!(ReferenceType)(ptr.type);
        assert (!rt.isInterface());
        Class c = rt.klass();
        if (!c) {
            //class wasn't registered for reflection
            r ~= str.format(`%d [label="unregistered: %s"];` \n, id,
                cur.classinfo.name);
            unregistered[cur.classinfo.name] = true;
            continue;
        }
        r ~= str.format(`%d [label="class: %s"];` \n, id, cur.classinfo.name);
        while (c) {
            ptr.type = c.owner(); //dangerous, but should be ok
            doStructMembers(id, ptr, c);
            c = c.superClass();
        }
    }
    r ~= "}\n";

    char[][] s_unknown = unknown.keys, s_unreged = unregistered.keys;
    s_unknown.sort;
    s_unreged.sort;
    std.stdio.writefln("Completely unknown:");
    foreach (x; s_unknown)
        std.stdio.writefln("  %s", x);
    std.stdio.writefln("Unregistered:");
    foreach (x; s_unreged)
        std.stdio.writefln("  %s", x);

    return r;
}
