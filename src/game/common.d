module game.common;
import game.toplevel;
import framework.framework;
import framework.commandline;
import filesystem;
import utils.time;
import utils.configfile;
import utils.log;

public Common globals;

//don't know where to put your stuff? just dump it here!
//mainly supposed to manage all the singletons...

//ZOrders!
//maybe keep in sync with game.Scene.cMaxZOrder
//maybe move to module game.toplevel
//these values are for globals.toplevel.guiscene
enum GUIZOrder : int {
    Invisible = 0,
    Background,
    Game,
    Gui,
    Console,
    FPS,
}

//the big singleton...
//also contains some important initialization code
class Common {
    Framework framework;
    TopLevel toplevel;
    FileSystem filesystem;
    Log log;
    Output defaultOut;
    CommandLine cmdLine;

    private Log mLogConf;

    //both time variables are updated for each frame
    //for graphics stuff (i.e. animations continue to play while game paused)
    Time gameTimeAnimations;
    //simulation time, etc.
    Time gameTime;

    this(Framework fw) {
        if (globals)
            throw new Exception("Common is a singelton!");
        globals = this;

        framework = fw;
        filesystem = gFileSystem;

        log = registerLog("common");

        framework.fontManager.readFontDefinitions(loadConfig("fonts"));

        toplevel = new TopLevel();

        //hint: after leaving this constructor, the framework's mainloop is
        //      called, which in turn calls callbacks set by TopLevel.
    }

    Surface loadGraphic(char[] path) {
        return framework.loadImage(filesystem.openData(path), Transparency.None);
    }

    ConfigNode loadConfig(char[] section) {
        char[] file = section ~ ".conf";
        auto s = filesystem.open(file, true);
        auto f = new ConfigFile(s, file, &logconf);
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
