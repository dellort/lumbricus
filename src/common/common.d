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
import stdx.stream;

public Common globals;

//don't know where to put your stuff? just dump it here!
//mainly supposed to manage all the singletons...

//the big singleton...
//also contains some important initialization code
class Common {
    Log log;
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
    }

    //both time variables are updated for each frame
    //for graphics stuff (i.e. animations continue to play while game paused)
    //xxx: move!
    TimeSource gameTimeAnimations;

    //moved to here from TopLevel
    //xxx move this to where-ever
    Translator localizedKeynames;

    private const cLocalePath = "/locale";
    private const cDefLang = "en";

    this(ConfigNode args) {
        assert(!globals, "Common is a singelton!");
        globals = this;
        programArgs = args;

        log = registerLog("common");

        readLogconf();

        if (args.getBoolValue("logconsole")) {
            defaultOut = StdioOutput.output;
        }

        loadColors(gConf.loadConfig("colors"));

        //will set global gResources
        resources = new Resources();
        //GUI resources, this is a bit off here
        guiResources = resources.loadResSet("guires.conf");

        //copy the stupid timers
        foreach (char[] name, PerfTimer cnt; gFramework.timers) {
            timers[name] = cnt;
        }

        ConfigNode scr = gConf.loadConfig("video");
        int w = scr.getIntValue("width", 800);
        int h = scr.getIntValue("height", 600);
        int d = scr.getIntValue("depth", 0);
        bool fs = scr.getBoolValue("fullscreen", false);
        gFramework.setVideoMode(Vector2i(w, h), d, fs);

        if (!gFramework.videoActive) {
            //this means we're F****D!!1  ("FOOLED")
            log("ERROR: couldn't initialize video");
            throw new Exception("can't continue");
        }

        ConfigNode langconf = gConf.loadConfig("language");
        char[] langId = programArgs["language_id"];
        if (!langId.length)
            langId = langconf.getStringValue("language_id", "de");
        initLocale(langId);

        gFramework.fontManager.readFontDefinitions(
            gConf.loadConfig("fonts"));

        localizedKeynames = localeRoot.bindNamespace("keynames");

        gameTimeAnimations = new TimeSource();
        //moved from toplevel.d
        gameTimeAnimations.resetTime();
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
            if (!sub.getCurValue!(bool)(false))
                log.shutup();
        }
        if (conf.getValue!(bool)("logconsole", false))
            defaultOut = StdioOutput.output;
    }

    private void initLocale(char[] langId) {
        initI18N(cLocalePath, langId, cDefLang, &gConf.loadConfig);
        try {
            //link locale-specific files into root
            gFS.link(cLocalePath ~ '/' ~ langId,"/",false,1);
        } catch (FilesystemException e) {
            //don't crash if current locale has no locale-specific files
            gDefaultLog("catched {}", e);
        }
    }

    //translate into translated user-readable string
    char[] translateKeyshortcut(Keycode code, ModifierSet mods) {
        if (!localizedKeynames)
            return "?";
        char[] res = localizedKeynames(
            gFramework.translateKeycodeToKeyID(code), "?");
        foreachSetModifier(mods,
            (Modifier mod) {
                res = localizedKeynames(
                    gFramework.modifierToString(mod), "?") ~ "+" ~ res;
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
