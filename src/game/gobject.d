module game.gobject;
import game.animation;
import game.common;
import game.physic;
import game.game;
import utils.vector2;
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

    void simulate(Time curTime) {
        //override this if you need game time
    }

    void kill() {
    }
}

class TestAnimatedGameObject : GameObject {
    Animator graphic;
    PhysicObject physics;

    this(GameController controller) {
        super(controller);
        physics = new PhysicObject();
        graphic = new Animator();
        graphic.setAnimation(new Animation(globals.loadConfig("animations").getSubNode("testani1")));
        graphic.setScene(controller.scene, GameZOrder.Objects);
        physics.onUpdate = &physUpdate;
        controller.physicworld.add(physics);
    }

    private void physUpdate() {
        graphic.pos = toVector2i(physics.pos);
    }
}
