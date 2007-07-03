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

//xxx include so that module constructors (static this) are actually called
import game.projectile;
import game.special_weapon;

//GameGui: hack for loader_game.d, make GuiFrame methods accessable
class GameFrame : GuiFrame, GameGui {
    GameEngine thegame;
    ClientGameEngine clientengine;
    /*private*/ GameLoader mGameLoader;
    private LoadingScreen mLoadScreen;

    //strange? complains about not implemented fpr GameGui, even happens if
    //GameFrame methods are public; maybe compiler bug
    public void addGui(GuiObject obj) {
        super.addGui(obj);
    }
    public void killGui() {
        super.killGui();
    }

    this(GuiMain gui) {
        super(gui);

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
}
