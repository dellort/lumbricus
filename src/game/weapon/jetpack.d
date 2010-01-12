module game.weapon.jetpack;

import framework.framework;
import game.game;
import game.gfxset;
import game.sprite;
import game.weapon.weapon;
import game.worm;
import game.sequence;
import game.wcontrol;
import gui.rendertext;
import physics.world;
import utils.configfile;
import utils.factory;
import utils.reflection;
import utils.time;
import utils.vector2;
import utils.log;
import utils.misc;

import tango.math.Math : abs;


//jetpack for a worm (special because it changes worm state)
class JetpackClass : ConfWeaponClass {
    //maximum active time, i.e. fuel
    Time maxTime = Time.Never;
    Vector2f jetpackThrust = {0f, 0f};
    bool stopOnDisable = true;

    this(GfxSet gfx, ConfigNode node) {
        super(gfx, node);
        maxTime = node.getValue("max_time", maxTime);
        jetpackThrust = node.getValue("jet_thrust", jetpackThrust);
        stopOnDisable = node.getValue("stop_on_disable", stopOnDisable);
    }

    //xxx class
    this (ReflectCtor c) {
        super(c);
    }

    override Shooter createShooter(Sprite go, GameEngine engine) {
        //for now, only worms are enabled to use tools
        //(because of special control methods, i.e. for jetpacks, ropes...)
        auto worm = cast(WormSprite)(go);
        if (!worm)
            throw new Exception(myformat("not a worm: {}", go));
        return new Jetpack(this, worm);
    }

    static this() {
        WeaponClassFactory.register!(typeof(this))("jetpack");
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
        super(base, a_owner, a_owner.engine);
        mWorm = a_owner;
        myclass = base;
        mMember = engine.controller.controlFromGameObject(mWorm, false);
    }

    this (ReflectCtor c) {
        super(c);
    }

    override bool delayedAction() {
        return false;
    }

    bool activity() {
        return internal_active;
    }

    override protected void doFire(FireInfo info) {
        reduceAmmo();
        mWorm.activateJetpack(true);
        internal_active = true;
    }

    override protected bool doRefire() {
        //second fire: deactivate jetpack again
        mWorm.activateJetpack(false);
        if (myclass.stopOnDisable) {
            //stop x movement
            mWorm.physics.addImpulse(-mWorm.physics.velocity.X
                * mWorm.physics.posp.mass);
        }
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
        if (internal_active && myclass.maxTime != Time.Never) {
            assert(!!mWorm.graphic);
            mTimeLabel = engine.gfx.textCreate();
            mWorm.graphic.attachText = mTimeLabel;
        } else {
            if (mTimeLabel && mWorm && mWorm.graphic) {
                mWorm.graphic.attachText = null;
                mTimeLabel = null;
            }
        }
    }

    override void simulate(float deltaT) {
        super.simulate(deltaT);
        //if it was used but it's not active anymore => die
        if (!mWorm.jetpackActivated()
            || mJetTimeUsed > myclass.maxTime.secsf)
        {
            mWorm.activateJetpack(false);
            mWorm.physics.selfForce = Vector2f(0);
            internal_active = false;
            finished();
            return;
        }
        if (mTimeLabel) {
            float remain = myclass.maxTime.secsf - mJetTimeUsed;
            mTimeLabel.setTextFmt(true, "{:f1}", remain);
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
        mJetTimeUsed += (xm + ym) * deltaT;
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

