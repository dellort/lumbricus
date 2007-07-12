module game.gui.gameview;

import framework.framework;
import game.controller;
import common.common;
import game.clientengine;
import common.scene;
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
    override protected bool onMouseMove(MouseInfo mouse) {
        /+
        if (mScrolling) {
            mGameSceneView.scrollMove(mouse.rel);
        }
        +/
        return false;
    }
}
