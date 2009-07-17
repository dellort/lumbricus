module game.gameshell;

import common.common;
import common.resources;
import common.resset;
import framework.framework;
import framework.i18n; //just because of weapon loading...
import framework.timesource;
import framework.commandline;

import game.controller;
import game.gamepublic;
import game.game;
import game.gfxset;
import game.gobject;
import game.levelgen.generator;
import game.levelgen.landscape;
import game.levelgen.level;
import game.levelgen.renderer;
import game.weapon.weapon;
import net.marshal : Hasher;

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
import utils.strparser : boxToString;
import utils.time;
import utils.vector2;
import str = utils.string;

import utils.stream;
import tango.math.Math : pow;
import convert = tango.util.Convert;


//see GameShell.engineHash()
//type of hash might be changed in the future
struct EngineHash {
    uint hash;
}

//initialized by serialize_register.d
Types serialize_types;

//fixed framerate for the game logic (all of GameEngine)
//also check physic frame length cPhysTimeStepMs in world.d
const Time cFrameLength = timeMsecs(20);

//the optimum length of the input queue in network mode (i.e. what the engine
//  will try to reach)
//if the queue gets longer, game speed will be increased to catch up
//xxx: for optimum performance, this should be calculated dynamically based
//     on connection jitter (higher values give more jitter protection, but
//     higher introduced lag)
const int cOptimumInputLag = 1;

private LogStruct!("game.gameshell") log;

//save the game engine to disk on snapshot/replay, stuff goes into path /debug/
debug = debug_save;

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
        bool mNetwork;
        GameShell mShell;
        //savegame only
        ConfigNode mGameData;
        ConfigNode mTimeConfig;
        ConfigNode mPersistence;
        LandscapeBitmap[] mBitmaps;
        bool enable_demo_recording = true;
        //ConfigNode mDemoFile;
        Output mDemoOutput;
        //null = no demo reading
        //OH GOD FUCK IT
        //GameShell.InputLog* mDemoInput;
        void* mDemoInput;
    }

    private struct TimeSettings {
        long time_ns;
        long game_ts;
        bool paused = false;
        float slowdown = 1.0f;
    }

    void delegate(GameShell shell) onLoadDone;

    private this() {
    }

    static GameLoader CreateFromSavegame(TarArchive file) {
        auto r = new GameLoader();
        r.initFromSavegame(file);
        return r;
    }

    static GameLoader CreateNewGame(GameConfig cfg) {
        auto r = new GameLoader();
        //xxx: should level==null really be allowed?
        if (!cfg.level) {
            auto gen = new GenerateFromSaved(new LevelGeneratorShared(),
                cfg.saved_level);
            cfg.level = gen.render();
        }
        assert(!!cfg.level);
        r.mGameConfig = cfg;
        r.doInit();
        return r;
    }

    static GameLoader CreateNetworkGame(GameConfig cfg,
        void delegate(GameShell shell) loadDone)
    {
        auto r = CreateNewGame(cfg);
        r.mNetwork = true;
        r.onLoadDone = loadDone;
        return r;
    }

    //filename_prefix is e.g. "last_demo", and the code will try to read the
    //  files last_demo.conf and last_demo.dat
    static GameLoader CreateFromDemo(char[] filename_prefix) {
        auto r = new GameLoader();
        auto lg = new GameShell.InputLog;
        r.mDemoInput = lg;
        auto demoFile = gConf.loadConfig(filename_prefix ~ ".conf", true);
        auto cfg = new GameConfig();
        r.mGameConfig = cfg;
        cfg.load(demoFile.getSubNode("game_config"));
        //xxx move elsewhere or whatever
        if (!cfg.level) {
            auto gen = new GenerateFromSaved(new LevelGeneratorShared(),
                cfg.saved_level);
            cfg.level = gen.render();
        }
        //parse the .dat
        ulong max_ts;
        auto f = gFS.open(filename_prefix ~ ".dat");
        char[] dat = cast(char[])f.readAll();
        f.close();
        //xxx throws exception on utf-8 error
        //(as intended, but needs better error reporting)
        str.validate(dat);
        foreach (char[] line; str.splitlines(dat)) {
            line = str.strip(line);
            if (line == "")
                continue;
            if (str.eatStart(line, "END ")) {
                //end marker, TS follows
                //xxx: throws exception...
                lg.end_ts = to!(ulong)(line);
                break;
            }
            //<ts>|<tag>|<cmd>
            //xxx: clumsy parser, throws exceptions...
            auto res = str.split2_b(line, '|');
            GameShell.LogEntry e;
            e.timestamp = to!(ulong)(res[0]);
            res = str.split2_b(res[1], '|');
            e.access_tag = res[0];
            e.cmd = res[1];
            lg.entries ~= e;
            max_ts = max(max_ts, e.timestamp);
        }
        if (!lg.end_ts)
            lg.end_ts = max_ts;
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

        //never record a demo when playing back a demo
        if (!!mDemoInput)
            enable_demo_recording = false;

        if (enable_demo_recording) {
            registerLog("foowarning")("demo recording enabled!");
            auto demoFile = new ConfigNode();
            demoFile.addNode("game_config", mGameConfig.save());
            char[] filename = "last_demo.";
            gConf.saveConfig(demoFile, filename ~ "conf");
            //why two files? because I want to output stuff in realtime, and
            //  the output should survive even a crash
            auto outstr = gFS.open(filename ~ "dat", File.WriteCreate);
            mDemoOutput = new PipeOutput(outstr.pipeOut());
        }

        mGfx = new GfxSet(mGameConfig.gfx);
        loadWeaponSets();

        mResPreloader = gResources.createPreloader(mGfx.resources);
    }

    private void initFromSavegame(TarArchive file) {
        //------ gamedata.conf
        ConfigNode savegame = file.readConfigStream("gamedata.conf");

        mTimeConfig = savegame.getSubNode("game_time");
        int bitmap_count = savegame.getValue!(int)("bitmap_count");
        ConfigNode game_cfg = savegame.getSubNode("game_config");
        ConfigNode game_data = savegame.getSubNode("game_data");
        ConfigNode persNode = savegame.getSubNode("persistence");

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
        for (int idx = 0; idx < bitmap_count; idx++) {
            Surface image = gFramework.loadImage(file
                .openReadStreamUncompressed(myformat("bitmap_{}.png", idx)));
            LandscapeBitmap lb = new LandscapeBitmap(image, false);
            auto lexels = lb.levelData();
            auto rd = file.openReadStream(myformat("lexels_{}", idx));
            scope(exit) rd.close();
            rd.readExact(cast(ubyte[])lexels);
            mBitmaps ~= lb;
        }

        //NOTE: can read actual GameEngine from mGameData only after all
        //      resources have been loaded; addResources() is the reason
        //      so it will be done in finish()
        mPersistence = persNode.copy();
        mGameData = game_data;

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
        mShell.mMasterTime = new TimeSource("GameShell/MasterTime");
        if (mNetwork) {
            mShell.mMasterTime.paused = true;
            //use server timestamps
            mShell.mUseExternalTS = true;
        }
        mShell.mGameTime = new TimeSourceFixFramerate("GameTime",
            mShell.mMasterTime, cFrameLength);

        //registers many objects referenced from mShell for serialization
        mShell.initSerialization();

        if (mDemoOutput) {
            mShell.mDemoOutput = mDemoOutput;
        }

        if (!mGameData) {
            //for creation of a new game
            mShell.mEngine = new GameEngine(mGameConfig, mGfx,
                mShell.mGameTime);
        } else {
            //code for loading a savegame

            SerializeContext ctx = mShell.mSerializeCtx;
            auto saveGame = new SerializeInConfig(ctx, mGameData);

            auto ts = saveGame.read!(TimeSettings)();

            //meh time, not serialized anymore because it only causes problems
            mShell.mMasterTime.initTime(timeNsecs(ts.time_ns));
            auto gt = mShell.mGameTime;
            gt.resetTime();
            gt.paused = ts.paused;
            gt.slowDown = ts.slowdown;
            mShell.mTimeStamp = ts.game_ts;
            //assert(gt.current == start_time);
            assert(mShell.mTimeStamp*cFrameLength ==mShell.mMasterTime.current);

            foreach (int n, LandscapeBitmap lb; mBitmaps) {
                ctx.addExternal(lb, myformat("landscape_{}", n));
            }
            ctx.addExternal(mPersistence, "persistence");

            //(actually deserialize the complete engine)
            mShell.mEngine = saveGame.readObjectT!(GameEngine)();

            foreach (LandscapeBitmap lb; mBitmaps) {
                ctx.removeExternal(lb);
            }
            mBitmaps = null; //make GC-able, just in case
            ctx.removeExternal(mPersistence);
        }

        if (mDemoInput) {
            //whee whee we simply set it to replay mode and seriously mess with
            //  the internals
            //let's hope it doesn't break
            mShell.snapForReplay();
            auto lg = cast(GameShell.InputLog*)mDemoInput;
            mShell.mReplayInput = *lg;
            mShell.mTimeStamp = lg.end_ts;
            mShell.replay();
        }

        if (onLoadDone)
            onLoadDone(mShell);
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
        TimeSourceFixFramerate mGameTime;
        //timestamps are simpler
        long mTimeStamp;
        long mTimeStampAvail = -1;
        GameConfig mGameConfig;
        GfxSet mGfx;
        InputLog mCurrentInput;
        GameSnap mReplaySnapshot;
        bool mLogReplayInput;
        InputLog mReplayInput;
        bool mReplayMode; //currently replaying
        bool mUseExternalTS; //timestamp advancing is controlled externally
        bool mExtIsLagging;
        debug bool mPrintFrameTime;
        Hasher mGameHasher;
        SerializeContext mSerializeCtx;

        CommandBucket mCmds;
        CommandLine mCmd;

        //bool mEnableDemoPlayback;
        //if !is null, enable demo recording
        Output mDemoOutput;
    }
    bool terminated;  //set to exit the game instantly

    void delegate() OnRestoreGuiAfterSnapshot;

    struct GameSnap {
        Snapshot snapshot;
        long game_time_ts; //what was mTimeStamp
        Time game_time;
        LandscapeBitmap[] bitmaps;
    }

    struct LogEntry {
        long timestamp;
        char[] access_tag;
        char[] cmd;

        char[] toString() {
            return myformat("ts={}, access='{}': '{}'", timestamp, access_tag,
                cmd);
        }
    }

    struct InputLog {
        LogEntry[] entries;
        long end_ts;

        InputLog clone() {
            auto res = *this;
            res.entries = res.entries.dup;
            return res;
        }
    }

    //use GameLoader.Create*() instead
    private this() {
        mCmd = new CommandLine(globals.defaultOut);
        mCmds = new CommandBucket();

        mCmds.register(Command("set_pause", &cmdSetPaused, "-",
            ["bool:-"]));
        mCmds.register(Command("slow_down", &cmdSetSlowdown, "-",
            ["float:-"]));

        mCmds.bind(mCmd);
    }

    private void execEntry(LogEntry e) {
        log("exec input: {}", e);
        assert(mTimeStamp == e.timestamp);
        //(this is here and not in addLoggedInput, because then input could be
        // logged for replay, that was never executed)
        if (mLogReplayInput) {
            mReplayInput.entries ~= e;
        }
        mEngine.executeCommand(e.access_tag, e.cmd);
    }

    //command to be executed by GameEngine.executeCommand()
    //this is logged/timestamped for networking, snapshot/replays, and demo mode
    void addLoggedInput(char[] access_tag, char[] cmd, long cmdTimeStamp = -1) {
        //yeh, this might be a really bad idea
        if (replayMode() && str.startsWith(cmd, "weapon_fire")) {
            replaySkip();
            return;
        }

        //and this may be a bad idea too
        if (mCmd.execute(cmd))
            return;


        LogEntry e;

        e.access_tag = access_tag;
        e.cmd = cmd;

        //assume time increases monotonically => list stays always sorted
        if (cmdTimeStamp >= 0)
            e.timestamp = cmdTimeStamp;
        else
            e.timestamp = mTimeStamp;

        log("received input: {}", e);

        if (mReplayMode) {
            log("previous input denied, because in replay mode");
            return;
        }

        mCurrentInput.entries ~= e;

        if (mDemoOutput) {
            //warning: some idiots could send us commands with newlines
            //  this would break demo recordings
            mDemoOutput.writefln("{}|{}|{}", e.timestamp, e.access_tag, e.cmd);
        }
    }

    //public access
    void executeCommand(char[] access_tag, char[] cmd) {
        addLoggedInput(access_tag, cmd);
    }

    void frame() {
        if (mUseExternalTS) {
            //external timestamps (network mode, from setFrameReady())
            //this code tries to keep the input queue length (local lag)
            //  at cOptimumInputLag by varying game speed
            //how far the server is ahead
            int lag = mTimeStampAvail - mTimeStamp;
            //log("lag = {}",lag);
            if (lag < 0) {
                //no server frame coming -> wait
                mMasterTime.paused = true;
                mExtIsLagging = true;
            } else {
                //server frames are available
                mMasterTime.paused = false;
                mExtIsLagging = false;
                if (lag < cOptimumInputLag) {
                    //run at 1x speed
                    if (mMasterTime.slowDown != 1.0f)
                        mMasterTime.slowDown = 1.0f;
                } else {
                    //run faster
                    uint diff = min(cast(uint)(lag - cOptimumInputLag + 1), 50);
                    float slow = pow(1.2L, diff);
                    if (slow > 20.0f)
                        slow = 20.0f;
                    mMasterTime.slowDown = slow;
                }
            }
            mMasterTime.update();
            //don't accidentally run past server time
            int maxFrames = lag + 1;
            mGameTime.update(&doFrame, maxFrames);
        } else {
            mMasterTime.update();
            mGameTime.update(() { doFrame(); });
        }
    }

    //called by network client, whenever all input events at the passed
    //timeStamp have been fed to the engine
    void setFrameReady(long timeStamp) {
        assert(timeStamp >= mTimeStamp, "local ts can't be ahead of server");
        assert(timeStamp >= mTimeStampAvail, "monotone time");
        mTimeStampAvail = timeStamp;
    }

    //true if master time is paused because setFrameReady() was not called
    bool waitingForFrame() {
        if (mUseExternalTS)
            return mExtIsLagging;
        return false;
    }

    private void doFrame() {
        //Trace.formatln("ts={}, hash={}", mTimeStamp, engineHash().hash);
        debug if (mPrintFrameTime) {
            log("frame time: ts={} time={} ({} ns)", mTimeStamp,
                mGameTime.current, mGameTime.current.nsecs);
            mPrintFrameTime = false;
        }
        //execute input at correct time, which is particularly important for
        //replays (input is reused on a snapshot of the deterministic engine)
        while (mCurrentInput.entries.length > 0) {
            LogEntry e = mCurrentInput.entries[0];
            if (e.timestamp > mTimeStamp)
                break;
            assert(e.timestamp == mTimeStamp);
            execEntry(e);
            //remove
            for (int n = 0; n < mCurrentInput.entries.length - 1; n++) {
                mCurrentInput.entries[n] = mCurrentInput.entries[n + 1];
            }
            mCurrentInput.entries.length = mCurrentInput.entries.length - 1;
        }
        mEngine.frame();
        mTimeStamp++;
        //xxx not sure if the input for this frame should be fed to the engine
        //    before debug-dumping, I'm too tired to think about that
        if (mReplayMode) {
            if (mTimeStamp >= mReplayInput.end_ts) {
                assert(mTimeStamp == mReplayInput.end_ts);
                if (mMasterTime.slowDown > 1.0f)
                    mMasterTime.slowDown = 1.0f;
                mReplayMode = false;
                log("stop replaying");
                debug(debug_save)
                    debug_save();
            }
        }
    }

    void snapForReplay() {
        doSnapshot(mReplaySnapshot);
        mLogReplayInput = true;
        mReplayInput = mReplayInput.init;
        log("snapshot for replay at time={} ({} ns)", mGameTime.current,
            mGameTime.current.nsecs);
        debug mPrintFrameTime = true;
    }

    void replay() {
        if (!mReplaySnapshot.snapshot) {
            log("replay failed: no snapshot saved");
            return;
        }
        debug(debug_save)
            debug_save();
        mReplayInput.end_ts = mTimeStamp;
        doUnsnapshot(mReplaySnapshot);
        mLogReplayInput = false;
        mCurrentInput = mReplayInput.clone;
        mReplayMode = true;
        log("replay start, time={} ({} ns)", mGameTime.current,
            mGameTime.current.nsecs);
        debug mPrintFrameTime = true;
    }

    void replaySkip() {
        if (mReplayMode) {
            mMasterTime.slowDown = 20.0f;
        }
    }

    bool replayMode() {
        return mReplayMode;
    }

    Time replayRemain() {
        if (mReplayMode) {
            return (mReplayInput.end_ts - mTimeStamp)*cFrameLength;
        } else {
            return Time.Null;
        }
    }

    void doSnapshot(ref GameSnap snap) {
        if (!snap.snapshot)
            snap.snapshot = new Snapshot(new SnapDescriptors(serialize_types));
        snap.game_time = mGameTime.current();
        snap.game_time_ts = mTimeStamp;
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
        log("snapshot backup bitmaps t={}", timer.time);
    }

    //NOTE: because of the time managment, you must not call this during a
    //      GameEngine frame (or during doFrame in general)
    //      if you do, replay-determinism might be destroyed
    void doUnsnapshot(ref GameSnap snap) {
        snap.snapshot.unsnap();
        PerfTimer timer = new PerfTimer(true);
        timer.start();
        auto bitmaps = mEngine.landscapeBitmaps();
        foreach (int index, LandscapeBitmap lb; bitmaps) {
            lb.copyFrom(snap.bitmaps[index]);
        }
        timer.stop();
        log("snapshot restore bitmaps t={}", timer.time);
        //(yes, mMasterTime is set to what mGameTime was - that's like when
        // loading a savegame)
        //one must be very careful that this bug doesn't happen: you restore
        // a snapshot, and then you repeat the frame that was executed right
        // before the snapshot was made. this can happen because the time before
        // and after a frame can be the same (the time doesn't change during the
        // frame; instead the time is increased by the frame length before a new
        // frame is executed)
        //so I did this lol, I hope this works; feel free to make it better
        //mTimeStamp is incremented right after a GameEngine frame, so it must
        //refer to the exact time for the next frame
        mMasterTime.initTime(snap.game_time_ts*cFrameLength);
        assert(mMasterTime.current == snap.game_time);
        //mMasterTime.initTime(snap.game_time);
        mGameTime.resetTime();
        mTimeStamp = snap.game_time_ts;
        //xxx it seems using snap.game_time was fine, but whatever
        assert(mGameTime.current == snap.game_time);
        //assert(!!OnRestoreGuiAfterSnapshot);
        if (OnRestoreGuiAfterSnapshot) {
            OnRestoreGuiAfterSnapshot();
        }
    }

    void saveGame(TarArchive file) {
        //------ gamedata.conf
        ConfigNode savegame = new ConfigNode();

        LandscapeBitmap[] bitmaps = mEngine.landscapeBitmaps();
        savegame.setValue!(int)("bitmap_count", bitmaps.length);

        //------ GameConfig & level
        savegame.addNode("game_config", mGameConfig.save());
        savegame.addNode("persistence", mEngine.persistentState.copy());

        //------ bitmaps
        foreach (int idx, LandscapeBitmap lb; bitmaps) {
            Lexel[] lexels = lb.levelData();
            auto zwriter = file.openWriteStream(myformat("lexels_{}", idx));
            zwriter.write(cast(ubyte[])lexels);
            zwriter.close();
            Stream bmp = file.openUncompressed(myformat("bitmap_{}.png", idx));
            //force png to guarantee lossless compression
            lb.image.saveImage(bmp, "png");
            bmp.close();
        }

        //------- game data
        auto writer = new SerializeOutConfig(mSerializeCtx);

        GameLoader.TimeSettings ts;
        ts.time_ns = mGameTime.current.nsecs;
        ts.paused = mGameTime.paused;
        ts.slowdown = mGameTime.slowDown;
        ts.game_ts = mTimeStamp;
        writer.write(ts);

        foreach (int n, LandscapeBitmap lb; bitmaps) {
            mSerializeCtx.addExternal(lb, myformat("landscape_{}", n));
        }
        mSerializeCtx.addExternal(mEngine.persistentState, "persistence");

        writer.writeObject(mEngine);

        //sorry for the braindead
        foreach (LandscapeBitmap lb; bitmaps) {
            mSerializeCtx.removeExternal(lb);
        }
        mSerializeCtx.removeExternal(mEngine.persistentState);

        ConfigNode g = writer.finish();
        savegame.addNode("game_data", g);

        auto zwriter = file.openWriteStream("gamedata.conf");
        savegame.writeFile(zwriter);
        zwriter.close();
    }

    private void initSerialization() {
        if (!!mSerializeCtx)
            return;

        mSerializeCtx = new SerializeContext(serialize_types);

        //all of the following should go away *sigh*

        //mSerializeCtx.addExternal(mEngine.persistentState, "persistence");
        mSerializeCtx.addExternal(mGameConfig, "gameconfig");
        mSerializeCtx.addExternal(mGameConfig.level, "level");

        foreach (int index, LevelItem o; mGameConfig.level.objects) {
            mSerializeCtx.addExternal(o, myformat("levelobject_{}", index));
        }

        mSerializeCtx.addExternal(mGameTime, "game_time");

        //was addResources()
        //can't really be avoided, because we're not going to write game data
        //  graphics and sounds into the savegame
        mSerializeCtx.addExternal(mGfx, "gfx");
        foreach (char[] key, TeamTheme tt; mGfx.teamThemes) {
            mSerializeCtx.addExternal(tt, "gfx_theme::" ~ key);
        }
        foreach (ResourceSet.Entry res; mGfx.resources.resourceList()) {
            mSerializeCtx.addExternal(res.wrapper.get(), "res::" ~ res.name());
        }
    }

    //public, but only for debugging stuff
    SerializeContext getSerializeContext() {
        return mSerializeCtx;
    }

    debug(debug_save) void debug_save() {
        int t;
        char[] p = gFS.getUniqueFilename("/debug/", "dump{0:d3}", ".tar", t);
        log("saving debugging dump to {}", p);
        scope st = gFS.open(p, File.WriteCreate);
        scope writer = new TarArchive(st, false);
        saveGame(writer);
        writer.close();
    }

    GameEngine serverEngine() {
        return mEngine;
    }

    TimeSource masterTime() {
        return mMasterTime;
    }

    //see GameEngine.hash()
    EngineHash engineHash() {
        if (!mGameHasher)
            mGameHasher = new Hasher();
        mGameHasher.reset();
        mEngine.hash(mGameHasher);
        mGameHasher.hash(mTimeStamp);
        return EngineHash(mGameHasher.hash_value);
    }

    bool paused() {
        return mGameTime.paused();
    }

    //xxx: not networking save, I guess
    private void cmdSetPaused(MyBox[] params, Output o) {
        bool state = params[0].unbox!(bool)();
        log("pause: {}", state);
        mGameTime.paused = state;
    }
    private void cmdSetSlowdown(MyBox[] params, Output o) {
        float state = params[0].unbox!(float)();
        log("slowndown: {}", state);
        mGameTime.slowDown = state;
    }
}

//one endpoint (e.g. network peer, or whatever), that can send input.
//for now, it has control over a given set of teams, and all time one of these
//teams is active, GameControl will actually accept the input and pass it to
//the GameEngine
class ClientControl {
    private {
        GameShell mShell;
        char[] mAccessTag;
        Team[] mCachedOwnedTeams;
    }

    //for explanation for access_control_tag, see GameEngine.executeCmd()
    //instantiating this directly is "dangerous", because this might
    //  accidentally bypass networking (see CmdNetControl)
    this(GameShell sh, char[] access_control_tag) {
        assert(!!sh);
        mShell = sh;
        mAccessTag = access_control_tag;
    }

    //NOTE: CmdNetControl overrides this method and redirects it so, that cmd
    //  gets sent over network, instead of being interpreted here
    void executeCommand(char[] cmd) {
        mShell.addLoggedInput(mAccessTag, cmd);
    }

    ///TeamMember that would receive keypresses
    ///a member of one team from GameLogicPublic.getActiveTeams()
    ///_not_ always the same member or null
    TeamMember getControlledMember() {
        foreach (Team t; getOwnedTeams()) {
            if (t.active) {
                return t.getActiveMember();
            }
        }
        return null;
    }

    ///The teams associated with this controller
    ///Does not mean any or all the teams can currently be controlled (they
    ///  can still be deactivated by controller)
    //xxx: ok, should be moved directly into GameEngine
    Team[] getOwnedTeams() {
        //xxx: if access map is dynamically changed for any reason, this cache
        //  must be invalidated
        if (!mCachedOwnedTeams.length) {
            GameEngine engine = mShell.serverEngine;
            foreach (Team t; engine.controller.getTeams()) {
                if (engine.checkTeamAccess(mAccessTag, t))
                    mCachedOwnedTeams ~= t;
            }
        }
        return mCachedOwnedTeams;
    }
}





//status information while clients are loading
struct NetLoadState {
    //players and flags if done loading, always same length
    uint[] playerIds;
    bool[] done;
}

struct NetPlayerInfo {
    uint id;
    char[] name;
    char[] teamName;
    Time ping;
}

struct NetTeamInfo {
    Team[] teams;

    struct Team {
        uint playerId;
        ConfigNode teamConf;
    }
}

//xxx: What was that for again? perhaps remove/merge with CmdNetClient
abstract class SimpleNetConnection {
    //new player information was received from the server
    void delegate(SimpleNetConnection sender) onUpdatePlayers;
    //the client should begin loading resources etc., loader will already
    //  contain all game information
    //by calling loader.finish(), clients signal loading is complete
    //loader.finish() will return the (initially paused) game engine
    void delegate(SimpleNetConnection sender, GameLoader loader) onStartLoading;
    //loading state of connected players changed
    void delegate(SimpleNetConnection sender, NetLoadState state) onLoadStatus;
    //all clients finished loading, game is starting
    void delegate(SimpleNetConnection sender, ClientControl control) onGameStart;
    //receiving a chat message
    void delegate(SimpleNetConnection sender, char[] playerName,
        char[] msg) onChat;
    //you are allowed to host a game
    void delegate(SimpleNetConnection sender, uint playerId,
        bool granted) onHostGrant;
    //incoming team info
    void delegate(SimpleNetConnection sender, NetTeamInfo info,
        ConfigNode persistentState) onHostAccept;

    //send a game-independent command (like "say Hi fellas!" or
    //  "pm Player2 Secret message")
    //"game-independent" means the command is not logged/timestamped/passed
    //  through the engine
    void lobbyCmd(char[] cmd);

    //join the game with a team
    //a client can only add one team, multiple calls will replace the client's
    //  team
    //when not called at all, the client will be spectator
    void deployTeam(ConfigNode teamInfo);

    //disconnect
    void close();

    bool connected();

    //returns true if the game is paused because server frames are not available
    bool waitingForServer();
}
