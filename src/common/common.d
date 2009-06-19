module common.common;

public import common.config;
import common.resources;
import common.resset;
import framework.filesystem;
import framework.framework;
import framework.commandline;
import framework.timesource;
import framework.i18n;
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

//the big singleton...
//also contains some important initialization code
class Common {
    LogStruct!("common") log;
    Output defaultOut;
    CommandLine cmdLine;
    ConfigNode programArgs; //command line for the lumbricus executable

    Resources resources;
    //oh sorry, didn't know where to put that!
    //is for guires.conf
    ResourceSet guiResources;

    //high resolution timers which are updated each frame, or so
    //toplevel.d will reset them all!
    PerfTimer[char[]] timers;

    //another hack, see addFrameCallback()
    private {
        bool delegate()[] mFrameCallbacks;
        MountId mLocaleMount = MountId.max;
    }

    //moved to here from TopLevel
    //xxx move this to where-ever
    Translator localizedKeynames;

    private const cLocalePath = "/locale";
    private const cDefLang = "en";

    this(ConfigNode args) {
        assert(!globals, "Common is a singelton!");
        globals = this;
        programArgs = args;

        readLogconf();

        if (args.getBoolValue("logconsole")) {
            defaultOut = StdioOutput.output;
        }

        loadColors(gConf.loadConfig("colors"));

        //will set global gResources
        resources = new Resources();

        char[] langId = programArgs["language_id"];
        if (!langId.length) {
            ConfigNode langconf = gConf.loadConfigDef("language");
            langId = langconf.getStringValue("language_id", "");
        }
        initLocale(langId);

        localizedKeynames = localeRoot.bindNamespace("keynames");
    }

    void initGUIStuff() {
        //????????????
        //copy the stupid timers
        foreach (char[] name, PerfTimer cnt; gFramework.timers) {
            timers[name] = cnt;
        }

        //GUI resources, this is a bit off here
        guiResources = resources.loadResSet("guires.conf");

        gFramework.fontManager.readFontDefinitions(
            gConf.loadConfig("fonts"));

        setVideoFromConf();
        if (!gFramework.videoActive) {
            //this means we're F****D!!1  ("FOOLED")
            log("ERROR: couldn't initialize video");
            throw new Exception("can't continue");
        }
    }

    //read configuration from video.conf and set video mode
    void setVideoFromConf(bool toggleFullscreen = false) {
        auto vconf = gConf.loadConfigDef("video");
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
        auto vconf = gConf.loadConfigDef("video");
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
        gConf.saveConfig(vconf, "video.conf");
    }

    void setDefaultOutput(Output o) {
        if (!defaultOut) {
            defaultOut = o;
            gDefaultOutput.destination = defaultOut;
        }
    }

    void readLogconf() {
        ConfigNode conf = gConf.loadConfig("logging", false, true);
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
        initI18N(cLocalePath, langId, cDefLang, &gConf.loadConfig);
        try {
            //link locale-specific files into root
            gFS.unmount(mLocaleMount);
            mLocaleMount = gFS.link(cLocalePath ~ '/' ~ langId,"/",false,1);
        } catch (FilesystemException e) {
            //don't crash if current locale has no locale-specific files
            gDefaultLog("catched {}", e);
        }
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
