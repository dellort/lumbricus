module common.common;

import framework.config;
import common.resources;
import common.resset;
import framework.commandline;
import framework.event;
import framework.filesystem;
import framework.font;
import framework.globalsettings;
import framework.keybindings;
import framework.main;
import utils.timesource;
import framework.i18n;
import gui.global;
import utils.array;
import utils.time;
import utils.configfile;
import utils.log, utils.output;
import utils.misc;
import utils.path;
import utils.perf;
import utils.gzip;
import utils.vector2;

public Common globals;

//don't know where to put your stuff? just dump it here!
//mainly supposed to manage all the singletons...

static this() {
    //singletons are cool
    globals = new Common();
}

//the big singleton...
//also contains some important initialization code
class Common {
    LogStruct!("common") log;
    CommandBucket cmdLine;
    //hack for now; needed by gameview.d and welcome.d; they invoke execute()
    CommandLine real_cmdLine;

    //high resolution timers which are updated each frame, or so
    //debugstuff.d will reset them all!
    PerfTimer[char[]] timers;
    long[char[]] counters;
    size_t[char[]] size_stats;

    //moved to here from TopLevel
    //xxx move this to where-ever
    Translator localizedKeynames;

    //globally capture input
    //if a delegate returns true, propagation of the event is stopped, and on
    //  false, the next delegate will tried. if no delegate wants to catch the
    //  input, it is propagated to the GUI.
    alias bool delegate(InputEvent event) CatchInput;
    CatchInput[] catchInput;

    private this() {
        cmdLine = new CommandBucket();
        localizedKeynames = localeRoot.bindNamespace("keynames");
    }

    void initGUIStuff() {

        setVideoFromConf();
        if (!gFramework.videoActive) {
            //this means we're F****D!!1  ("FOOLED")
            log.error("couldn't initialize video");
            //end program in some way
            throw new Exception("can't continue");
        }

        //xxx there was some reason why this was here (after video init), but
        //  this reason disappeared; now where should this be moved to?
        //- maybe create a global "filesystem available" event?

        //GUI resources, this is a bit off here
        gGuiResources = gResources.loadResSet("guires.conf");

        gFontManager.readFontDefinitions(loadConfig("fonts.conf"));
    }

    const cVideoFS = "video.fullscreen";
    const cVideoSizeWnd = "video.size.window";
    const cVideoSizeFS = "video.size.fullscreen";

    static this() {
        addSetting!(bool)(cVideoFS, false);
        addSetting!(Vector2i)(cVideoSizeWnd, Vector2i(0));
        addSetting!(Vector2i)(cVideoSizeFS, Vector2i(0));
    }

    //read configuration from video.conf and set video mode
    void setVideoFromConf(bool toggleFullscreen = false) {
        bool fs = getSetting!(bool)(cVideoFS);
        if (toggleFullscreen)
            fs = !gFramework.fullScreen;
        Vector2i res = getSetting!(Vector2i)(fs ? cVideoSizeFS : cVideoSizeWnd);
        //if nothing set, default to desktop resolution
        if (res.x == 0 || res.y == 0) {
            if (fs)
                res = gFramework.desktopResolution;
            else
                res = Vector2i(1024, 768);
        }
        gFramework.setVideoMode(res, 0, fs);
    }

    void saveVideoConfig() {
        bool fs = gFramework.fullScreen;
        //xxx might be slightly different from code before
        setSetting!(bool)(cVideoFS, fs);
        Vector2i res = gFramework.screenSize;
        setSetting!(Vector2i)(fs ? cVideoSizeFS : cVideoSizeWnd, res);
        saveSettings();
    }

    //translate into translated user-readable string
    char[] translateKeyshortcut(BindKey key) {
        if (!localizedKeynames)
            return "?";
        char[] res = localizedKeynames(translateKeycodeToKeyID(key.code), "?");
        foreachSetModifier(key.mods,
            (Modifier mod) {
                res = localizedKeynames(modifierToString(mod), "?") ~ "+" ~ res;
            }
        );
        return res;
    }

    //xxx maybe move to framework
    char[] translateBind(KeyBindings b, char[] bind) {
        BindKey k;
        if (!b.readBinding(bind, k)) {
            return "-";
        } else {
            return translateKeyshortcut(k);
        }
    }

    //debugging crap

    public PerfTimer newTimer(char[] name) {
        auto pold = name in timers;
        if (pold)
            return *pold;
        auto t = new PerfTimer(true);
        timers[name] = t;
        return t;
    }

    void incCounter(char[] name, long amount = 1) {
        long* pold = name in counters;
        if (!pold) {
            counters[name] = 0;
            pold = name in counters;
        }
        (*pold) += amount;
    }
    void setCounter(char[] name, long cnt) {
        counters[name] = cnt;
    }

    void setByteSizeStat(char[] name, size_t size) {
        size_stats[name] = size;
    }
}
