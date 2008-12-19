module game.weapon.tools;

import game.game;
import game.sprite;
import game.weapon.weapon;
import game.worm;
import physics.world;
import utils.configfile;
import utils.factory;
import utils.time;
import utils.vector2;

import std.string : format;

//sub-factory used by ToolClass (stupid double-factory)
class ToolsFactory : StaticFactory!(Tool, ToolClass, WormSprite) {
}

//covers tools like jetpack, beamer, superrope
//these are not actually weapons, but the weapon-code is generic enough to
//cover these tools (including weapon window etc.)
class ToolClass : WeaponClass {
    private {
        char[] mSubType;
    }

    this(GameEngine engine, ConfigNode node) {
        super(engine, node);
        mSubType = node.getStringValue("subtype", "none");
    }

    override Shooter createShooter(GObjectSprite go) {
        //for now, only worms are enabled to use tools
        //(because of special control methods, i.e. for jetpacks, ropes...)
        auto worm = cast(WormSprite)(go);
        if (!worm)
            throw new Exception(format("not a worm: %s", go));
        return ToolsFactory.instantiate(mSubType, this, worm);
    }

    static this() {
        WeaponClassFactory.register!(typeof(this))("tool");
    }
}

class Tool : Shooter {
    protected ToolClass mToolClass;
    protected WormSprite mWorm;

    override bool delayedAction() {
        return false;
    }

    this(ToolClass base, WormSprite a_owner) {
        super(base, a_owner, a_owner.engine);
        mToolClass = base;
        mWorm = a_owner;
    }

    bool activity() {
        return active;
    }
}

class Jetpack : Tool {
    this(ToolClass b, WormSprite o) {
        super(b, o);
    }

    override protected void doFire(FireInfo info) {
        reduceAmmo();
        mWorm.activateJetpack(true);
        active = true;
    }

    override protected void doRefire() {
        //second fire: deactivate jetpack again
        mWorm.activateJetpack(false);
        active = false;
        finished();
    }

    override void simulate(float deltaT) {
        super.simulate(deltaT);
        //if it was used but it's not active anymore => die
        if (!mWorm.jetpackActivated()) {
            active = false;
            finished();
        }
    }

    static this() {
        ToolsFactory.register!(typeof(this))("jetpack");
    }
}

class Rope : Tool {
    private {
        bool mUsed;
        PhysicConstraint mRope;
    }

    this(ToolClass b, WormSprite o) {
        super(b, o);
    }

    override protected void doFire(FireInfo info) {
        reduceAmmo();
        float len = (mWorm.physics.pos - info.pointto).length * 0.9f;
        mRope = new PhysicConstraint(mWorm.physics, info.pointto, len, 0.1, true);
        engine.physicworld.add(mRope);
        active = true;
    }

    override protected void doRefire() {
        //second fire: deactivate rope
        mRope.dead = true;
        active = false;
        finished();
    }

    override void interruptFiring() {
        if (active) {
            mRope.dead = true;
            active = false;
            finished();
        }
    }

    static this() {
        ToolsFactory.register!(typeof(this))("rope");
    }
}
