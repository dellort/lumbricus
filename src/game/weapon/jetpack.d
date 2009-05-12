module game.weapon.jetpack;

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

import tango.math.Math : abs;
import tango.math.IEEE : isInfinity;


//jetpack for a worm (special because it changes worm state)
class JetpackClass : WeaponClass {
    //maximum active time, i.e. fuel
    float maxSeconds = float.infinity;

    this(GameEngine engine, ConfigNode node) {
        super(engine, node);
        maxSeconds = node.getValue("max_seconds", maxSeconds);
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
        return new Jetpack(this, worm);
    }

    static this() {
        WeaponClassFactory.register!(typeof(this))("jetpack");
    }
}

class Jetpack : Shooter {
    private {
        TextGraphic mTimeLabel;
        JetpackClass myclass;
        WormSprite mWorm;
    }

    this(JetpackClass base, WormSprite a_owner) {
        super(base, a_owner, a_owner.engine);
        mWorm = a_owner;
        myclass = base;
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
        mWorm.activateJetpack(true);
        active = true;
    }

    override protected bool doRefire() {
        //second fire: deactivate jetpack again
        mWorm.activateJetpack(false);
        active = false;
        finished();
        return true;
    }

    override protected void updateActive() {
        super.updateActive();
        if (active && !isInfinity(myclass.maxSeconds)) {
            mTimeLabel = new TextGraphic();
            mTimeLabel.msg.id = "game_msg.jetpacktime";
            mTimeLabel.attach = Vector2f(0.5f, 1.0f);
            engine.graphics.add(mTimeLabel);
        } else {
            if (mTimeLabel) {
                mTimeLabel.remove();
                mTimeLabel = null;
            }
        }
    }

    override void simulate(float deltaT) {
        super.simulate(deltaT);
        //if it was used but it's not active anymore => die
        if (!mWorm.jetpackActivated()
            || mWorm.jetpackTimeUsed > myclass.maxSeconds)
        {
            mWorm.activateJetpack(false);
            active = false;
            finished();
        }
        if (mTimeLabel) {
            //xxx I'm not gonna copy+paste the crap in crate.d,
            //    pls fix TextGraphic and remove this hack
            mTimeLabel.pos = toVector2i(mWorm.physics.pos) - Vector2i(0, 30);
            float remain = myclass.maxSeconds - mWorm.jetpackTimeUsed;
            mTimeLabel.msg.args = [myformat("{:f1}", remain)];
        }
    }
}

