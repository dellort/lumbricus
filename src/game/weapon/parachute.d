module game.weapon.parachute;

import framework.framework;
import game.game;
import game.gfxset;
import game.sprite;
import game.weapon.weapon;
import game.worm;
import game.sequence;
import game.wcontrol;
import physics.world;
import utils.configfile;
import utils.factory;
import utils.reflection;
import utils.time;
import utils.vector2;
import utils.log;
import utils.misc;

import tango.math.Math : abs;


class ParachuteClass : WeaponClass {
    float sideForce = 0f;

    this(GfxSet gfx, ConfigNode node) {
        super(gfx, node);
        sideForce = node.getValue("side_force", sideForce);
    }

    //xxx class
    this (ReflectCtor c) {
        super(c);
    }

    override Shooter createShooter(GObjectSprite go, GameEngine engine) {
        //for now, only worms are enabled to use tools
        //(because of special control methods, i.e. for jetpacks, ropes...)
        auto worm = cast(WormSprite)(go);
        if (!worm)
            throw new Exception(myformat("not a worm: {}", go));
        return new Parachute(this, worm);
    }

    static this() {
        WeaponClassFactory.register!(typeof(this))("parachute");
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
        mMember = engine.controller.controlFromGameObject(mWorm, false);
    }

    this (ReflectCtor c) {
        super(c);
    }

    override bool delayedAction() {
        return false;
    }

    bool activity() {
        return active;
    }

    override protected void doFire(FireInfo info) {
        reduceAmmo();
        mWorm.activateParachute(true);
        active = true;
    }

    override protected bool doRefire() {
        mWorm.activateParachute(false);
        active = false;
        finished();
        return true;
    }

    override protected void updateActive() {
        super.updateActive();
        if (active) {
            mMember.pushControllable(this);
        } else {
            mMember.releaseControllable(this);
            mWorm.physics.selfForce = Vector2f(0);
        }
    }

    override void simulate(float deltaT) {
        super.simulate(deltaT);

        if (!mWorm.parachuteActivated()) {
            active = false;
            finished();
            return;
        }

        float force = mMoveVector.x * myclass.sideForce;
        mWorm.physics.selfForce = Vector2f(force, 0);

        if (mWorm.physics.isGlued)
            active = false;
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

    GObjectSprite getSprite() {
        return mWorm;
    }

    //<-- Controllable end
}
