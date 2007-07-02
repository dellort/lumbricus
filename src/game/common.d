module game.common;

import framework.framework;
import framework.commandline;
import framework.timesource;
import framework.i18n;
import utils.time;
import utils.configfile;
import utils.log, utils.output;
import utils.misc;
import game.resources;
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
    Resources resources;

    private Log mLogConf;

    //both time variables are updated for each frame
    //for graphics stuff (i.e. animations continue to play while game paused)
    TimeSource gameTimeAnimations;

    private const cLocalePath = "/locale";
    private const cDefLang = "en";

    this(Framework fw, char[][] args) {
        if (globals)
            throw new Exception("Common is a singelton!");
        globals = this;

        log = registerLog("common");

        framework = fw;

        resources = new Resources();

        anyConfig = loadConfig("anything");

        auto scr = anyConfig.getSubNode("screenmode");
        int w = scr.getIntValue("width", 800);
        int h = scr.getIntValue("height", 600);
        int d = scr.getIntValue("depth", 0);
        bool fs = scr.getBoolValue("fullscreen", false);
        fw.setVideoMode(w, h, d, fs);

        initLocale();

        framework.fontManager.readFontDefinitions(loadConfig("fonts"));

        //maybe replace by a real arg parser
        if (args.length > 0 && args[0] == "logconsole") {
            defaultOut = StdioOutput.output;
        }

        gameTimeAnimations = new TimeSource(&framework.getCurrentTime);
    }

    void setDefaultOutput(Output o) {
        if (!defaultOut) {
            defaultOut = o;
            gDefaultOutput.destination = defaultOut;
        }
    }

    private void initLocale() {
        char[] langId = anyConfig.getStringValue("language_id", "de");
        ConfigNode localeNode = null;
        try {
            localeNode = globals.loadConfig(cLocalePath ~ '/' ~ langId);
        } catch {
            try {
                //try default language
                langId = cDefLang;
                localeNode = globals.loadConfig(cLocalePath ~ '/' ~ langId);
            } catch {
                langId = "none";
            }
        }
        initI18N(localeNode,langId);
        try {
            framework.fs.link(cLocalePath ~ '/' ~ langId,"/",true);
        } catch {
            //don't crash if current locale has no locale-specific files
        }
    }

    Surface loadGraphic(char[] path, Transparency t = Transparency.Colorkey) {
        log("load image: %s", path);
        auto stream = framework.fs.open(path);
        auto image = framework.loadImage(stream, t);
        stream.close();
        return image;
    }

    ConfigNode loadConfig(char[] section, bool asfilename = false) {
        char[] file = fixRelativePath(section ~ (asfilename ? "" : ".conf"));
        log("load config: %s", file);
        auto s = framework.fs.open(file);
        auto f = new ConfigFile(s, file, &logconf);
        s.close();
        if (!f.rootnode)
            throw new Exception("?");
        return f.rootnode;
    }

    private void logconf(char[] log) {
        if (!mLogConf) {
            mLogConf = registerLog("configfile");
            assert(mLogConf !is null);
        }
        mLogConf("%s", log);
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
