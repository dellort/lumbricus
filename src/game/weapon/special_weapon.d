module game.weapon.special_weapon;

import game.game;
import game.gobject;
import physics.world;
import game.sprite;
import game.weapon.weapon;
import utils.configfile;
import utils.log;
import utils.time;

class AtomtestWeapon : WeaponClass {
    float earthquakeStrength;
    Time testDuration;
    int waterRaise;

    this(GameEngine aengine, ConfigNode node) {
        super(aengine, node);
        earthquakeStrength = node.getFloatValue("earthquake_strength");
        testDuration = timeMsecs(node.getIntValue("test_duration_ms"));
        waterRaise = node.getIntValue("water_raise");
    }

    //using SpecialShooter here leads to dmd lockup (at least with dsss)
    Shooter createShooter(GObjectSprite owner) {
        return new AtomtestShooter(this, owner, engine);
    }

    static this() {
        WeaponClassFactory.register!(AtomtestWeapon)("atomtest_mc");
    }
}

private class AtomtestShooter : Shooter {
    AtomtestWeapon base;
    PhysicBase earthquake;
    Time endtime;

    this(AtomtestWeapon base, GObjectSprite a_owner, GameEngine engine) {
        super(base, a_owner, engine);
        this.base = base;
    }

    bool activity() {
        return active;
    }

    void fire(FireInfo info) {
        active = true;
        //start it hrhrhr
        engine.raiseWater(base.waterRaise);
        earthquake = new EarthQuakeDegrader(base.earthquakeStrength, 1.0f,
            engine.earthQuakeForce);
        engine.physicworld.addBaseObject(earthquake);
        endtime = engine.gameTime.current + base.testDuration;
    }

    override protected void simulate(float deltaT) {
        super.simulate(deltaT);
        if (engine.gameTime.current >= endtime) {
            active = false;
            earthquake.dead = true;
        }
    }
}
