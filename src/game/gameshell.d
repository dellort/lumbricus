module game.gameshell;

import common.common;
import common.resources;
import common.resset;
import framework.commandline;
import framework.framework;
import framework.i18n; //just because of weapon loading...
import framework.timesource;

import game.controller;
import game.gamepublic;
import game.game;
import game.gfxset;
import game.levelgen.generator;
import game.levelgen.landscape;
import game.levelgen.level;
import game.levelgen.renderer;
import game.weapon.weapon;

import utils.archive;
import utils.configfile;
import utils.log;
import utils.misc;
import utils.mybox;
import utils.perf;
import utils.random;
import utils.reflection;
import utils.serialize;
import utils.snapshot;
import utils.time;
import utils.vector2;

import stdx.stream;

//initialized by serialize_register.d
Types serialize_types;

//fixed framerate for the game logic (all of GameEngine)
//also check physic frame length cPhysTimeStepMs in world.d
const Time cFrameLength = timeMsecs(20);

//to implement a pre-load mechanism
//for normal games:
//1. read game configuration
//   => a GameLoader instance is returned
//2. load resources (stepwise, to be enable the GUI to show a progress bar)
//   => can be done by caller by reading resources and creating a preloader etc.
//3. done (GameShell is created), finish() returns GameShell
//for savegames, step 1. is replaced by loading a GameConfig, a savegame header,
//and the level bitmap
//network games: I don't know, lol (needs to be clearified later)
class GameLoader {
    private {
        GameConfig mGameConfig;
        GfxSet mGfx;
        Resources.Preloader mResPreloader;
        SerializeInConfig mSaveGame;
        GameShell mShell;
    }

    private this() {
    }

    static GameLoader CreateFromSavegame(TarArchive file) {
        auto r = new GameLoader();
        r.initFromSavegame(file);
        return r;
    }

    static GameLoader CreateNewGame(GameConfig cfg) {
        auto r = new GameLoader();
        r.mGameConfig = cfg;
        r.doInit();
        return r;
    }

    private void loadWeaponSets() {
        //xxx for weapon set stuff:
        //    weapon ids are assumed to be unique between sets
        foreach (char[] ws; mGameConfig.weaponsets) {
            char[] dir = "weapons/"~ws;
            //load set.conf as gfx set (resources and sequences)
            auto conf = gResources.loadConfigForRes(dir
                ~ "/set.conf");
            mGfx.addGfxSet(conf);
            //load mapping file matching gfx set, if it exists
            auto mappingsNode = conf.getSubNode("mappings");
            char[] mappingFile = mappingsNode.getStringValue(mGfx.gfxId);
            auto mapConf = gConf.loadConfig(dir~"/"~mappingFile,true,true);
            if (mapConf) {
                mGfx.addSequenceNode(mapConf.getSubNode("sequences"));
            }
            //load weaponset locale
            localeRoot.addLocaleDir("weapons", dir ~ "/locale");
        }
    }

    private void doInit() {
        //save last played level functionality
        //xxx should this really be here
        if (mGameConfig.level.saved) {
            gConf.saveConfig(mGameConfig.level.saved, "lastlevel.conf");
        }

        mGfx = new GfxSet(mGameConfig.gfx);
        loadWeaponSets();

        mResPreloader = gResources.createPreloader(mGfx.resources);
    }

    private void initFromSavegame(TarArchive file) {
        //------ gamedata.conf
        ZReader reader = file.openReadStream("gamedata.conf");
        ConfigNode savegame = reader.readConfigFile();
        reader.close();

        int bitmap_count = savegame.getValue!(int)("bitmap_count");
        ConfigNode game_cfg = savegame.getSubNode("game_config");
        ConfigNode game_data = savegame.getSubNode("game_data");

        //------ GameConfig & level
        mGameConfig = new GameConfig();
        mGameConfig.load(game_cfg);
        //reconstruct GameConfig.level
        auto gen = new GenerateFromSaved(new LevelGeneratorShared(),
            mGameConfig.saved_level);
        //false parameter prevents re-rendering... we don't need the original
        //level bitmap; instead it's loaded from the png in the savegame
        //this also means the call should be relatively fast (I HOPE)
        mGameConfig.level = gen.render(false);

        //------ bitmaps
        LandscapeBitmap[] bitmaps;
        for (int idx = 0; idx < bitmap_count; idx++) {
            Surface image = gFramework.loadImage(file
                .openReadStreamUncompressed(myformat("bitmap_{}.png", idx)));
            LandscapeBitmap lb = new LandscapeBitmap(image, false);
            auto lexels = lb.levelData();
            ZReader rd = file.openReadStream(myformat("lexels_{}", idx));
            rd.read_ptr(lexels.ptr, Lexel.sizeof*lexels.length);
            rd.close();
            bitmaps ~= lb;
        }

        //------- game data
        auto ctx = new SerializeContext(serialize_types);
        mSaveGame = new SerializeInConfig(ctx, game_data);

        mSaveGame.addExternal(mGameConfig, "gameconfig");
        mSaveGame.addExternal(mGameConfig.level, "level");

        foreach (int n, LandscapeBitmap lb; bitmaps) {
            mSaveGame.addExternal(lb, myformat("landscape_{}", n));
        }

        //needed because level objects are not serialized with the engine,
        //but the engine still stores references to them
        foreach (int index, LevelItem o; mGameConfig.level.objects) {
            mSaveGame.addExternal(o, myformat("levelobject_{}", index));
        }

        //NOTE: can read actual GameEngine from mSaveGame only after all
        //      resources have been loaded; addResources() is the reason
        //      so it will be done in finish()

        doInit();
    }

    GameShell finish() {
        if (mShell)
            return mShell;
        //just to be sure caller didn't mess up
        mResPreloader.loadAll();
        assert(mResPreloader.done()); //xxx error handling (failed resources)
        mResPreloader = null;
        mGfx.finishLoading();
        mShell = new GameShell();
        mShell.mGameConfig = mGameConfig;
        mShell.mGfx = mGfx;
        mShell.mMasterTime = new TimeSource();
        if (!mSaveGame) {
            //for creation of a new game
            mShell.mGameTime = new TimeSourceFixFramerate(mShell.mMasterTime,
                cFrameLength);
            mShell.mEngine = new GameEngine(mGameConfig, mGfx,
                mShell.mGameTime);
        } else {
            //for loading a savegame
            addResources(mGfx, mSaveGame);
            mSaveGame.addExternal(mShell.mMasterTime, "mastertime");
            //(actually deserialize the complete engine)
            mShell.mEngine = mSaveGame.readObjectT!(GameEngine)();
            //(could also get mEngine.gameTime and cast it)
            mShell.mGameTime = mSaveGame.readObjectT!(TimeSourceFixFramerate)();
            //time continues at when game was saved
            mShell.mMasterTime.initTime(mShell.mGameTime.lastExternalTime());
        }
        return mShell;
    }

    //valid during loading (between creation and finish())
    Resources.Preloader resPreloader() {
        return mResPreloader;
    }

    GameConfig gameConfig() {
        return mGameConfig;
    }
}

private void addResources(GfxSet gfx, SerializeBase sb) {
    //support game save/restore: add all resources and some stuff from gfx
    // as external objects
    sb.addExternal(gfx, "gfx");
    foreach (char[] key, TeamTheme tt; gfx.teamThemes) {
        sb.addExternal(tt, "gfx_theme::" ~ key);
    }
    foreach (ResourceSet.Entry res; gfx.resources.resourceList()) {
        //this depends from resset.d's struct Resource
        //currently, the user has the direct resource object, so this must
        //be added as external object reference
        sb.addExternal(res.wrapper.get(), "res::" ~ res.name());
    }
}

//this provides a "shell" around a GameEngine, to log all mutating function
//calls to it (a function that changes something must be logged to implement
//replaying, which is an awfully important feature)
class GameShell {
    private {
        GameEngine mEngine;
        //only used to feed mGameTime and to set offset time when loading
        //savegames
        TimeSource mMasterTime;
        //fixed-framerate time, note that there's also the paused/slowdown
        //stuff, which is why the .current() time value can be completely
        //different from mMasterTime
        //this object is serialized into savegames / is managed by snapshotting!
        TimeSourceFixFramerate mGameTime;
        GameConfig mGameConfig;
        GfxSet mGfx;
        InputLog mCurrentInput;
        GameSnap mReplaySnapshot;
        bool mLogReplayInput;
        InputLog mReplayInput;
    }

    void delegate() OnRestoreGuiAfterSnapshot;

    struct GameSnap {
        Snapshot snapshot;
        Time game_time;
        LandscapeBitmap[] bitmaps;
    }

    struct LogEntry {
        void function(LogEntry e) caller; //function to call the boxed delegate
        Time timestamp;
        MyBox callee; //boxed delegate
        MyBox[] params; //boxed parameters for the callee
    }

    struct InputLog {
        LogEntry[] entries;
        InputLog clone() {
            auto res = *this;
            res.entries = res.entries.dup;
            return res;
        }
    }

    //use GameLoader.Create*() instead
    private this() {
    }

    private void execEntry(LogEntry e) {
        assert(!!e.caller);
        e.caller(e);
    }

    //add a logged function call - the timestamp of the function call is set to
    //now, and is executed at the next possible time
    private void addLoggedInput(T)(T a_callee, MyBox[] params) {
        alias GetDGParams!(T) Params;

        //function to unbox the types and call the destination delegate
        static void do_call(LogEntry e) {
            T callee = e.callee.unbox!(T)();
            Params p;
            //(yes, p[i] will have a different static type in each iteration)
            foreach (int i, x; Params) {
                p[i] = e.params[i].unbox!(x)();
            }
            callee(p);
        }

        LogEntry e;

        e.caller = &do_call;
        e.callee = MyBox.Box(a_callee);
        e.params = params;
        //assume time increases monotonically => list stays always sorted
        e.timestamp = mEngine.gameTime.current;

        mCurrentInput.entries ~= e;
        if (mLogReplayInput) {
            mReplayInput.entries ~= e;
        }
    }

    void frame() {
        mMasterTime.update();
        mGameTime.update(() { doFrame(); });
    }

    private void doFrame() {
        //execute input at correct time, which is particularly important for
        //replays (input is reused on a snapshot of the deterministic engine)
        while (mCurrentInput.entries.length > 0) {
            LogEntry e = mCurrentInput.entries[0];
            if (e.timestamp > mGameTime.current)
                break;
            execEntry(e);
            //remove
            for (int n = 0; n < mCurrentInput.entries.length - 1; n++) {
                mCurrentInput.entries[n] = mCurrentInput.entries[n + 1];
            }
            mCurrentInput.entries.length = mCurrentInput.entries.length - 1;
        }
        mEngine.frame();
    }

    void snapForReplay() {
        doSnapshot(mReplaySnapshot);
        mLogReplayInput = true;
        mReplayInput = mReplayInput.init;
    }

    void replay() {
        doUnsnapshot(mReplaySnapshot);
        mLogReplayInput = false;
        mCurrentInput = mReplayInput.clone;
    }

    void doSnapshot(ref GameSnap snap) {
        if (!snap.snapshot)
            snap.snapshot = new Snapshot(new SnapDescriptors(serialize_types));
        snap.game_time = mGameTime.current();
        snap.snapshot.snap(mEngine);
        //bitmaps are specially handled, I don't know how to do better
        //probably unify with savegame stuff?
        PerfTimer timer = new PerfTimer(true);
        timer.start();
        auto bitmaps = mEngine.landscapeBitmaps();
        foreach (int index, LandscapeBitmap lb; bitmaps) {
            if (index >= snap.bitmaps.length) {
                snap.bitmaps ~= lb.copy();
            } else {
                //assume LandscapeBitmap.size() never changes, and that the
                //result of server's landscapeBitmaps() returns the same objects
                //in the same order (newly created ones attached to the end)
                //random note: for faster snapshotting, one could copy only the
                // regions that have been modified since the last snapshot
                snap.bitmaps[index].copyFrom(lb);
            }
        }
        timer.stop();
        Stdout.formatln("backup bitmaps t={}", timer.time);
    }

    void doUnsnapshot(ref GameSnap snap) {
        snap.snapshot.unsnap();
        PerfTimer timer = new PerfTimer(true);
        timer.start();
        auto bitmaps = mEngine.landscapeBitmaps();
        foreach (int index, LandscapeBitmap lb; bitmaps) {
            lb.copyFrom(snap.bitmaps[index]);
        }
        timer.stop();
        Stdout.formatln("restore bitmaps t={}", timer.time);
        //(yes, mMasterTime is set to what mGameTime was - that's like when
        // loading a savegame)
        mMasterTime.initTime(snap.game_time);
        mGameTime.resetTime();
        assert(!!OnRestoreGuiAfterSnapshot);
        OnRestoreGuiAfterSnapshot();
    }

    void saveGame(TarArchive file) {
        //------ gamedata.conf
        ConfigNode savegame = new ConfigNode();

        LandscapeBitmap[] bitmaps = mEngine.landscapeBitmaps();
        savegame.setValue!(int)("bitmap_count", bitmaps.length);

        //------ GameConfig & level
        savegame.add("game_config", mGameConfig.save());

        //------ bitmaps
        foreach (int idx, LandscapeBitmap lb; bitmaps) {
            Lexel[] lexels = lb.levelData();
            ZWriter zwriter = file.openWriteStream(myformat("lexels_{}", idx));
            zwriter.write_ptr(lexels.ptr, Lexel.sizeof*lexels.length);
            zwriter.close();
            Stream bmp = file.openUncompressed(myformat("bitmap_{}.png", idx));
            //force png to guarantee lossless compression
            lb.image.saveImage(bmp, "png");
            bmp.close();
        }

        //------- game data
        auto ctx = new SerializeContext(serialize_types);
        auto writer = new SerializeOutConfig(ctx);

        writer.addExternal(mGameConfig, "gameconfig");
        writer.addExternal(mGameConfig.level, "level");

        foreach (int n, LandscapeBitmap lb; bitmaps) {
            writer.addExternal(lb, myformat("landscape_{}", n));
        }

        foreach (int index, LevelItem o; mGameConfig.level.objects) {
            writer.addExternal(o, myformat("levelobject_{}", index));
        }

        addResources(mGfx, writer);

        writer.addExternal(mMasterTime, "mastertime");

        writer.writeObject(mEngine);
        writer.writeObject(mGameTime); //see loading code for the why

        ConfigNode g = writer.finish();
        savegame.add("game_data", g);

        ZWriter zwriter = file.openWriteStream("gamedata.conf");
        zwriter.writeConfigFile(savegame);
        zwriter.close();
    }

    GameEngine serverEngine() {
        return mEngine;
    }
}

//one endpoint (e.g. network peer, or whatever), that can send input.
//for now, it has control over a given set of teams, and all time one of these
//teams is active, GameControl will actually accept the input and pass it to
//the GameEngine
class GameControl : ClientControl {
    private {
        GameShell mOwner;
        CommandBucket mCmds;
        CommandLine mCmd;
        ServerTeam[] mOwnedTeams;
        Log mInputLog;
    }

    this(GameShell sh) {
        mInputLog = new Log("game.input_log");

        mOwner = sh;
        createCmd();

        //multiple clients for one team? rather not, but cannot be checked here
        //xxx implement client-team assignment
        foreach (t; mOwner.mEngine.logic.getTeams)
            mOwnedTeams ~= castStrict!(ServerTeam)(cast(Object)t);
    }

    //return true if command was found and could be parsed
    //gives no indication if the actual action was accepted or rejected
    //this function could directly accept network input
    bool doExecuteCommand(char[] cmd) {
        mInputLog("client command: '{}'", cmd);
        return mCmd.execute(cmd);
    }


    //automatically add an item to the command line parser
    //compile time magic is used to infer the parameters, and the delegate
    //is called when the command is invoked (maybe this is overcomplicated)
    void addCmd(T)(char[] name, T del) {
        alias GetDGParams!(T) Params;

        //proxify the function in a commandline call
        //the wrapper is just to get a delegate, that is valid even after this
        //function has returned
        //in D2.0, this Wrapper stuff will be unnecessary
        struct Wrapper {
            GameShell owner;
            T callee;
            void cmd(MyBox[] params, Output o) {
                owner.addLoggedInput!(T)(callee, params);
            }
        }

        Wrapper* pwrap = new Wrapper;
        pwrap.owner = mOwner;
        pwrap.callee = del;

        //build command line argument list according to delegate arguments
        char[][] cmdargs;
        foreach (int i, x; Params) {
            char[]* pt = typeid(x) in gCommandLineParserTypes;
            if (!pt) {
                assert(false, "no command line parser for " ~ x.stringof);
            }
            cmdargs ~= myformat("{}:param_{}", *pt, i);
        }

        mCmds.register(Command(name, &pwrap.cmd, "-", cmdargs));
    }

    //similar to addCmd()
    //expected is a delegate like void foo(ServerTeamMember w, X); where
    //X can be further parameters (can be empty)
    void addWormCmd(T)(char[] name, T del) {
        //remove first parameter, because that's the worm
        alias GetDGParams!(T)[1..$] Params;

        struct Wrapper {
            GameControl owner;
            T callee;
            void moo(Params p) {
                owner.checkWormCommand(
                    (ServerTeamMember w) {
                        //may error here, if del has a wrong type
                        callee(w, p);
                    }
                );
            }
        }

        Wrapper* pwrap = new Wrapper;
        pwrap.owner = this;
        pwrap.callee = del;

        addCmd(name, &pwrap.moo);
    }


    private void createCmd() {
        mCmd = new CommandLine(globals.defaultOut);
        mCmds = new CommandBucket();

        GameEngine engine = mOwner.mEngine;

        //usual server "admin" command (commands could simply be not add for
        //GameControl instances, that represent unprivileged users)
        addCmd("raise_water", &engine.raiseWater);
        addCmd("set_wind", &engine.setWindSpeed);
        addCmd("set_pause", &engine.setPaused);
        addCmd("slow_down", &engine.setSlowDown);
        addCmd("crate_test", &engine.crateTest);
        addCmd("shake_test", &engine.addEarthQuake);
        addCmd("activity", &engine.activityDebug);

        //worm control commands; work like above, but the worm-selection code
        //is factored out

        //remember that delegate literals must only access their params
        //if they access members of this class, runtime errors will result

        addWormCmd("next_member", (ServerTeamMember w) {
            w.serverTeam.doChooseWorm();
        });
        addWormCmd("jump", (ServerTeamMember w, bool alt) {
            w.jump(alt ? JumpMode.straightUp : JumpMode.normal);
        });
        addWormCmd("move", (ServerTeamMember w, int x, int y) {
            w.doMove(Vector2i(x, y));
        });
        addWormCmd("weapon", (ServerTeamMember w, char[] weapon) {
            WeaponClass wc;
            if (weapon != "-")
                wc = w.engine.findWeaponClass(weapon, true);
            w.selectWeaponByClass(wc);
        });
        addWormCmd("set_timer", (ServerTeamMember w, int ms) {
            w.doSetTimer(timeMsecs(ms));
        });
        addWormCmd("set_target", (ServerTeamMember w, int x, int y) {
            w.serverTeam.doSetPoint(Vector2f(x, y));
        });
        addWormCmd("selectandfire", (ServerTeamMember w, char[] m, bool down) {
            if (down) {
                WeaponClass wc;
                if (m != "-")
                    wc = w.engine.findWeaponClass(m, true);
                w.selectWeaponByClass(wc);
                //doFireDown will save the keypress and wait if not ready
                w.doFireDown(true);
            } else {
                //key was released (like fire behavior)
                w.doFireUp();
            }
        });

        //also a worm cmd, but specially handled
        addCmd("weapon_fire", &executeWeaponFire);

        mCmds.bind(mCmd);
    }

    //if a worm control command is incoming (like move, shoot, etc.), two things
    //must be done here:
    //  1. find out which worm is controlled by GameControl
    //  2. check if the move is allowed
    private bool checkWormCommand(void delegate(ServerTeamMember w) pass) {
        //we must intersect both sets of team members (= worms):
        // set of active worms (by game controller) and set of worms owned by us
        //xxx: if several worms are active that belong to us, pick the first one
        foreach (ServerTeam t; mOwnedTeams) {
            ServerTeamMember w = t.current;
            if (t.active) {
                pass(w);
                return true;
            }
        }
        return false;
    }

    private void executeWeaponFire(bool is_down) {
        void fire(ServerTeamMember w) {
            if (is_down) {
                w.doFireDown();
            } else {
                w.doFireUp();
            }
        }

        if (!checkWormCommand(&fire)) {
            //no worm active
            //spacebar for crate
            mOwner.mEngine.instantDropCrate();
        }
    }

    //-- ClientControl

    override TeamMember getControlledMember() {
        //hurf, just what did I think???
        ServerTeamMember cur;
        checkWormCommand((ServerTeamMember w) { cur = w; });
        return cur;
    }

    override void executeCommand(char[] cmd) {
        doExecuteCommand(cmd);
    }

    //-- /ClientControl
}
