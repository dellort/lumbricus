module game.banana;

import game.gobject;
import game.animation;
import game.common;
import game.physic;
import game.game;
import utils.misc;
import utils.vector2;
import utils.mylist;
import utils.time;

class BananaBomb : GameObject {
    Animator graphic;
    Animation mAnim;
    PhysicObject physics;
    private bool mSpawner;

    this(GameController controller, Animation anim, bool spawner = true) {
        super(controller);
        mSpawner = spawner;
        physics = new PhysicObject();
        graphic = new Animator();
        mAnim = anim;
        graphic.setAnimation(mAnim);
        graphic.setScene(controller.scene, GameZOrder.Objects);
        physics.radius = 5;
        physics.onUpdate = &physUpdate;
        if (spawner) {
            physics.onDie = &physDie;
            physics.lifeTime = 3;
        } else
            physics.onImpact = &physImpact;
        controller.physicworld.add(physics);
    }

    void setPos(Vector2i pos) {
        physics.pos = toVector2f(pos);
        physUpdate();
    }

    private void physUpdate() {
        graphic.pos = toVector2i(physics.pos) - mAnim.size/2;
    }

    private void physImpact(PhysicObject other) {
        if (other is null) {
            physics.dead = true;
            graphic.active = false;
            explode();
        }
    }

    private void explode() {
        controller.gamelevel.damage(toVector2i(physics.pos), 50);
        auto expl = new ExplosiveForce();
        expl.impulse = 2000;
        expl.radius = 200;
        expl.pos = physics.pos;
        controller.physicworld.add(expl);
    }

    private void physDie() {
        explode();
        if (mSpawner) {
            for (int i = 0; i < 5; i++) {
                auto b = new BananaBomb(controller, mAnim, false);
                b.setPos(toVector2i(physics.pos+Vector2f(genrand_real1()*4-2,-2)));
            }
        }
        graphic.active = false;
    }
}
