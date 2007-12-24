module game.tools;

import game.game;
import game.sprite;
import game.weapon;
import game.worm;
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
        WeaponClassFactory.register!(typeof(this))("tools_mc");
    }
}

class Tool : Shooter {
    protected ToolClass mToolClass;
    protected WormSprite mWorm;
    this(ToolClass base, WormSprite a_owner) {
        super(base, a_owner, a_owner.engine);
        mToolClass = base;
        mWorm = a_owner;
    }

    bool activity() {
        return active;
    }
}

class Beamer : Tool {
    private {
        bool mStartBeaming;
        Time mWhenStart;
        Vector2f mDest;
    }

    this(ToolClass b, WormSprite o) {
        super(b, o);
    }

    override void fire(FireInfo info) {
        if (active)
            return; //while beaming
        active = true;
        mDest = info.pointto;
        //first play animation where worm talks into its communicator
        engine.mLog("wait for beaming");
        mStartBeaming = true;
        mWhenStart = engine.gameTime.current +
            weapon.animations[WeaponWormAnimations.Fire].get()
            .duration();
    }

    override void simulate(float deltaT) {
        super.simulate(deltaT);
        if (mStartBeaming) {
            if (mWhenStart <= engine.gameTime.current) {
                engine.mLog("start beaming");
                mStartBeaming = false;
                mWorm.beamTo(mDest);
            }
        } else if (!mWorm.isBeaming) {
            active = false;
            engine.mLog("end beaming");
        }
    }

    static this() {
        ToolsFactory.register!(typeof(this))("beamer");
    }
}

class Jetpack : Tool {
    private {
        bool mUsed;
    }

    this(ToolClass b, WormSprite o) {
        super(b, o);
    }

    override void fire(FireInfo info) {
        if (!mUsed) {
            mWorm.activateJetpack(true);
            mUsed = true;
            active = true;
        } else {
            //second fire: deactivate jetpack again
            mWorm.activateJetpack(false);
            active = false;
        }
    }

    override void simulate(float deltaT) {
        super.simulate(deltaT);
        //if it was used but it's not active anymore => die
        if (mUsed && !mWorm.jetpackActivated())
            active = false;
    }

    static this() {
        ToolsFactory.register!(typeof(this))("jetpack");
    }
}

class Rope : Tool {
    this(ToolClass b, WormSprite o) {
        super(b, o);
    }

    override void fire(FireInfo info) {
    }

    override void simulate(float deltaT) {
        super.simulate(deltaT);
    }

    static this() {
        ToolsFactory.register!(typeof(this))("rope");
    }
}
