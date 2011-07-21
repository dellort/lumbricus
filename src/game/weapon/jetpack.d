module game.weapon.jetpack;

import game.controller;
import game.core;
import game.sprite;
import game.weapon.weapon;
import game.worm;
import game.sequence;
import game.teamtheme;
import game.wcontrol;
import gui.rendertext;
import physics.all;
import utils.time;
import utils.vector2;
import utils.misc;

import std.math;


//jetpack for a worm (special because it changes worm state)
class JetpackClass : WeaponClass {
    //maximum active time, i.e. fuel
    Time maxTime = Time.Never;
    Vector2f jetpackThrust = {0f, 0f};
    bool stopOnDisable = true;

    this(GameCore a_engine, string name) {
        super(a_engine, name);
    }

    override Shooter createShooter(Sprite go) {
        //for now, only worms are enabled to use tools
        //(because of special control methods, i.e. for jetpacks, ropes...)
        auto worm = cast(WormSprite)(go);
        if (!worm)
            throw new CustomException(myformat("not a worm: %s", go));
        return new Jetpack(this, worm);
    }
}

class Jetpack : Shooter, Controllable {
    private {
        FormattedText mTimeLabel;
        JetpackClass myclass;
        WormSprite mWorm;
        Vector2f mMoveVector;
        float mJetTimeUsed = 0f;
        WormControl mMember;
    }

    this(JetpackClass base, WormSprite a_owner) {
        super(base, a_owner);
        mWorm = a_owner;
        myclass = base;
        auto controller = engine.singleton!(GameController)();
        mMember = controller.controlFromGameObject(mWorm, false);
    }

    override bool delayedAction() {
        return false;
    }

    override protected void doFire() {
        reduceAmmo();
    }

    override protected bool doRefire() {
        //second fire: deactivate jetpack again
        if (myclass.stopOnDisable) {
            //stop x movement
            mWorm.physics.addImpulse(-mWorm.physics.velocity.X
                * mWorm.physics.posp.mass);
        }
        finished();
        return true;
    }

    override protected void onWeaponActivate(bool active) {
        if (active) {
            mWorm.activateJetpack(true);
            mMember.pushControllable(this);
            mJetTimeUsed = 0f;
        } else {
            mWorm.activateJetpack(false);
            mMember.releaseControllable(this);
            mWorm.physics.selfForce = Vector2f(0);
        }
        if (active && myclass.maxTime != Time.Never) {
            assert(!!mWorm.graphic);
            mTimeLabel = WormLabels.textCreate();
            mWorm.graphic.attachText = mTimeLabel;
        } else {
            if (mTimeLabel && mWorm && mWorm.graphic) {
                mWorm.graphic.attachText = null;
                mTimeLabel = null;
            }
        }
    }

    override void simulate() {
        super.simulate();
        if (!weaponActive)
            return;
        //if it was used but it's not active anymore => die
        if (!mWorm.jetpackActivated()
            || mJetTimeUsed > myclass.maxTime.secsf)
        {
            finished();
            return;
        }
        if (mTimeLabel) {
            float remain = myclass.maxTime.secsf - mJetTimeUsed;
            mTimeLabel.setTextFmt(true, "%.1f", remain);
        }

        //force!
        Vector2f jetForce = mMoveVector.mulEntries(myclass.jetpackThrust);
        //don't accelerate down
        if (jetForce.y > 0)
            jetForce.y = 0;
        mWorm.physics.selfForce = jetForce;
        float xm = abs(mMoveVector.x);
        float ym = (mMoveVector.y < 0) ? -mMoveVector.y : 0f;
        //acc. seconds for all active thrusters
        mJetTimeUsed += (xm + ym) * engine.gameTime.difference.secsf;
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

