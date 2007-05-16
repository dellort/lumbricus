module game.gobject;
import game.animation;
import utils.vector2;
import utils.mylist;
import game.common;
import game.physic;
import game.game;

class GameObject {
    Animator graphic;
    PhysicObject physics;
    GameController controller;

    //for GameController
    package mixin ListNodeMixin node;

    private void physUpdate() {
        graphic.pos = toVector2i(physics.pos);
    }

    this(GameController controller) {
        this.controller = controller;
        controller.mObjects.insert_tail(this);
        physics = new PhysicObject();
        graphic = new Animator();
        graphic.setAnimation(new Animation(globals.loadConfig("animations").getSubNode("testani1")));
        graphic.setScene(controller.scene, GameZOrder.Objects);
        physics.onUpdate = &physUpdate;
        controller.physicworld.add(physics);
    }
}
