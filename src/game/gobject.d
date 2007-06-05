module game.gobject;
import game.common;
import game.game;
import utils.mylist;
import utils.time;

import std.stdio;

//not really abstract, but should not be created
abstract class GameObject {
    GameEngine engine;

    //for GameEngine
    package mixin ListNodeMixin node;

    this(GameEngine engine) {
        this.engine = engine;
        engine.mObjects.insert_tail(this);
    }

    //deltaT = seconds since last frame
    void simulate(float deltaT) {
        //override this if you need game time
    }

    void kill() {
    }
}

