module gui.gameview;

import framework.framework;
import game.controller;
import game.common;
import game.clientengine;
import game.scene;
import gui.widget;
import gui.container;
import gui.mousescroller;
import utils.vector2;

//GameView is everything which is scrolled
class GameView : Widget {
    private {
        ClientGameEngine mEngine;
        GameController mController;
        Container mGuiFrame;
    }

    override bool canHaveFocus() {
        return true;
    }
    override bool greedyFocus() {
        return true;
    }

    this(ClientGameEngine engine) {
        mEngine = engine;
        scene.add(mEngine.scene);
    }

    override Vector2i layoutSizeRequest() {
        return mEngine.scene.size;
    }

    override void onRelayout() {
    }

    void controller(GameController cont) {
        if (cont) {
            //cont.sceneview = mGameSceneView;
        } else {
            //if (mController)
              //  mController.sceneview = null;
        }
        mController = cont;
    }

    override protected bool onKeyDown(char[] bind, KeyInfo key) {
        if (bind == "scroll_toggle") {
            //scrollToggle();
            return true;
        }
        return mController.onKeyDown(bind, key, mousePos);
    }
    override protected bool onKeyUp(char[] bind, KeyInfo key) {
        return mController.onKeyUp(bind, key, mousePos);
    }
    override protected void onMouseMove(MouseInfo mouse) {
        /+
        if (mScrolling) {
            mGameSceneView.scrollMove(mouse.rel);
        }
        +/
    }

    //--------------------------- Scrolling start -------------------------

    /+
    private bool mScrolling;

    private void scrollToggle() {
        if (mScrolling) {
            //globals.framework.grabInput = false;
            globals.framework.cursorVisible = true;
            globals.framework.unlockMouse();
        } else {
            //globals.framework.grabInput = true;
            globals.framework.cursorVisible = false;
            globals.framework.lockMouse();
            mGameSceneView.scrollReset();
        }
        mScrolling = !mScrolling;
    }
    +/

    //--------------------------- Scrolling end ---------------------------
}
