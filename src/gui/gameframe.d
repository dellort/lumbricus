module gui.gameframe;
import gui.guiframe;
import gui.gui;
import gui.guiobject;
import gui.loadingscreen;
import game.common;
import game.scene;
import game.game;
import game.visual;
import game.clientengine;
import game.loader;
import game.loader_game;
import framework.commandline : CommandBucket, Command;
import utils.mybox;
import utils.output;

//xxx include so that module constructors (static this) are actually called
import game.projectile;
import game.special_weapon;

//GameGui: hack for loader_game.d, make GuiFrame methods accessable
class GameFrame : GuiFrame, GameGui {
    GameEngine thegame;
    ClientGameEngine clientengine;
    /*private*/ GameLoader mGameLoader;
    private LoadingScreen mLoadScreen;

    private CommandBucket mCmds;

    //strange? complains about not implemented fpr GameGui, even happens if
    //GameFrame methods are public; maybe compiler bug
    public void addGui(GuiObject obj) {
        super.addGui(obj);
    }
    public void killGui() {
        super.killGui();
    }

    bool gamePaused() {
        return thegame.gameTime.paused;
    }
    void gamePaused(bool set) {
        thegame.gameTime.paused = set;
        clientengine.engineTime.paused = set;
    }

    this(GuiMain gui) {
        super(gui);

        mCmds = new CommandBucket();
        registerCommands();
        mCmds.bind(globals.cmdLine);

        mLoadScreen = new LoadingScreen();
        addGui(mLoadScreen);

        mLoadScreen.active = false;
        mLoadScreen.zorder = GUIZOrder.Loading;

        mGameLoader = new GameLoader(globals.anyConfig.getSubNode("newgame"), this);
        mGameLoader.onFinish = &gameLoaded;
        mGameLoader.onUnload = &gameUnloaded;

        //creaton of this frame -> start new game
        mLoadScreen.startLoad(mGameLoader);
    }

    private void gameLoaded(Loader sender) {
        thegame = mGameLoader.thegame;
        thegame.gameTime.resetTime;
        //yyy?? resetTime();
        globals.gameTimeAnimations.resetTime(); //yyy
        clientengine = mGameLoader.clientengine;
    }
    private void gameUnloaded(Loader sender) {
        thegame = null;
        clientengine = null;
    }

    protected void kill() {
        mGameLoader.unload();
        mCmds.kill();
        super.kill();
    }

    void onFrame(Canvas c) {
        if (mGameLoader.fullyLoaded) {
            globals.gameTimeAnimations.update();

            if (thegame) {
                thegame.doFrame();
            }

            if (clientengine) {
                clientengine.doFrame();
            }
        }

        if (!mLoadScreen.loading)
            //xxx can't deactivate this from delegate because it would crash
            //the list
            mLoadScreen.active = false;
    }

    //game specific commands
    private void registerCommands() {
        mCmds.register(Command("raisewater", &cmdRaiseWater,
            "increase waterline", ["int:water level"]));
        mCmds.register(Command("wind", &cmdSetWind,
            "Change wind speed", ["float:wind speed"]));
        mCmds.register(Command("cameradisable", &cmdCameraDisable,
            "disable game camera"));
        mCmds.register(Command("detail", &cmdDetail,
            "switch detail level", ["int?:detail level (if not given: cycle)"]));
    }

    private void cmdCameraDisable(MyBox[] args, Output write) {
        if (mGameLoader.gameView)
            mGameLoader.gameView.view.setCameraFocus(null);
    }

    private void cmdDetail(MyBox[] args, Output write) {
        if (!clientengine)
            return;
        int c = args[0].unboxMaybe!(int)(-1);
        clientengine.detailLevel = c >= 0 ? c : clientengine.detailLevel + 1;
        write.writefln("set detailLevel to %s", clientengine.detailLevel);
    }

    private void cmdSetWind(MyBox[] args, Output write) {
        thegame.windSpeed = args[0].unbox!(float)();
    }

    private void cmdRaiseWater(MyBox[] args, Output write) {
        thegame.raiseWater(args[0].unbox!(int)());
    }
}
