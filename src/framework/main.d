//this handles the main window and controls the drivers (the SDL API kind of
//  forces this design)
module framework.main;


import framework.drawing;
import framework.driver_base;
import framework.event;
import framework.filesystem;
import framework.font;
import framework.globalsettings;
import framework.keybindings;
import framework.sound;
import framework.surface;

import utils.color;
import utils.configfile;
import utils.factory;
import utils.log;
import utils.misc;
import utils.path;
import utils.perf;
import utils.rect2;
import utils.time;
import utils.vector2;

import str = utils.string;

Framework gFramework;

abstract class FrameworkDriver : Driver {
    ///flip screen after drawing
    abstract void flipScreen();

    abstract void processInput();

    abstract DriverInputState getInputState();
    abstract void setInputState(in DriverInputState state);
    abstract void setMousePos(Vector2i p);

    abstract VideoWindowState getVideoWindowState();
    ///returns success (for switching the video mode, only)
    abstract bool setVideoWindowState(in VideoWindowState state);
    ///returns desktop video resolution at program start
    abstract Vector2i getDesktopResolution();

    ///sleep for a specific time (grr, Phobos doesn't provide this)
    abstract void sleepTime(Time relative);
}

struct DriverInputState {
    bool mouse_visible = true;
    bool mouse_locked;
}

version(Windows) {
    alias void* SysWinHandle;
} else {
    alias uint SysWinHandle;
}

struct VideoWindowState {
    bool video_active;
    ///sizes for windowed mode/fullscreen
    Vector2i window_size, fs_size;
    int bitdepth;
    bool fullscreen;
    string window_caption;
    Surface window_icon;
    string window_icon_res_win32;
    SysWinHandle window_handle;

    Vector2i actualSize() {
        return fullscreen ? fs_size : window_size;
    }
}

private const Time cFPSTimeSpan = timeSecs(1); //how often to recalc FPS

///what mouse cursor to display
struct MouseCursor {
    bool visible = true;
    //custom mouse cursor graphic
    //if this is null, the standard cursor is displayed
    Surface graphic;
    //offset to "click point" for custom cursor
    Vector2i graphic_spot;

    const None = MouseCursor(false);
    const Standard = MouseCursor();
}

const cDrvBase = "base";
const cDrvDraw = "draw";

private {
    SettingVar!(int) gFrameRate;
    Setting gEnableSound;
}

static this() {
    gFrameRate = gFrameRate.Add("fps.max", 100);
    gEnableSound = addSetting("sound.enable", true);

    new Framework();
}

class Framework {
    private {
        FrameworkDriver mDriver;
        DrawDriver mDrawDriver;
        bool mDriverReload;
        ConfigNode mLastWorkingDriver;

        bool mShouldTerminate;

        //misc singletons, lol
        Log mLog;

        Time mFPSLastTime;
        uint mFPSFrameCount;
        float mFPSLastValue;
        //fixedFramerate() property (0 disables)
        //to get actual, final fixed framerate, timePerFrame()
        int mFps = 0;

        //contains keystate (key down/up) for each key; indexed by Keycode
        bool[] mKeyStateMap;

        //for mouse handling
        Vector2i mMousePos;
        MouseCursor mMouseCursor;
        bool mDisableMouseMoveEvent;

        //base drivers can report that the app is hidden, which will stop
        //  redrawing (no more onFrame events)
        bool mAppVisible, mAppFocused;
    }

    private this() {
        mLog = registerLog("fw");

        assert(!gFramework, "Framework is a singleton");
        gFramework = this;

        mKeyStateMap.length = Keycode.max - Keycode.min + 1;

        gEnableSound.onChange ~= &onChangeEnableSound;
    }

    //call this if you actually want to create a window and so on
    void initialize() {
        replaceDriver();
    }

    private void replaceDriver() {
        //Trace.formatln("replace:");
        //gFrameworkSettings.dump((string s) { Trace.format("{}", s); } );

        //deinit old driver
        VideoWindowState vstate;
        DriverInputState istate;
        if (mDriver) {
            vstate = mDriver.getVideoWindowState();
            istate = mDriver.getInputState();
        }

        killDriver();

        //new driver
        mDriver = createDriver!(FrameworkDriver)(getSelectedDriver(cDrvBase));

        //for graphics (pure SDL, OpenGL...)
        mDrawDriver = createDriver!(DrawDriver)(getSelectedDriver(cDrvDraw));

        gFontManager.loadDriver(getSelectedDriver(
            gFontManager.getDriverType()));

        reloadSoundDriver();

        mDriver.setVideoWindowState(vstate);
        mDriver.setInputState(istate);
        mAppVisible = true;
        mAppFocused = true;

        mLog.minor("reloaded driver");
    }

    private void reloadSoundDriver() {
        string driver = "sound_none";
        //special exception for simple activation/deactivation of sound
        //disabling sound simply overrides normal sound driver choice
        if (gEnableSound.get!(bool)()) {
            driver = getSelectedDriver(gSoundManager.getDriverType());
        }
        gSoundManager.releaseCaches(CacheRelease.Hard);
        gSoundManager.unloadDriver();
        gSoundManager.loadDriver(driver);
    }

    private void onChangeEnableSound(Setting s) {
        reloadSoundDriver();
    }

    void scheduleDriverReload() {
        mDriverReload = true;
    }

    private void checkDriverReload() {
        if (mDriverReload) {
            mDriverReload = false;
            replaceDriver();
        }
    }

    private void killDriver() {
        releaseCaches(true);

        gFontManager.unloadDriver();
        gSoundManager.unloadDriver();

        if (mDrawDriver) {
            mDrawDriver.destroy();
            mDrawDriver = null;
        }

        if (mDriver) {
            mDriver.destroy();
            mDriver = null;
        }
    }

    void deinitialize() {
        killDriver();
        // .free() all Surfaces and then do deferred_free()?
    }

    public FrameworkDriver driver() {
        return mDriver;
    }

    public DrawDriver drawDriver() {
        return mDrawDriver;
    }

    //--- Surface handling

    ///create a copy of the screen contents
    Surface screenshot() {
        return mDrawDriver.screenshot();
    }

    //--- key stuff

    private void updateKeyState(in KeyInfo infos, bool state) {
        assert(infos.code >= Keycode.min && infos.code <= Keycode.max);
        mKeyStateMap[infos.code - Keycode.min] = state;
    }

    /// Query if key is currently pressed down (true) or not (false)
    final bool getKeyState(Keycode code) {
        assert(code >= Keycode.min && code <= Keycode.max);
        return mKeyStateMap[code - Keycode.min];
    }

    /// query if any of the checked set of keys is currently down
    ///     keyboard = check normal keyboard keys
    ///     mouse = check mouse buttons
    bool anyButtonPressed(bool keyboard = true, bool mouse = true) {
        for (auto n = Keycode.min; n <= Keycode.max; n++) {
            auto ismouse = keycodeIsMouseButton(n);
            if (!(ismouse ? mouse : keyboard))
                continue;
            if (getKeyState(n))
                return true;
        }
        return false;
    }

    /// return if Modifier is applied
    public bool getModifierState(Modifier mod) {
        switch (mod) {
            case Modifier.Alt:
                return getKeyState(Keycode.RALT) || getKeyState(Keycode.LALT);
            case Modifier.Control:
                return getKeyState(Keycode.RCTRL) || getKeyState(Keycode.LCTRL);
            case Modifier.Shift:
                return getKeyState(Keycode.RSHIFT)
                    || getKeyState(Keycode.LSHIFT);
            default:
        }
        return false;
    }

    /// return true if all modifiers in the set are applied
    /// empty set applies always
    bool getModifierSetState(ModifierSet mods) {
        return (getModifierSet() & mods) == mods;
    }

    ModifierSet getModifierSet() {
        ModifierSet mods;
        for (uint n = Modifier.min; n <= Modifier.max; n++) {
            if (getModifierState(cast(Modifier)n))
                mods |= 1 << n;
        }
        return mods;
    }

    ///This will move the mouse cursor to screen center and keep it there
    ///It is probably a good idea to hide the cursor first, as it will still
    ///be moveable and generate events, but "snap" back to the locked position
    ///Events and mousePos() will show the mouse cursor standing at its locked
    ///position and only show relative motion
    void mouseLocked(bool set) {
        auto state = mDriver.getInputState();
        state.mouse_locked = set;
        mDriver.setInputState(state);
    }
    bool mouseLocked() {
        return mDriver.getInputState().mouse_locked;
    }

    ///appaerance of the mouse pointer when it is inside the video window
    void mouseCursor(MouseCursor cursor) {
        mMouseCursor = cursor;

        //hide/show hardware mouse cursor (the one managed by SDL)
        auto state = mDriver.getInputState();
        bool vis = mMouseCursor.visible && !mMouseCursor.graphic;
        if (state.mouse_visible != vis) {
            state.mouse_visible = vis;
            mDriver.setInputState(state);
        }
    }
    MouseCursor mouseCursor() {
        return mMouseCursor;
    }

    private void drawSoftCursor(Canvas c) {
        if (!mMouseCursor.visible || !mMouseCursor.graphic)
            return;
        c.draw(mMouseCursor.graphic, mousePos() - mMouseCursor.graphic_spot);
    }

    Vector2i mousePos() {
        return mMousePos;
    }

    //looks like this didn't trigger an event in the old code either
    void mousePos(Vector2i newPos) {
        //never generate movement event
        mDisableMouseMoveEvent = true;
        mDriver.setMousePos(newPos);
        mDisableMouseMoveEvent = false;
    }

    //--- driver input callbacks

    //xxx should be all package or so, but that doesn't work out
    //  sub packages can't access parent package package-declarations, wtf?

    //called from framework implementation... relies on key repeat
    void driver_doKeyEvent(KeyInfo infos) {
        updateKeyState(infos, infos.isDown);

        //xxx: huh? shouldn't that be done by the OS' window manager?
        if (infos.isDown && infos.code == Keycode.F4
            && getModifierState(Modifier.Alt))
        {
            doTerminate();
        }

        if (!onInput)
            return;

        InputEvent event;
        event.keyEvent = infos;
        event.isKeyEvent = true;
        event.mousePos = mousePos();
        onInput(event);
    }

    //rel is the relative movement; needed for locked mouse mode
    void driver_doUpdateMousePos(Vector2i pos, Vector2i rel) {
        if ((mMousePos == pos && rel == Vector2i(0)) || mDisableMouseMoveEvent)
            return;

        mMousePos = pos;

        if (onInput) {
            InputEvent event;
            event.isMouseEvent = true;
            event.mousePos = event.mouseEvent.pos = mMousePos;
            event.mouseEvent.rel = rel;
            onInput(event);
        }
    }

    //Note: for the following two events, drivers have to make sure they
    //      are only called when values actually changed

    void driver_doFocusChange(bool focused) {
        mAppFocused = focused;
        if (onFocusChange)
            onFocusChange(focused);
    }

    //the main app window was hidden or restored
    void driver_doVisibilityChange(bool visible) {
        mAppVisible = visible;
    }

    //--- video mode

    void setVideoMode(Vector2i size, int bpp, bool fullscreen) {
        VideoWindowState state = mDriver.getVideoWindowState();
        if (fullscreen) {
            state.fs_size = size;
        } else {
            state.window_size = size;
        }
        if (bpp >= 0) {
            state.bitdepth = bpp;
        }
        state.fullscreen = fullscreen;
        state.video_active = true;
        mDriver.setVideoWindowState(state);
    }

    //version for default arguments
    void setVideoMode(Vector2i size, int bpp = -1) {
        setVideoMode(size, bpp, fullScreen());
    }

    bool videoActive() {
        return mDriver.getVideoWindowState().video_active;
    }

    bool fullScreen() {
        return mDriver.getVideoWindowState().fullscreen;
    }

    Vector2i screenSize() {
        VideoWindowState state = mDriver.getVideoWindowState();
        return state.fullscreen ? state.fs_size : state.window_size;
    }

    ///desktop screen resolution at program start
    Vector2i desktopResolution() {
        return mDriver.getDesktopResolution();
    }

    //--- time stuff

    /// return number of invocations of onFrame pro second
    float FPS() {
        return mFPSLastValue;
    }

    /// set a fixed framerate / a maximum framerate
    /// fps = framerate, or 0 to disable fixed framerate
    /// NOTE: also see gFrameRate
    void fixedFramerate(int fps) {
        mFps = fps;
    }
    int fixedFramerate() {
        return mFps;
    }

    //frame-time from forced fps settings; 0 if no forced fps
    //foced driver vsync (OpenGL) may override this implicitly
    Time timePerFrame() {
        //setting fps via fixedFramerate overrides gFrameRate
        int forcefps = max(gFrameRate.get(), 0);
        if (mFps > 0) {
            forcefps = mFps;
        }

        if (forcefps <= 0) {
            return Time.Null;
        } else {
            return timeMusecs(1000000/forcefps);
        }
    }

    //--- main loop

    /// Main-Loop
    void run() {
        Time waitTime;
        while(!mShouldTerminate) {
            // recalc FPS value
            Time curtime = timeCurrentTime();
            if (curtime >= mFPSLastTime + cFPSTimeSpan) {
                mFPSLastValue = (cast(float)mFPSFrameCount
                    / (curtime - mFPSLastTime).msecs) * 1000.0f;
                mFPSLastTime = curtime;
                mFPSFrameCount = 0;
            }

            //xxx: whereever this should be?
            checkDriverReload();

            //this also does deferred free
            gFontManager.tick();
            gSoundManager.tick();
            mDrawDriver.tick();
            mDriver.tick();

            //mInputTime.start();
            mDriver.processInput();
            //mInputTime.stop();

            if (onUpdate) {
                onUpdate();
            }

            //no drawing when the window is invisible
            if (mAppVisible) {
                Canvas c = mDrawDriver.startScreenRendering();
                c.clear(Color(0));
                if (onFrame) {
                    onFrame(c);
                }
                drawSoftCursor(c);
                mDrawDriver.stopScreenRendering();
                mDriver.flipScreen();
                c = null;
            }

            //wait for fixed framerate?
            Time time = timeCurrentTime();
            //target waiting time
            waitTime += timePerFrame() - (time - curtime);
            //even if you don't wait, yield the rest of the timeslice
            waitTime = waitTime > Time.Null ? waitTime : Time.Null;
            mDriver.sleepTime(waitTime);

            //real frame time
            Time cur = timeCurrentTime();
            //subtract the time that was really waited, to cover the
            //inaccuracy of Driver.sleepTime()
            waitTime -= (cur - time);

            //it's a hack!
            //used by toplevel.d
            if (onFrameEnd)
                onFrameEnd();

            mFPSFrameCount++;
        }
    }

    void sleep(Time t) {
        assert(!!mDriver);
        mDriver.sleepTime(t);
    }

    private bool doTerminate() {
        bool term = true;
        if (onTerminate != null) {
            term = onTerminate();
        }
        if (term) {
            terminate();
        }
        return term;
    }

    /// requests main loop to terminate
    void terminate() {
        mShouldTerminate = true;
    }

    //--- misc

    void setCaption(string caption) {
        VideoWindowState state = mDriver.getVideoWindowState();
        state.window_caption = caption;
        mDriver.setVideoWindowState(state);
    }

    void setIcon(Surface icon, string win32ResItem = "") {
        VideoWindowState state = mDriver.getVideoWindowState();
        state.window_icon = icon;
        state.window_icon_res_win32 = win32ResItem;
        mDriver.setVideoWindowState(state);
    }

    bool appFocused() {
        return mAppFocused;
    }

    bool appVisible() {
        return mAppVisible;
    }

    //force: for sounds; if true, sounds are released too, but this leads to
    //a hearable interruption
    int releaseCaches(bool force) {
        CacheRelease pri = force ? CacheRelease.Hard : CacheRelease.Soft;
        if (!mDriver)
            return 0;
        int count;
        foreach (r; gCacheReleasers) {
            count += r(pri);
        }
        count += gFontManager.releaseCaches(pri);
        count += gSoundManager.releaseCaches(pri);
        count += mDriver.releaseCaches(pri);
        count += mDrawDriver.releaseCaches(pri);
        return count;
    }

    void driver_doVideoInit() {
        mDrawDriver.initVideoMode(mDriver.getVideoWindowState().actualSize());
        if (onVideoInit) {
            onVideoInit();
        }
    }

    void driver_doTerminate() {
        bool term = true;
        if (onTerminate != null) {
            term = onTerminate();
        }
        if (term) {
            terminate();
        }
    }

    int weakObjectsCount() {
        int objs = 0;
        objs += gFontManager.usedObjects();
        objs += gSoundManager.usedObjects();
        objs += mDriver.usedObjects();
        objs += mDrawDriver.usedObjects();
        return objs;
    }

    void preloadResource(Resource res) {
        if (cast(Surface)res) {
            if (mDrawDriver)
                mDrawDriver.requireDriverResource(res);
        } else if (cast(Sample)res) {
            if (auto d = gSoundManager.driver)
                d.requireDriverResource(res);
        }
    }

    //--- events

    /// executed when receiving quit event from framework
    /// return false to abort quit
    public bool delegate() onTerminate;
    /// Event raised every frame before drawing starts#
    /// Input processing and time advance should happen here
    public void delegate() onUpdate;
    /// Event raised when the screen is repainted
    public void delegate(Canvas canvas) onFrame;
    /// Input events, see InputEvent
    public void delegate(InputEvent input) onInput;
    /// Event raised on initialization (before first onFrame) and when the
    /// screen size or format changes.
    public void delegate() onVideoInit;

    /// Called after all work for a frame is done
    public void delegate() onFrameEnd;

    ///called when the application gets or loses input focus (also on minimize)
    public void delegate(bool focused) onFocusChange;
}
