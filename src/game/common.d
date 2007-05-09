module game.common;
import framework.framework;
import framework.font;
import game.scene;
import game.animation;
import filesystem;
import utils.time;
import utils.configfile;
import utils.log;
import std.string;

public Common gCommon;

//don't know where to put your stuff? just dump it here!

//ZOrders!
//maybe keep in sync with game.Scene.cMaxZOrder
enum ZOrder : int {
    Invisible = 0,
    Background,
    HUD,
    FPS,
}

class Common {
    Framework framework;
    Screen screen;
    Scene gamescene;
    FileSystem filesystem;
    Font consFont;
    FontLabel fpsDisplay;
    Log defaultLog;

    private Log mLogConf;

    //for graphics stuff (i.e. animations continue to play while game paused)
    Time gameTimeAnimations;
    //simulation time, etc.
    Time gameTime;

    this(Framework fw, Font consFont) {
        if (gCommon)
            throw new Exception("Common is a singelton!");
        gCommon = this;

        framework = fw;
        screen = new Screen(fw.screen.size);

        this.consFont = consFont;

        defaultLog = registerLog("common");

        filesystem = gFileSystem;

        framework.fontManager.readFontDefinitions(loadConfig("fonts", true));

        gamescene = screen.rootscene;
        fpsDisplay = new FontLabel(gamescene, framework.getFont("fpsfont"));
        fpsDisplay.active = true;
        fpsDisplay.zorder = ZOrder.FPS;

        fpsDisplay.text = "hallo";

        //kidnap framework singleton...
        framework.onFrame = &onFrame;
        ConfigNode node = loadConfig("animations", true);
        auto sub = node.getSubNode("testani1");
        Animation ani = new Animation(sub);
        Animator ar = new Animator(gamescene);
        ar.zorder = 2;
        ar.active = true;
        ar.setAnimation(ani, true);
    }

    Surface loadGraphic(char[] path) {
        return framework.loadImage(filesystem.openData(path), Transparency.None);
    }

    ConfigNode loadConfig(char[] section, bool system) {
        char[] file = section ~ ".conf";
        auto s = filesystem.open(file, system);
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

    private void onFrame() {
        gameTimeAnimations = framework.getCurrentTime();

        fpsDisplay.text = format("FPS: %1.2f", framework.FPS);

        Canvas canvas = framework.screen.startDraw();
        screen.draw(canvas);
        framework.screen.endDraw();
    }
}
