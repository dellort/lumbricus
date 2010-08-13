module game.weapon.parachute;

import framework.framework;
import game.controller;
import game.core;
import game.sprite;
import game.weapon.weapon;
import game.worm;
import game.sequence;
import game.wcontrol;
import physics.all;
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
        float mTriggerVel;
    }

    this(ParachuteClass base, WormSprite a_owner) {
        super(base, a_owner);
        mWorm = a_owner;
        myclass = base;
        auto controller = engine.singleton!(GameController)();
        mMember = controller.controlFromGameObject(mWorm, false);
        auto wsc = castStrict!(WormSpriteClass)(mWorm.type);
        mTriggerVel = wsc.rollVelocity*0.8f;
    }

    override bool delayedAction() {
        return false;
    }

    override protected void doFire() {
        reduceAmmo();
    }

    override protected bool doRefire() {
        finished();
        return true;
    }

    override protected void onWeaponActivate(bool active) {
        mWorm.activateParachute(active);
        if (active) {
            mMember.pushControllable(this);
            OnSpriteImpact.handler(mWorm.instanceLocalEvents,
                &onSpriteImpact_Worm);
        } else {
            mMember.releaseControllable(this);
            mWorm.physics.selfForce = Vector2f(0);
            OnSpriteImpact.remove_handler(mWorm.instanceLocalEvents,
                &onSpriteImpact_Worm);
        }
    }

    override void simulate() {
        super.simulate();

        //trigger when the worm is flying fast enough
        if (currentState == WeaponState.idle && !isSelected
            && mWorm.currentState.name == "fly"
            && mWorm.physics.velocity.y >= mTriggerVel)
        {
            instantFireInternal();
        }

        if (!weaponActive)
            return;

        if (!mWorm.parachuteActivated() || mWorm.physics.isGlued) {
            finished();
            return;
        }

        //slight control with arrow keys
        float force = mMoveVector.x * myclass.sideForce;
        mWorm.physics.selfForce = Vector2f(force, 0);
    }

    private void onSpriteImpact_Worm(Sprite sender, PhysicObject other,
        Vector2f normal)
    {
        //abort parachute when the worm hit something
        if (sender is mWorm) {
            finished();
        }
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
