module common.common;

public import framework.config;
import common.resources;
import common.resset;
import common.settings;
import framework.filesystem;
import framework.framework;
import framework.font;
import framework.commandline;
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
    Output defaultOut;
    CommandLine cmdLine;

    //high resolution timers which are updated each frame, or so
    //toplevel.d will reset them all!
    PerfTimer[char[]] timers;
    long[char[]] counters;

    private {
        //another hack, see addFrameCallback()
        bool delegate()[] mFrameCallbacks;
    }

    //moved to here from TopLevel
    //xxx move this to where-ever
    Translator localizedKeynames;

    //PropertyValue currentLocaleID;

    private this() {
        //currentLocaleID = gSettings.add!(char[])("locale_id", cDefLang);
    }

    void do_init() {
        readLogconf();

        /+yyy
        if (args.getBoolValue("logconsole")) {
            defaultOut = StdioOutput.output;
        }
        +/

        loadColors(loadConfig("colors"));

        ConfigNode langconf = loadConfigDef("language");
        auto langId = langconf.getStringValue("language_id", "");
        initLocale(langId);

        localizedKeynames = localeRoot.bindNamespace("keynames");
    }

    void initGUIStuff() {

        setVideoFromConf();
        if (!gFramework.videoActive) {
            //this means we're F****D!!1  ("FOOLED")
            log("ERROR: couldn't initialize video");
            throw new Exception("can't continue");
        }

        //woo woo load this stuff here, because framework blows up if
        //- you preload images
        //- but video mode is not set yet (or so)
        //- OpenGL (at least nvidia under linux/sdl) refuses to work
        //- but loading images as resources preloads them by default
        //in pure SDL mode, there's a similar error (SDL_DisplayFormat() fails)

        //GUI resources, this is a bit off here
        gGuiResources = gResources.loadResSet("guires.conf");

        gFontManager.readFontDefinitions(loadConfig("fonts"));

    }

    //read configuration from video.conf and set video mode
    void setVideoFromConf(bool toggleFullscreen = false) {
        auto vconf = loadConfigDef("video");
        bool fs = vconf.getValue("fullscreen", false);
        if (toggleFullscreen)
            fs = !gFramework.fullScreen;
        ConfigNode vnode = vconf.getSubNode(fs ? "fs" : "window");
        Vector2i res = Vector2i(vnode.getValue("width", 0),
            vnode.getValue("height", 0));
        //if nothing set, default to desktop resolution
        if (res.x == 0 || res.y == 0) {
            if (fs)
                res = gFramework.desktopResolution;
            else
                res = Vector2i(800, 600);
        }
        int d = vnode.getIntValue("depth", 0);
        gFramework.setVideoMode(res, d, fs);
    }

    void saveVideoConfig() {
        //store the current resolution into the config file
        auto vconf = loadConfigDef("video");
        bool isFS = gFramework.fullScreen;
        //xxx save fullscreen state? I would prefer configuring this explicitly
        //vconf.setValue("fullscreen", isFS);
        if (!vconf.hasValue("fullscreen"))
            vconf.setValue("fullscreen", false);
        ConfigNode vnode = vconf.getSubNode(isFS ? "fs" : "window");
        Vector2i res = gFramework.screenSize;
        vnode.setValue("width", res.x);
        vnode.setValue("height", res.y);
        //xxx get bit depth somehow?
        saveConfig(vconf, "video.conf");
    }

    void setDefaultOutput(Output o) {
        if (!defaultOut) {
            defaultOut = o;
            gDefaultOutput.destination = defaultOut;
        }
    }

    void readLogconf() {
        ConfigNode conf = loadConfig("logging", false, true);
        if (!conf)
            return;
        foreach (ConfigNode sub; conf.getSubNode("logs")) {
            Log log = registerLog(sub.name);
            if (!sub.getCurValue!(bool)())
                log.shutup();
        }
        if (conf.getValue!(bool)("logconsole", false))
            defaultOut = StdioOutput.output;
    }

    void initLocale(char[] langId) {
        initI18N(langId);
    }

    //translate into translated user-readable string
    char[] translateKeyshortcut(Keycode code, ModifierSet mods) {
        if (!localizedKeynames)
            return "?";
        char[] res = localizedKeynames(translateKeycodeToKeyID(code), "?");
        foreachSetModifier(mods,
            (Modifier mod) {
                res = localizedKeynames(modifierToString(mod), "?") ~ "+" ~ res;
            }
        );
        return res;
    }

    //xxx maybe move to framework
    char[] translateBind(KeyBindings b, char[] bind) {
        Keycode code;
        ModifierSet mods;
        if (!b.readBinding(bind, code, mods)) {
            return "-";
        } else {
            return translateKeyshortcut(code, mods);
        }
    }

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

    //cb will be called each frame between Task and GUI updates
    //if return value of cb is false, the cb is removed from the list
    //better use the Task stuff or override Widget.simulate()
    void addFrameCallback(bool delegate() cb) {
        //memory will be copied (unlike as in "mFrameCallbacks ~= cb;")
        mFrameCallbacks = mFrameCallbacks ~ cb;
    }
    void callFrameCallBacks() {
        //robust enough to deal with additions/removals during iterating
        int[] mRemoveList;
        foreach (int idx, cb; mFrameCallbacks) {
            if (!cb())
                mRemoveList ~= idx;
        }
        //works even after modifications because the only possible change is
        //adding new callbacks
        foreach_reverse (x; mRemoveList) {
            mFrameCallbacks = mFrameCallbacks[0..x] ~ mFrameCallbacks[x+1..$];
        }
    }
}
