module game.gobject;
import game.common;
import game.game;
import utils.mylist;
import utils.time;

import std.stdio;

//not really abstract, but should not be created
abstract class GameObject {
    GameController controller;

    //for GameController
    package mixin ListNodeMixin node;

    this(GameController controller) {
        this.controller = controller;
        controller.mObjects.insert_tail(this);
    }

    //deltaT = seconds since last frame
    void simulate(float deltaT) {
        //override this if you need game time
    }

    void kill() {
    }
}

