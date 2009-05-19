module game.weapon.drill;

import framework.framework;
import game.game;
import game.sprite;
import game.weapon.weapon;
import game.worm;
import game.gamepublic;
import game.sequence;
import physics.world;
import utils.configfile;
import utils.factory;
import utils.reflection;
import utils.time;
import utils.vector2;
import utils.log;
import utils.misc;
import utils.randval;

//drill (changes worm state etc.)
class DrillClass : WeaponClass {
    Time duration;
    int tunnelRadius = 8;
    RandomInt interval = {150, 250};

    this(GameEngine engine, ConfigNode node) {
        super(engine, node);
        duration = timeSecs(node.getValue("duration", 5));
        tunnelRadius = node.getValue("tunnel_radius", tunnelRadius);
        interval = RandomInt(node.getStringValue("interval",
            interval.toString()), engine.rnd);
    }

    //xxx class
    this (ReflectCtor c) {
        super(c);
    }

    override Shooter createShooter(GObjectSprite go) {
        //for now, only worms are enabled to use tools
        //(because of special control methods, i.e. for jetpacks, ropes...)
        auto worm = cast(WormSprite)(go);
        if (!worm)
            throw new Exception(myformat("not a worm: {}", go));
        return new Drill(this, worm);
    }

    static this() {
        WeaponClassFactory.register!(typeof(this))("drill");
    }
}

class Drill : Shooter {
    private {
        DrillClass myclass;
        WormSprite mWorm;
        Time mStart, mNext;
    }

    this(DrillClass base, WormSprite a_owner) {
        super(base, a_owner, a_owner.engine);
        mWorm = a_owner;
        myclass = base;
    }

    this (ReflectCtor c) {
        super(c);
    }

    override bool delayedAction() {
        return active;
    }

    bool activity() {
        return active;
    }

    override protected void updateActive() {
        mWorm.activateDrill(active);
    }

    override protected void doFire(FireInfo info) {
        reduceAmmo();
        active = true;
        mStart = mNext = engine.gameTime.current;
    }

    override protected bool doRefire() {
        active = false;
        finished();
        return true;
    }

    override void simulate(float deltaT) {
        super.simulate(deltaT);
        if (!mWorm.drillActivated()
            || engine.gameTime.current - mStart > myclass.duration)
        {
            doRefire();
            return;
        }
        if (engine.gameTime.current > mNext) {
            engine.damageLandscape(toVector2i(mWorm.physics.pos)
                + Vector2i(0, 7), myclass.tunnelRadius, mWorm);
            mNext = engine.gameTime.current
                + timeMsecs(myclass.interval.sample());
        }
    }
}
