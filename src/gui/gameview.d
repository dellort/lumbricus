module gui.gameview;

import framework.framework;
import game.controller;
import game.common;
import game.clientengine;
import game.scene;
import gui.guiobject;
import utils.vector2;

class GameView : GuiObject {
    private ClientGameEngine mEngine;
    private SceneView mGameSceneView;
    private GameController mController;

    override bool canHaveFocus() {
        return true;
    }
    override bool greedyFocus() {
        return true;
    }

    override void relayout() {
        mGameSceneView.pos = bounds.p1;
        mGameSceneView.size = size;
    }

    this(ClientGameEngine engine) {
        mEngine = engine;
        mGameSceneView = new SceneView();
        addManagedSceneObject(mGameSceneView);
    }

    SceneView view() {
        return mGameSceneView;
    }

    void controller(GameController cont) {
        if (cont) {
            cont.sceneview = mGameSceneView;
        } else {
            if (mController)
                mController.sceneview = null;
        }
        mController = cont;
    }

    void gamescene(Scene s) {
        mGameSceneView.clientscene = s;
    }

    override protected bool onKeyDown(char[] bind, KeyInfo key) {
        if (bind == "scroll_toggle") {
            scrollToggle();
            return true;
        }
        return mController.onKeyDown(bind, key,
            mGameSceneView.toClientCoords(mousePos));
    }
    override protected bool onKeyUp(char[] bind, KeyInfo key) {
        return mController.onKeyUp(bind, key,
            mGameSceneView.toClientCoords(mousePos));
    }
    override protected bool onMouseMove(MouseInfo mouse) {
        if (mScrolling) {
            mGameSceneView.scrollMove(mouse.rel);
            return true;
        }
        return false;
    }

    //--------------------------- Scrolling start -------------------------

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

    //--------------------------- Scrolling end ---------------------------
}
