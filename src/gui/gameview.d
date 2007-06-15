module gui.gameview;

import framework.framework;
import game.controller;
import game.common;
import game.game;
import game.scene;
import gui.guiobject;
import utils.vector2;

class GameView : GuiObject {
    private SceneView mGameSceneView;
    private GameController mController;

    this() {
        mGameSceneView = new SceneView();
        events.onKeyDown = &keyDown;
        events.onKeyUp = &keyUp;
        events.onMouseMove = &mouseMove;
    }

    public void setScene(Scene s, int z) {
        super.setScene(s, z);
        mGameSceneView.setScene(scene, zorder);
        if (s) {
            mGameSceneView.pos = Vector2i(0, 0);
        }
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

    void draw(Canvas canvas) {
        //
    }

    void resize() {
        mGameSceneView.size = scene.size;
        size = mGameSceneView.size;
    }

    bool keyDown(char[] bind, KeyInfo key) {
        if (bind == "scroll_toggle") {
            scrollToggle();
            return true;
        }
        return mController.onKeyDown(bind, key, mGameSceneView.toClientCoords(events.mousePos));
    }
    bool keyUp(char[] bind, KeyInfo key) {
        return mController.onKeyUp(bind, key, mGameSceneView.toClientCoords(events.mousePos));
    }
    bool mouseMove(MouseInfo mouse) {
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
