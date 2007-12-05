module common.common;

import framework.framework;
import framework.commandline;
import framework.timesource;
import framework.i18n;
import utils.time;
import utils.configfile;
import utils.log, utils.output;
import utils.misc;
import utils.path;
import utils.perf;
import std.stream;

public Common globals;

//don't know where to put your stuff? just dump it here!
//mainly supposed to manage all the singletons...

//the big singleton...
//also contains some important initialization code
class Common {
    Framework framework;
    Log log;
    Output defaultOut;
    CommandLine cmdLine;
    ConfigNode anyConfig;

    //high resolution timers which are updated each frame, or so
    //toplevel.d will reset them all!
    PerfTimer[char[]] timers;

    //both time variables are updated for each frame
    //for graphics stuff (i.e. animations continue to play while game paused)
    //xxx: move!
    TimeSource gameTimeAnimations;

    //moved to here from TopLevel
    //xxx move this to where-ever
    Translator localizedKeynames;

    private const cLocalePath = "/locale";
    private const cDefLang = "en";

    this(Framework fw, char[][] args) {
        if (globals)
            throw new Exception("Common is a singelton!");
        globals = this;

        log = registerLog("common");

        loadColors(gFramework.loadConfig("colors"));

        framework = fw;

        //copy the stupid timers
        foreach (char[] name, PerfTimer cnt; fw.timers) {
            timers[name] = cnt;
        }

        anyConfig = framework.loadConfig("anything");

        auto scr = anyConfig.getSubNode("screenmode");
        int w = scr.getIntValue("width", 800);
        int h = scr.getIntValue("height", 600);
        int d = scr.getIntValue("depth", 0);
        bool fs = scr.getBoolValue("fullscreen", false);
        fw.setVideoMode(Vector2i(w, h), d, fs);

        initLocale();

        framework.fontManager.readFontDefinitions(framework.loadConfig("fonts"));

        //maybe replace by a real arg parser
        if (args.length > 0 && args[0] == "logconsole") {
            defaultOut = StdioOutput.output;
        }

        localizedKeynames = localeRoot.bindNamespace("keynames");

        gameTimeAnimations = new TimeSource(&framework.getCurrentTime);
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
        char[] langId = anyConfig.getStringValue("language_id", "de");
        initI18N(cLocalePath, langId, cDefLang, &framework.loadConfig);
        //try {
            //link locale-specific files into root
            framework.fs.link(cLocalePath ~ '/' ~ langId,"/",false,1);
        //} catch { xxx: no, don't catch everything
            //don't crash if current locale has no locale-specific files
        //}
    }

    //translate into translated user-readable string
    char[] translateKeyshortcut(Keycode code, ModifierSet mods) {
        if (!localizedKeynames)
            return "?";
        char[] res = localizedKeynames(
            framework.translateKeycodeToKeyID(code), "?");
        foreachSetModifier(mods,
            (Modifier mod) {
                res = localizedKeynames(
                    framework.modifierToString(mod), "?") ~ "+" ~ res;
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
        auto t = new PerfTimer();
        timers[name] = t;
        return t;
    }
}

//arrgh
void saveConfig(ConfigNode node, char[] filename) {
    auto stream = gFramework.fs.open(filename, FileMode.OutNew);
    try {
        auto textstream = new StreamOutput(stream);
        node.writeFile(textstream);
    } finally {
        stream.close();
    }
}
