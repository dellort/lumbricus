module game.weapon.drill;

import framework.framework;
import game.game;
import game.gfxset;
import game.sprite;
import game.weapon.weapon;
import game.worm;
import game.sequence;
import physics.world;
import utils.configfile;
import utils.factory;
import utils.time;
import utils.vector2;
import utils.log;
import utils.misc;
import utils.randval;

//drill (changes worm state etc.)
class DrillClass : ConfWeaponClass {
    Time duration = timeSecs(5);
    int tunnelRadius = 8;
    RandomValue!(Time) interval = {timeMsecs(150), timeMsecs(250)};
    bool blowtorch = false;

    this(GfxSet gfx, ConfigNode node) {
        super(gfx, node);
        duration = node.getValue("duration", duration);
        tunnelRadius = node.getValue("tunnel_radius", tunnelRadius);
        blowtorch = node.getValue("blowtorch", blowtorch);
        interval = node.getValue("interval", interval);
    }

    override Shooter createShooter(Sprite go, GameEngine engine) {
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

    override bool delayedAction() {
        return internal_active;
    }

    bool activity() {
        return internal_active;
    }

    override protected void updateInternalActive() {
        //xxx simply activate "firing" state for drill weapon (like minigun...)
        if (myclass.blowtorch)
            mWorm.activateBlowtorch(internal_active);
        else
            mWorm.activateDrill(internal_active);
        if (internal_active)
            makeTunnel();
    }

    override protected void doFire(FireInfo info) {
        reduceAmmo();
        internal_active = true;
        mStart = mNext = engine.gameTime.current;
    }

    override protected bool doRefire() {
        internal_active = false;
        finished();
        return true;
    }

    override void simulate(float deltaT) {
        super.simulate(deltaT);
        if ((!mWorm.drillActivated() && !mWorm.blowtorchActivated())
            || engine.gameTime.current - mStart > myclass.duration)
        {
            doRefire();
            return;
        }
        if (engine.gameTime.current > mNext) {
            makeTunnel();
        }
    }

    private bool checkApply(ExplosiveForce sender, PhysicObject other) {
        //force applies to all objects, except the own worm
        return other !is mWorm.physics;
    }

    private void makeTunnel() {
        //xxx: stuff should be tuneable? (all constants != 0)
        Vector2f advVec = Vector2f(0, 7.0f);
        if (myclass.blowtorch) {
            advVec = mWorm.weaponDir*8.0f
                + Vector2f(0, mWorm.physics.posp.radius - myclass.tunnelRadius);
        }
        auto at = mWorm.physics.pos + advVec;
        engine.damageLandscape(toVector2i(at), myclass.tunnelRadius, mWorm);
        const cPush = 3.0f; //multiplier so that other worms get pushed away
        engine.explosionAt(at,
            myclass.tunnelRadius/ExplosiveForce.cDamageToRadius*cPush, mWorm,
            false, false, &checkApply);

        mNext = engine.gameTime.current + myclass.interval.sample(engine.rnd);
    }
}
