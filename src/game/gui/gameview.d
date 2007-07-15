module game.gui.gameview;

import framework.framework;
import common.common;
import common.scene;
import game.gamepublic;
import game.clientengine;
import gui.widget;
import gui.container;
import gui.mousescroller;
import utils.vector2;

//GameView is everything which is scrolled
class GameView : Widget {
    private {
        ClientGameEngine mEngine;
        GameLogicPublic mLogic;
        TeamMemberControl mController;
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

        //hacky?
        mLogic = mEngine.logic;
        mController = mEngine.controller;
    }

    override Vector2i layoutSizeRequest() {
        return mEngine.scene.size;
    }

    override void onRelayout() {
    }

    override protected bool onKeyDown(char[] bind, KeyInfo key) {
        //return mController.onKeyDown(bind, key, mousePos);
        return false;
    }
    override protected bool onKeyUp(char[] bind, KeyInfo key) {
        //return mController.onKeyUp(bind, key, mousePos);
        return false;
    }
    override protected bool onMouseMove(MouseInfo mouse) {
        return false;
    }
}
