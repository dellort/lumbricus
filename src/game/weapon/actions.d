module game.weapon.actions;

import game.game;
import game.gobject;
import game.sprite;
import game.weapon.weapon;
import game.action;
import game.worm;
import physics.world;
import utils.configfile;
import utils.time;
import utils.vector2;

class ExplosionActionClass : ActionClass {
    float damage = 5.0f;

    void loadFromConfig(ConfigNode node) {
        damage = node.getFloatValue("damage", damage);
    }

    ExplosionAction createInstance(GameEngine eng) {
        return new ExplosionAction(this, eng);
    }

    static this() {
        ActionClassFactory.register!(typeof(this))("explosion");
    }
}

class ExplosionAction : Action {
    private {
        ExplosionActionClass myclass;
        FireInfo* fi;
        PhysicObject shootby;
        GameObject shootby_obj;
    }

    this(ExplosionActionClass base, GameEngine eng) {
        super(base, eng);
        myclass = base;
    }

    override protected void initialStep() {
        //xxx parameter stuff is a bit weird
        fi = params.getPar!(FireInfo)("fireinfo");
        shootby_obj = *params.getPar!(GameObject)("owner_game");
        //delay is not used, use ActionList looping for this
        if (!fi.pos.isNaN)
            engine.explosionAt(fi.pos, myclass.damage, shootby_obj);
        done();
    }
}

class BeamActionClass : ActionClass {
    bool usePos = false;

    void loadFromConfig(ConfigNode node) {
        usePos = node.valueIs("target", "pos");
    }

    BeamAction createInstance(GameEngine eng) {
        return new BeamAction(this, eng);
    }

    static this() {
        ActionClassFactory.register!(typeof(this))("beam");
    }
}

class BeamAction : Action {
    private {
        BeamActionClass myclass;
        FireInfo* fi;
        PhysicObject shootby;
        WormSprite mWorm;

        Vector2f mDest;
    }

    this(BeamActionClass base, GameEngine eng) {
        super(base, eng);
        myclass = base;
    }

    override protected void initialStep() {
        //xxx parameter stuff is a bit weird
        fi = params.getPar!(FireInfo)("fireinfo");
        mWorm = cast(WormSprite)*params.getPar!(GameObject)("owner_game");
        //delay is not used, use ActionList looping for this
        if (!fi.pos.isNaN && mWorm) {
            if (myclass.usePos)
                mDest = fi.pos;
            else
                mDest = fi.pointto;
            //first play animation where worm talks into its communicator
            engine.mLog("start beaming");
            mWorm.beamTo(mDest);
        } else {
            done();
        }
    }

    override void simulate(float deltaT) {
        super.simulate(deltaT);
        if (!mWorm.isBeaming) {
            engine.mLog("end beaming");
            done();
        }
    }
}
