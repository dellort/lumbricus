module game.common;
import game.toplevel;
import framework.framework;
import framework.commandline;
import utils.time;
import utils.configfile;
import utils.log;
import framework.i18n;

public Common globals;

//don't know where to put your stuff? just dump it here!
//mainly supposed to manage all the singletons...

//the big singleton...
//also contains some important initialization code
class Common {
    Framework framework;
    TopLevel toplevel;
    Log log;
    Output defaultOut;
    CommandLine cmdLine;
    ConfigNode anyConfig;

    private Log mLogConf;

    //both time variables are updated for each frame
    //for graphics stuff (i.e. animations continue to play while game paused)
    Time gameTimeAnimations;
    //simulation time, etc.
    Time gameTime;

    private const cLocalePath = "/locale";
    private const cDefLang = "en";

    this(Framework fw) {
        if (globals)
            throw new Exception("Common is a singelton!");
        globals = this;

        log = registerLog("common");

        framework = fw;

        anyConfig = loadConfig("anything");

        initLocale();

        framework.fontManager.readFontDefinitions(loadConfig("fonts"));

        toplevel = new TopLevel();

        //hint: after leaving this constructor, the framework's mainloop is
        //      called, which in turn calls callbacks set by TopLevel.
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

    Surface loadGraphic(char[] path) {
        log("load image: %s", path);
        auto stream = framework.fs.open(path);
        auto image = framework.loadImage(stream, Transparency.Colorkey);
        stream.close();
        return image;
    }

    ConfigNode loadConfig(char[] section) {
        char[] file = section ~ ".conf";
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
