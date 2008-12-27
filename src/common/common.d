module common.common;

import framework.filesystem;
import framework.framework;
import framework.commandline;
import framework.resset;
import framework.resources;
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
import std.stream;
import zlib = std.zlib;

public Common globals;

//don't know where to put your stuff? just dump it here!
//mainly supposed to manage all the singletons...

//the big singleton...
//also contains some important initialization code
class Common {
    Log log;
    Output defaultOut;
    CommandLine cmdLine;
    ConfigNode anyConfig;
    ConfigNode programArgs; //command line for the lumbricus executable

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
        if (globals)
            throw new Exception("Common is a singelton!");
        globals = this;

        log = registerLog("common");

        programArgs = args;

        if (args.getBoolValue("logconsole")) {
            defaultOut = StdioOutput.output;
        }

        loadColors(gFramework.loadConfig("colors"));

        //GUI resources, this is a bit off here
        guiResources = gFramework.resources.loadResSet("guires.conf");

        //copy the stupid timers
        foreach (char[] name, PerfTimer cnt; gFramework.timers) {
            timers[name] = cnt;
        }

        anyConfig = gFramework.loadConfig("anything");

        auto scr = anyConfig.getSubNode("screenmode");
        int w = scr.getIntValue("width", 800);
        int h = scr.getIntValue("height", 600);
        int d = scr.getIntValue("depth", 0);
        bool fs = scr.getBoolValue("fullscreen", false);
        gFramework.setVideoMode(Vector2i(w, h), d, fs);

        if (!gFramework.videoActive) {
            //this means we're F****D!!1
            log("ERROR: couldn't initialize video");
            throw new Exception("can't continue");
        }

        initLocale();

        gFramework.fontManager.readFontDefinitions(
            gFramework.loadConfig("fonts"));

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

    private void initLocale() {
        char[] langId = programArgs["language_id"];
        if (!langId.length)
            langId = anyConfig.getStringValue("language_id", "de");
        initI18N(cLocalePath, langId, cDefLang, &gFramework.loadConfig);
        try {
            //link locale-specific files into root
            gFramework.fs.link(cLocalePath ~ '/' ~ langId,"/",false,1);
        } catch (FilesystemException e) {
            //don't crash if current locale has no locale-specific files
            gDefaultLog("catched %s", e);
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

//arrgh
//compress = true: do gzip compression, adds .gz to filename
void saveConfig(ConfigNode node, char[] filename, bool compress = false) {
    if (compress) {
        saveConfigGz(node, filename~".gz");
        return;
    }
    auto stream = gFramework.fs.open(filename, FileMode.OutNew);
    try {
        auto textstream = new StreamOutput(stream);
        node.writeFile(textstream);
    } finally {
        stream.close();
    }
}

//same as above, always gzipped
//will not modify file extension
void saveConfigGz(ConfigNode node, char[] filename) {
    auto stream = gFramework.fs.open(filename, FileMode.OutNew);
    try {
        ubyte[] txt = cast(ubyte[])node.writeAsString();
        ubyte[] gz = gzipData(txt);
        stream.write(gz);
    } finally {
        stream.close();
    }
}
