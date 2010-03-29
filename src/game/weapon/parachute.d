module game.weapon.parachute;

import framework.framework;
import game.controller;
import game.core;
import game.sprite;
import game.weapon.weapon;
import game.worm;
import game.sequence;
import game.wcontrol;
import physics.world;
import utils.time;
import utils.vector2;
import utils.misc;

import tango.math.Math : abs;


class ParachuteClass : WeaponClass {
    float sideForce = 0f;

    this(GameCore engine, char[] name) {
        super(engine, name);
    }

    override Shooter createShooter(Sprite go) {
        //for now, only worms are enabled to use tools
        //(because of special control methods, i.e. for jetpacks, ropes...)
        auto worm = cast(WormSprite)(go);
        if (!worm)
            throw new CustomException(myformat("not a worm: {}", go));
        return new Parachute(this, worm);
    }
}

class Parachute : Shooter, Controllable {
    private {
        ParachuteClass myclass;
        WormSprite mWorm;
        Vector2f mMoveVector;
        WormControl mMember;
    }

    this(ParachuteClass base, WormSprite a_owner) {
        super(base, a_owner, a_owner.engine);
        mWorm = a_owner;
        myclass = base;
        auto controller = engine.singleton!(GameController)();
        mMember = controller.controlFromGameObject(mWorm, false);
    }

    override bool delayedAction() {
        return false;
    }

    bool activity() {
        return internal_active;
    }

    override protected void doFire(FireInfo info) {
        reduceAmmo();
        mWorm.activateParachute(true);
        internal_active = true;
    }

    override protected bool doRefire() {
        mWorm.activateParachute(false);
        internal_active = false;
        finished();
        return true;
    }

    override protected void updateInternalActive() {
        super.updateInternalActive();
        if (internal_active) {
            mMember.pushControllable(this);
        } else {
            mMember.releaseControllable(this);
            mWorm.physics.selfForce = Vector2f(0);
        }
    }

    override void simulate() {
        super.simulate();

        if (!mWorm.parachuteActivated()) {
            internal_active = false;
            finished();
            return;
        }

        float force = mMoveVector.x * myclass.sideForce;
        mWorm.physics.selfForce = Vector2f(force, 0);

        if (mWorm.physics.isGlued)
            internal_active = false;
    }

    //Controllable implementation -->

    bool fire(bool keyDown) {
        return false;
    }

    bool jump(JumpMode j) {
        return false;
    }

    bool move(Vector2f m) {
        mMoveVector = m;
        return true;
    }

    Sprite getSprite() {
        return mWorm;
    }

    //<-- Controllable end
}
