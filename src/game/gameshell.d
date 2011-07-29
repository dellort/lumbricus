module game.gameshell;

import common.resources;
import common.resset;
import framework.config;
import framework.filesystem;
import framework.i18n;

import game.controller;
import game.core;
import game.events;
import game.game;
import game.gfxset;
import game.input;
import game.plugins;
import game.levelgen.generator;
import game.levelgen.landscape;
import game.levelgen.level;
import game.levelgen.renderer;
import game.setup;
import game.temp;
import game.weapon.weapon;

import utils.archive;
import utils.configfile;
import utils.log;
import utils.misc;
import utils.mybox;
import utils.perf;
import utils.random;
import utils.strparser;
import utils.time;
import utils.vector2;
import utils.timesource;
import utils.queue;
import str = utils.string;
import strparser = utils.strparser;

import utils.stream;
import std.math;


//the optimum length of the input queue in network mode (i.e. what the engine
//  will try to reach)
//if the queue gets longer, game speed will be increased to catch up
//xxx: for optimum performance, this should be calculated dynamically based
//     on connection jitter (higher values give more jitter protection, but
//     higher introduced lag)
enum int cOptimumInputLag = 1;

private LogStruct!("gameshell") log;


//for each demo frame, write the game hash value (engineHash())
//could be easily made a runtime option
//NOTE: when playing demos, the hash value will be checked if the file contains
//      hash values (actually, it's per LogEntry)
enum bool WriteDemoHashFrames = true;

//check hashes on replays - might put a little pressure on the GC, because each
//  frame a LogEntry is appended to the replay log
enum bool ReplayHashFrames = true;

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

        //demo stuff
        bool mEnableDemoRecording = true;
        //ConfigNode mDemoFile;
        PipeOut mDemoOutput;
        //null = no demo reading
        GameShell.InputLog* mDemoInput;
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

    static GameLoader CreateNewGame(GameConfig cfg, bool network = false) {
        auto r = new GameLoader();
        //xxx: should level==null really be allowed?
        if (!cfg.level) {
            auto gen = new GenerateFromSaved(new LevelGeneratorShared(),
                cfg.saved_level);
            cfg.level = gen.render();
        }
        assert(!!cfg.level);
        r.mGameConfig = cfg;
        r.mNetwork = network;
        r.doInit();
        return r;
    }

    static GameLoader CreateNetworkGame(GameConfig cfg,
        void delegate(GameShell shell) loadDone)
    {
        auto r = CreateNewGame(cfg, true);
        r.onLoadDone = loadDone;
        return r;
    }

    //filename_prefix is e.g. "last_demo", and the code will try to read the
    //  files last_demo.conf and last_demo.dat
    static GameLoader CreateFromDemo(string filename) {
        try {
            return doCreateFromDemo(filename);
        } catch (CustomException e) {
            e.msg = myformat("when trying to load demo file '%s': %s", filename,
                e.msg);
            throw e;
        }
    }

    private static GameLoader doCreateFromDemo(string filename) {
        auto r = new GameLoader();
        auto lg = new GameShell.InputLog;
        r.mDemoInput = lg;

        auto f = gFS.open(filename);
        string data = cast(string)f.readAll();
        scope(exit) f.close();

        //xxx should catch & convert utf-8 exception (dammit)
        str.validate(data);

        auto demo = parseDemoFile(data);

        auto cfg = new GameConfig();
        r.mGameConfig = cfg;
        cfg.load(demo.config.getSubNode("game_config"));
        //xxx move elsewhere or whatever
        if (!cfg.level) {
            auto gen = new GenerateFromSaved(new LevelGeneratorShared(),
                cfg.saved_level);
            cfg.level = gen.render();
        }

        lg.entries = demo.log;
        //NOTE: the last written command should be the DEMO_END pseudo-command,
        //  but no need to specially catch this; the following code does the
        //  same anyway
        if (lg.entries.length > 0)
            lg.end_ts = lg.entries[$-1].timestamp;

        r.doInit();
        return r;
    }

    private void doInit() {
        //save last played level functionality
        //xxx should this really be here
        if (mGameConfig.level.saved) {
            saveConfig(mGameConfig.level.saved, "lastlevel.conf");
        }

        //this doesn't really make sense, but is a helpful hack for now
        mEnableDemoRecording = mGameConfig.management
            .getValue!(bool)("enable_demo_recording", false);

        //never record a demo when playing back a demo
        if (!!mDemoInput)
            mEnableDemoRecording = false;

        if (mEnableDemoRecording) {
            auto demoConf = new ConfigNode();
            demoConf.addNode("game_config", mGameConfig.save());

            try {
                auto outstr = gFS.open("last_demo.demo", "wb");
                outstr.set_line_buffered();
                mDemoOutput = outstr.pipeOut();
                startDemoFile(mDemoOutput, demoConf);
            } catch (CustomException e) {
                mDemoOutput = mDemoOutput.init;
                log.warn("Failed to create demo file (%s). Demo"
                    " writing disabled.", e.msg);
            }
        }

        if (!mDemoOutput.isNull())
            log.notice("Demo recording enabled!");

        mShell = new GameShell();
        mShell.mGameConfig = mGameConfig;
        mShell.mMasterTime = new TimeSource("GameShell/MasterTime");
        if (mNetwork) {
            mShell.mMasterTime.paused = true;
            //use server timestamps
            mShell.mUseExternalTS = true;
        }
        mShell.mGameTime = new TimeSourceFixFramerate("GameTime",
            mShell.mMasterTime, cFrameLength);
        auto it = new TimeSourceSimple("GameShell/Interpolated");
        it.reset(mShell.mGameTime.current);
        mShell.mInterpolateTime = it;

        if (!mDemoOutput.isNull()) {
            mShell.mDemoOutput = mDemoOutput;
        }

        assert(!!mGameConfig.level);
        mShell.mEngine = new GameEngine(mGameConfig,
            mShell.mGameTime, mShell.mInterpolateTime);
        auto engine = mShell.mEngine;

        new GameController(engine);

        //input for this never takes the "normal" path, but it's needed for
        //  input validation
        engine.input.addSub(mShell.mInput);

        mGfx = new GfxSet(engine, mGameConfig);

        auto plugins = new PluginBase(engine, mGameConfig);

        mResPreloader = mGfx.createPreloader();
        mShell.mGfx = mGfx;

        //test for time skip on loading
        //gFramework.sleep(timeSecs(2));
    }

    GameShell finish() {
        assert(!!mResPreloader, "loading already finished?");

        //just to be sure caller didn't mess up
        mResPreloader.loadAll();
        addToResourceSet(mShell.mEngine.resources, mResPreloader.list);
        mResPreloader = null;

        mGfx.finishLoading();

        GameEngine rengine = GameEngine.fromCore(mShell.mEngine);
        rengine.initGame();

        mShell.mEngine.singleton!(GameController)().finishLoading();

        if (mDemoInput) {
            //changed because replays were ditched (and it looks nicer)
            mShell.playbackDemo(*mDemoInput);
        }

        //all resources have been loaded, and that took a while => skip time
        //if this is omitted, the TimeSource implementation will print a warning
        //  if loading was slow
        //a good way to test this is to comment out the sleep call in doInit()
        //xxx setting pause while it's loaded etc. didn't work for some reason
        //xxx-2 should do this after waiting a until next frame in gsmetask.d
        mShell.mMasterTime.resetTime();

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
        GameCore mEngine;
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
        ulong mSingleStep; //if != 0, singlestep is enabled
        GameConfig mGameConfig;
        GfxSet mGfx;
        InputLog mCurrentInput;
        bool mLogReplayInput;  //for demo playback
        InputLog mReplayInput;
        bool mReplayMode; //currently replaying
        bool mUseExternalTS; //timestamp advancing is controlled externally
        bool mExtIsLagging;
        debug bool mPrintFrameTime;
        Hasher mGameHasher;

        //abuse AA as set
        bool[Object] mPauseBlockers;

        //for undeterministic input controls
        InputGroup mInput;

        //time used for interpolated drawing
        TimeSourceSimple mInterpolateTime;
        //actual time after the execution of the last frame
        Time mLastFrameRealTime;

        //bool mEnableDemoPlayback;
        //if !.isNull(), enable demo recording
        PipeOut mDemoOutput;

        bool mSOMETHINGISWRONG; //good variable names are an art
    }
    bool terminated;  //set to exit the game instantly

    struct LogEntry {
        long timestamp;
        string access_tag;
        string cmd;

        //the hash is done right before the input is executed
        //only valid if !is EngineHash.init
        EngineHash hash;

        string toString() {
            return myformat("ts=%s, access='%s': '%s'", timestamp, access_tag,
                cmd);
        }
    }

    struct InputLog {
        LogEntry[] entries;
        long end_ts;

        InputLog clone() {
            auto res = this;
            res.entries = res.entries.dup;
            return res;
        }
    }

    //called before a frame (and inputs) are executed
    void delegate(GameShell shell, long timestamp) onPreFrame;
    //called after the engine frame marked with timestamp has been executed
    void delegate(GameShell shell, long timestamp) onPostFrame;

    //use GameLoader.Create*() instead
    private this() {
        mInput = new InputGroup();
        mInput.add("pause", &inpSetPaused);
        mInput.add("slow_down", &inpSetSlowdown);
        mInput.add("single_step", &inpSinglestep);
    }

    //xxx: not networking save, I guess
    private bool inpSetPaused(cstring s) {
        bool nstate = !mGameTime.paused;
        tryFromStr(s, nstate);
        log.minor("pause: %s", nstate);
        pauseBlock(nstate, this);
        return true;
    }
    private bool inpSetSlowdown(cstring s) {
        float state = tryFromStrDef(s, 1.0f);
        if (state != state)
            return false;
        log.minor("slowdown: %s", state);
        mGameTime.slowDown = state;
        return true;
    }
    private bool inpSinglestep(cstring s) {
        int step = tryFromStrDef(s, 1);
        mSingleStep += max(step, 0);
        return true;
    }

    void logAsyncError(long timestamp, EngineHash current,
        EngineHash expected)
    {
         if (!mSOMETHINGISWRONG) {
            void woosh() {
                log.error("------------ wooooosh -------------");
            }
            woosh();
            log.error("oh hi, something is severely wrong");
            log.error("current hash: %s", current);
            log.error("LogEntry/Network hash: %s", expected);
            log.error("timestamp: %s", mTimeStamp);
            log.error("not bothering you anymore, enjoy your day");
            mSOMETHINGISWRONG = true;
            woosh();
        }
    }

    private void execEntry(LogEntry e) {
        //empty commands are used for hash frames in demos
        bool for_hash = e.cmd.length == 0;

        if (!for_hash)
            log("exec input: %s", e);
        assert(mTimeStamp == e.timestamp);

        //check hash (more a special case for demo replaying)
        //if e.hash is invalid, e is fresh input (or the hash wasn't stored)
        if (e.hash !is EngineHash.init) {
            auto expect = engineHash();
            if (expect != e.hash) {
                logAsyncError(mTimeStamp, expect, e.hash);
            }
        }

        //hopefully not too spaghetti code
        //xxx: could store hash for each LogEntry (not only hash frames)
        //     but right now: exactly 1 timestamp each hash check => simpler
        bool hash_stuff(bool want_hash_frame) {
            if (!for_hash)
                return true;
            //it's a hash frame
            if (!want_hash_frame)
                return false;
            //calculate hash if it hasn't been done yet
            if (e.hash is EngineHash.init)
                e.hash = engineHash();
            return true;
        }

        if (!mReplayMode && hash_stuff(WriteDemoHashFrames)) {
            writeDemoEntry(e);
        }

        if (!for_hash) {
            if (!mEngine.input.execCommand(e.access_tag, e.cmd))
                log.minor("ignore net input: '%s':'%s'", e.access_tag, e.cmd);
        }
    }

    //command to be executed by GameEngine.executeCommand()
    //this is logged/timestamped for networking, snapshot/replays, and demo mode
    //NOTE: cmd=="" is abused as a special case for demo hash frames
    void addLoggedInput(cstring access_tag, cstring cmd, long cmdTimeStamp = -1) {
        //yeh, this might be a really bad idea
        if (replayMode() && str.startsWith(cmd, "weapon_fire")) {
            replaySkip();
            return;
        }

        //and this may be a bad idea too - execute non-timestamped commands
        //may or may not cause desynchronization in network mode (not sure)
        if (mInput.execCommand(access_tag, cmd))
            return;


        LogEntry e;

        //XXXTANGO: sad memory allocations that weren't here before
        e.access_tag = access_tag.idup;
        e.cmd = cmd.idup;

        //assume time increases monotonically => list stays always sorted
        if (cmdTimeStamp >= 0)
            e.timestamp = cmdTimeStamp;
        else
            e.timestamp = mTimeStamp;

        if (e.cmd.length)
            log("received input: %s", e);

        if (mReplayMode) {
            log.minor("previous input denied, because in replay mode");
            return;
        }

        mCurrentInput.entries ~= e;
    }

    //public access
    void executeCommand(string access_tag, string cmd) {
        addLoggedInput(access_tag, cmd);
    }

    //for now this does:
    //- increase the intraframe time (time between engine frames for
    //  interpolated drawing)
    //  the time used is mEngine.interpolateTime / mInterpolateTime
    //- execute a game frame if necessary (for simulation)
    void frame() {
        auto interpol = mInterpolateTime;

        void exec_frame(Time overdue) {
            //xxx this was failing in multiplayer because an empty command
            //    with TS mTimeStamp was added to the end of the list
            //    (which is at mTimeStampAvail), thus destroying sort order
            if (!mReplayMode && !mUseExternalTS) {
                //pseudo hash command to insert a hash frame (see execFrame())
                //always generated, but execEntry() might throw it away
                addLoggedInput("", "");
            }

            //this is the time it _should_ have been when mGameTime was updated
            //this way, interpolation can also correct for varying duration of
            //  the doFrame() call
            mLastFrameRealTime = timeCurrentTime() - overdue;
            doFrame();

            /+
            ok... interpolateTime is mainly used for drawing, and it doesn't
                make sense to update it when nothing is drawn; even worse, if
                some code relies on TimeSourcePublic.difference, it will be all
                messed up because it "misses" the "difference" time for frames
                when it wasn't called
            //skip to next frame, if there's some time "left"
            auto gt = mGameTime.current;
            if (interpol.current < gt)
                interpol.update(gt);
            +/

        }

        if (mUseExternalTS) {
            //external timestamps (network mode, from setFrameReady())
            //this code tries to keep the input queue length (local lag)
            //  at cOptimumInputLag by varying game speed
            //how far the server is ahead
            int lag = cast(int)(mTimeStampAvail - mTimeStamp);
            //log("lag = %s",lag);
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
            mGameTime.update(&exec_frame, maxFrames);
        } else {
            if (mSingleStep) {
                //xxx: I don't know if there are any desynchronization issues by
                //  creating small time drifts due to pause/update order or such
                mMasterTime.update();
                if (mGameTime.paused)
                    mGameTime.paused = false;
                mGameTime.update(
                    (Time overdue) {
                        assert(mSingleStep > 0);
                        mSingleStep--; exec_frame(overdue);
                    }, cast(int)mSingleStep);
                if (mSingleStep == 0)
                    mGameTime.paused = true;
            } else {
                mMasterTime.update();
                mGameTime.update(&exec_frame);
            }
        }

        if (mGameTime.paused || mSingleStep) {
            //interpolation off
            //this call is also needed to make TimeSourcePublic.difference = 0
            interpol.update(max(interpol.current, mGameTime.current));
        } else if (mLastFrameRealTime !is Time.init) {
            Time cur = mGameTime.current;
            //not anymore -- assert(interpol.current >= cur);
            //allow interpolating 2 frames ahead
            Time next = cur + 2*mGameTime.frameLength();
            Time passed = (timeCurrentTime() - mLastFrameRealTime)
                * mGameTime.slowDown;
            assert(passed >= Time.Null);
            Time newt = cur + passed;
            if (newt > next) {
                newt = next; //because time can't go back
                //debug Trace.formatln("XX, cur=%s next=%s passed=%s",cur,next,
                //    passed);
            }
            assert(newt >= cur);
            //I have no idea why this happens, but of course the time never
            //  should run backwards (would complicate all the user code)
            if (newt < interpol.current)
                newt = interpol.current;
            interpol.update(newt);
        }

        /+ forgotten debugging code
        auto rt = timeCurrentTime();
        static Time last;
        Time dt = rt - last;
        last = rt;

        Trace.formatln("GT: %s / %s ## IT: %s / %s ## RT: %s / %s",
            mGameTime.current, mGameTime.difference, interpol.current,
            interpol.difference, rt, dt);
        +/
    }

    //called by network client, whenever all input events at the passed
    //timeStamp have been fed to the engine
    void setFrameReady(long timeStamp) {
        assert(mUseExternalTS);
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
        //Trace.formatln("ts=%s, hash=%s", mTimeStamp, engineHash().hash);
        debug if (mPrintFrameTime) {
            log("frame time: ts=%s time=%s (%s ns)", mTimeStamp,
                mGameTime.current, mGameTime.current.nsecs);
            mPrintFrameTime = false;
        }

        if (onPreFrame)
            onPreFrame(this, mTimeStamp);

        //execute input at correct time, which is particularly important for
        //replays (input is reused on a snapshot of the deterministic engine)
        while (mCurrentInput.entries.length > 0) {
            LogEntry e = mCurrentInput.entries[0];
            if (e.timestamp > mTimeStamp)
                break;
            //log("pre-exec s=%s %s", mTimeStamp, e);
            assert(e.timestamp == mTimeStamp);
            execEntry(e);
            //remove
            for (int n = 0; n < mCurrentInput.entries.length - 1; n++) {
                mCurrentInput.entries[n] = mCurrentInput.entries[n + 1];
            }
            mCurrentInput.entries.length = mCurrentInput.entries.length - 1;
        }

        mEngine.frame();
        if (onPostFrame)
            onPostFrame(this, mTimeStamp);

        mTimeStamp++;

        //xxx not sure if the input for this frame should be fed to the engine
        //    before debug-dumping, I'm too tired to think about that
        if (mReplayMode) {
            if (mTimeStamp >= mCurrentInput.end_ts) {
                assert(mTimeStamp == mCurrentInput.end_ts);
                if (mMasterTime.slowDown > 1.0f)
                    mMasterTime.slowDown = 1.0f;
                mReplayMode = false;
                log.minor("stop replaying");
            }
        }
    }

    void playbackDemo(InputLog input) {
        mLogReplayInput = false;
        mCurrentInput = input.clone;
        mReplayMode = true;
        log.minor("replay start, time=%s (%s ns)", mGameTime.current,
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
            return (mCurrentInput.end_ts - mTimeStamp)*cFrameLength;
        } else {
            return Time.Null;
        }
    }

    GameCore serverEngine() {
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
        auto hash = EngineHash(mGameHasher.hash_value);
        if (hash is EngineHash.init) {
            hash.hash = 1;
            assert(hash !is EngineHash.init);
        }
        return hash;
    }

    bool paused() {
        return mGameTime.paused();
    }

    //set pause state
    //the idea is that there can be multiple "blockers" which force the game
    //  into pause mode, and the game can only continue if all blockers got
    //  removed
    void pauseBlock(bool pause_enable, Object blocker) {
        assert(!!blocker);
        if (pause_enable) {
            mPauseBlockers[blocker] = true;
        } else {
            mPauseBlockers.remove(blocker);
        }
        mGameTime.paused = mPauseBlockers.length > 0;
        log("pause state=%s blockers=%s", paused(), mPauseBlockers);
    }

    private void writeDemoEntry(LogEntry e) {
        if (!mDemoOutput.isNull()) {
            .writeDemoEntry(mDemoOutput, e);
        }
    }

    //stop and finalize (e.g. close file, actually write demo file...) the demo
    //  recorder; this will also set the end timestamp of the demo
    //NOP if no demo is being recorded
    void stopDemoRecorder() {
        if (!mDemoOutput.isNull()) {
            //pseudo entry with a magic pseudo command to end the demo
            LogEntry e;
            e.timestamp = mTimeStamp;
            e.cmd = "DEMO_END";
            writeDemoEntry(e);
            mDemoOutput.close();
            mDemoOutput = typeof(mDemoOutput).init;
        }
    }

    //can be called for cleanup
    //only closes the demo file for now
    void terminate() {
        stopDemoRecorder();
    }
}

//one endpoint (e.g. network peer, or whatever), that can send input.
//for now, it has control over a given set of teams, and all time one of these
//teams is active, GameControl will actually accept the input and pass it to
//the GameEngine
class ClientControl {
    private {
        GameShell mShell;
        string mAccessTag;
        Team[] mCachedOwnedTeams;
    }

    //for explanation for access_control_tag, see GameEngine.executeCmd()
    //instantiating this directly is "dangerous", because this might
    //  accidentally bypass networking (see CmdNetControl)
    this(GameShell sh, string access_control_tag) {
        assert(!!sh);
        mShell = sh;
        mAccessTag = access_control_tag;
    }

    //NOTE: CmdNetControl overrides this method and redirects it so, that cmd
    //  gets sent over network, instead of being interpreted here
    protected void sendCommand(cstring cmd) {
        mShell.addLoggedInput(mAccessTag, cmd);
    }

    final void execCommand(cstring cmd) {
        if (checkCommand(cmd)) {
            sendCommand(cmd);
        } else {
            log.minor("input denied, don't send: '%s':'%s'", mAccessTag, cmd);
        }
    }

    //whether the game code would likely accept the input
    //(too high network lag may introduce random false results)
    final bool checkCommand(cstring cmd) {
        return mShell.serverEngine.input.checkCommand(mAccessTag, cmd);
    }

    ///TeamMember that would receive keypresses
    ///a member of one team from GameLogicPublic.getActiveTeams()
    ///_not_ always the same member or null
    TeamMember getControlledMember() {
        foreach (Team t; getOwnedTeams()) {
            if (t.active) {
                return t.current();
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
            GameCore engine = mShell.serverEngine;
            auto controller = engine.singleton!(GameController)();
            foreach (Team t; controller.teams()) {
                if (controller.checkAccess(mAccessTag, t))
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
    string name;
    string teamName;
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
    void delegate(SimpleNetConnection sender, NetPlayerInfo player,
        string msg) onChat;

abstract:

    //send a game-independent command (like "say Hi fellas!" or
    //  "pm Player2 Secret message")
    //"game-independent" means the command is not logged/timestamped/passed
    //  through the engine
    void lobbyCmd(string cmd);

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

    void sendChat(string msg);
}

enum string cDemoFileSignature = "=== lumbricus demo file ===\n";
enum string cDemoFileStartLog = "\n=== start log entries ===\n";

//oh how I wish D had real tuples
struct ParseDemoFileResult {
    ConfigNode config;
    GameShell.LogEntry[] log;
}
//this thing is supposed to throw a CustomException on any failure
ParseDemoFileResult parseDemoFile(string data) {
    if (!str.eatStart(data, cDemoFileSignature))
        throwError("no header");
    //hurrr.... but it works
    auto logpos = str.find(data, cDemoFileStartLog);
    if (logpos < 0)
        throwError("no log entries");
    string s_conf = data[0..logpos];
    string s_log = data[logpos + cDemoFileStartLog.length .. $];
    auto config = new ConfigFile(s_conf, "game config embedded in demo file");
    //parse the logs
    GameShell.LogEntry[] log;
    foreach (string s_entry; str.splitlines(s_log)) {
        if (s_entry.length == 0)
            continue;
        //every entry is <timestamp>:<hash>:<accesstag>:<command>
        string[] cols = str.split(s_entry, ":");
        if (cols.length != 4)
            throwError("error in log entry");
        GameShell.LogEntry entry;
        entry.timestamp = strparser.fromStr!(long)(cols[0]);
        entry.hash.hash = strparser.fromStr!(typeof(entry.hash.hash))(cols[1]);
        entry.access_tag = str.simpleUnescape(cols[2]);
        entry.cmd = str.simpleUnescape(cols[3]);
        //for some reason non-unique timestamps are allowed, so it's > not >=
        if (log.length && log[$-1].timestamp > entry.timestamp)
            throwError("unsorted or negative timestamps");
        log ~= entry;
    }
    return ParseDemoFileResult(config.rootnode, log);
}

void startDemoFile(PipeOut dest, ConfigNode config) {
    dest.write(cast(ubyte[])cDemoFileSignature);
    config.writeFile(dest);
    dest.write(cast(ubyte[])cDemoFileStartLog);
}

void writeDemoEntry(PipeOut dest, GameShell.LogEntry e) {
    void dump(cstring s) {
        dest.write(cast(ubyte[])s);
    }
    string demoesc(string s) {
        //escape anything that would make the log part unparseable
        return str.simpleEscape(s, "\n\r:");
    }
    myformat_cb(&dump, "%s:%s:%s:%s\n", e.timestamp, e.hash.hash,
        demoesc(e.access_tag), demoesc(e.cmd));
}
