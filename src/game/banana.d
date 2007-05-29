module game.banana;

import game.gobject;
import game.animation;
import game.common;
import game.physic;
import game.game;
import game.sprite;
import utils.misc;
import utils.vector2;
import utils.mylist;
import utils.time;

class BananaBomb : GObjectSprite {
    private bool mSpawner;

    this(GameController controller, bool spawner = true) {
        super(controller, controller.findGOSpriteClass("banana"));
        mSpawner = spawner;
        if (spawner) {
            physics.lifeTime = 3;
        }
    }

    override protected void physImpact(PhysicBase other) {
        super.physImpact(other);
        if (mSpawner)
            return; //???

        //Hint: in future, physImpact should deliver the collision cookie
        //(aka "action" in the config file)
        //then the banana bomb can decide if it expldoes or falls into the water
        physics.dead = true;
        graphic.active = false;
        explode();
    }

    private void explode() {
        controller.explosionAt(physics.pos,
            type.config.getFloatValue("damage", 1.0f));
    }

    override protected void physDie() {
        explode();
        if (mSpawner) {
            for (int i = 0; i < 5; i++) {
                auto b = new BananaBomb(controller, false);
                b.setPos(physics.pos+Vector2f(genrand_real1()*4-2,-2));
            }
        }
        graphic.active = false;
        super.physDie();
    }
}
