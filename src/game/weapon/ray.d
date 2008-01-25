module game.weapon.ray;

import game.game;
import game.gobject;
import physics.world;
import game.sprite;
import game.weapon.weapon;
import std.math: PI;
import utils.vector2;
import utils.configfile;
import utils.log;
import utils.random;
import utils.time;

class RayWeapon: WeaponClass {
    float damage = 5.0f;   //damage of one hit
    int count = 1;         //number of bullets
    Time delay;            //delay between bullets
    float spread = 0;      //random spread (degrees)

    this(GameEngine aengine, ConfigNode node) {
        super(aengine, node);
        //always directed with fixed strength
        canThrow = true;
        variableThrowStrength = false;
        damage = node.getFloatValue("damage", damage);
        count = node.getIntValue("count", count);
        delay = timeSecs(node.getFloatValue("delay", delay.secs));
        spread = node.getFloatValue("spread", spread);
    }

    //using SpecialShooter here leads to dmd lockup (at least with dsss)
    Shooter createShooter(GObjectSprite owner) {
        return new RayShooter(this, owner, engine);
    }

    static this() {
        WeaponClassFactory.register!(RayWeapon)("ray_mc");
    }
}

private class RayShooter: Shooter {
    RayWeapon base;
    FireInfo fireInfo;
    int remain;      //number of bullets still to fire
    Time lastShot;

    this(RayWeapon base, GObjectSprite a_owner, GameEngine engine) {
        super(base, a_owner, engine);
        this.base = base;
    }

    bool activity() {
        return active;
    }

    void fire(FireInfo info) {
        if (active) {
            //try to interrupt
            interruptFiring();
            //if still active: no.
            if (active)
                return;
        }

        fireInfo = info;
        remain = base.count;
        active = true;
    }

    //fires one shot with random spread
    private void fireRound() {
        float a = base.spread*genrand_real1() - base.spread/2.0f;
        float dist = owner.physics.posp.radius + 2;
        Vector2f ndir = fireInfo.dir.rotated(a*PI/180.0f);
        Vector2f npos = owner.physics.pos+ndir*dist;
        PhysicObject o;
        Vector2f hitPoint;
        bool hit = engine.physicworld.shootRay(npos, ndir,
            engine.level.size.length, hitPoint, o);
        if (hit) {
            engine.explosionAt(hitPoint, base.damage, owner);
        }
    }

    override void simulate(float deltaT) {
        //shoot bullets
        while (remain > 0
            && engine.gameTime.current - lastShot >= base.delay)
        {
            remain--;
            lastShot = engine.gameTime.current;

            fireRound();
        }
        if (remain == 0) {
            active = false;
        }
    }
}
