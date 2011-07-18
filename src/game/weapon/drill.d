module game.weapon.drill;

import game.core;
import game.game;
import game.sprite;
import game.worm;
import game.weapon.weapon;
import physics.all;
import utils.math;
import utils.misc;
import utils.randval;
import utils.time;
import utils.vector2;

//drill (changes worm state etc.)
class DrillClass : WeaponClass {
    Time duration = timeSecs(5);
    int tunnelRadius = 8;
    RandomValue!(Time) interval = {timeMsecs(150), timeMsecs(250)};
    bool blowtorch = false;

    this(GameCore engine, string name) {
        super(engine, name);
    }

    override Shooter createShooter(Sprite go) {
        //for now, only worms are enabled to use tools
        //(because of special control methods, i.e. for jetpacks, ropes...)
        auto worm = cast(WormSprite)(go);
        if (!worm)
            throw new CustomException(myformat("not a worm: %s", go));
        return new Drill(this, worm);
    }
}

class Drill : Shooter {
    private {
        DrillClass myclass;
        WormSprite mWorm;
        Time mStart, mNext;
    }

    this(DrillClass base, WormSprite a_owner) {
        super(base, a_owner);
        mWorm = a_owner;
        myclass = base;
    }

    override protected void onWeaponActivate(bool active) {
        //xxx simply activate "firing" state for drill weapon (like minigun...)
        //^ what?

        if (myclass.blowtorch) {
            mWorm.activateBlowtorch(active);
            if (active)
                mWorm.physics.setWalking(
                    dirFromSideAngle(mWorm.physics.lookey, 0), true);
            else
                mWorm.physics.setWalking(Vector2f(0, 0));
        } else {
            mWorm.activateDrill(active);
            mWorm.physics.doUnglue();
        }

        if (active)
            makeTunnel();
    }

    override protected void doFire() {
        reduceAmmo();
        mStart = mNext = engine.gameTime.current;
    }

    override protected bool doRefire() {
        finished();
        return true;
    }

    override void simulate() {
        super.simulate();
        if (!weaponActive)
            return;
        if ((!mWorm.drillActivated() && !mWorm.blowtorchActivated())
            || engine.gameTime.current - mStart > myclass.duration
            || (myclass.blowtorch && !mWorm.physics.isWalking()))
        {
            finished();
            return;
        }
        if (engine.gameTime.current > mNext) {
            makeTunnel();
        }
    }

    private bool checkApply(PhysicObject other) {
        //force applies to all objects, except the own worm or landscape
        return other !is mWorm.physics && !other.isStatic;
    }

    private void makeTunnel() {
        //xxx: stuff should be tuneable? (all constants != 0)
        Vector2f advVec = Vector2f(0, 7.0f);
        if (myclass.blowtorch) {
            advVec = weaponDir*10.0f
                + Vector2f(0, owner.physics.posp.radius - myclass.tunnelRadius);
        }
        auto at = owner.physics.pos + advVec;
        GameEngine rengine = GameEngine.fromCore(engine);
        rengine.damageLandscape(toVector2i(at), myclass.tunnelRadius, owner);
        const cPush = 3.0f; //multiplier so that other worms get pushed away
        rengine.explosionAt(at,
            myclass.tunnelRadius/GameEngine.cDamageToRadius*cPush, owner,
            false, &checkApply);

        mNext = engine.gameTime.current + myclass.interval.sample(engine.rnd);
    }

    override bool isFixed() {
        //like LuaShooter with isFixed = false
        return activity && (currentState != WeaponState.fire);
    }
}
