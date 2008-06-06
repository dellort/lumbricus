module game.weapon.actions;

import framework.framework;
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

///Causes an explosion at FireInfo.pos
class ExplosionActionClass : ActionClass {
    float damage = 5.0f;

    void loadFromConfig(GameEngine eng, ConfigNode node) {
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
        if (!fi.pos.isNaN)
            engine.explosionAt(fi.pos, myclass.damage, shootby_obj);
        done();
    }
}

//------------------------------------------------------------------------

///Teleports the owner (must be a worm sprite) to FireInfo.pos/FireInfo.pointto
class BeamActionClass : ActionClass {
    //beam to FireInfo.pos (FireInfo.pointto otherwise)
    bool usePos = false;

    void loadFromConfig(GameEngine eng, ConfigNode node) {
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
        if (!fi.pos.isNaN && mWorm) {
            if (myclass.usePos)
                mDest = fi.pos;
            else
                mDest = fi.pointto;
            //WormSprite.beamTo does all the work, just wait for it to finish
            engine.mLog("start beaming");
            mWorm.beamTo(mDest);
        } else {
            //error
            done();
        }
    }

    override void simulate(float deltaT) {
        super.simulate(deltaT);
        if (!mWorm.isBeaming) {
            //beaming is over, finish
            engine.mLog("end beaming");
            done();
        }
    }
}

//------------------------------------------------------------------------

///Inserts a bitmap into the landscape at FireInfo.pos
class InsertBitmapActionClass : ActionClass {
    Resource!(Surface) bitmap;

    void loadFromConfig(GameEngine eng, ConfigNode node) {
        //prepare bitmap resource
        bitmap = eng.gfx.resources.resource!(Surface)(
            node.getStringValue("source"));
    }

    InsertBitmapAction createInstance(GameEngine eng) {
        return new InsertBitmapAction(this, eng);
    }

    static this() {
        ActionClassFactory.register!(typeof(this))("bitmap");
    }
}

class InsertBitmapAction : Action {
    private {
        InsertBitmapActionClass myclass;
        FireInfo* fi;
        PhysicObject shootby;
        GameObject shootby_obj;
    }

    this(InsertBitmapActionClass base, GameEngine eng) {
        super(base, eng);
        myclass = base;
    }

    override protected void initialStep() {
        //xxx parameter stuff is a bit weird
        fi = params.getPar!(FireInfo)("fireinfo");
        shootby_obj = *params.getPar!(GameObject)("owner_game");
        if (!fi.pos.isNaN && myclass.bitmap.defined()) {
            //centered at FireInfo.pos
            auto p = toVector2i(fi.pos);
            auto res = myclass.bitmap;
            p -= res.get.size / 2;
            engine.insertIntoLandscape(p, res);
        }
        done();
    }
}

//------------------------------------------------------------------------

///Causes an earthquake and returns only after its finished
class EarthquakeActionClass : ActionClass {
    float strength, degrade;
    Time duration;
    int waterRaise;

    void loadFromConfig(GameEngine eng, ConfigNode node) {
        strength = node.getFloatValue("strength", 100.0f);
        degrade = node.getFloatValue("degrade", 1.0f);
        duration = timeMsecs(node.getIntValue("duration_ms", 1000));
        waterRaise = node.getIntValue("water_raise", 0);
    }

    EarthquakeAction createInstance(GameEngine eng) {
        return new EarthquakeAction(this, eng);
    }

    static this() {
        ActionClassFactory.register!(typeof(this))("earthquake");
    }
}

class EarthquakeAction : Action {
    private {
        EarthquakeActionClass myclass;
        PhysicBase mEarthquake;
        Time mEndtime;
    }

    this(EarthquakeActionClass base, GameEngine eng) {
        super(base, eng);
        myclass = base;
    }

    override protected void initialStep() {
        //raise water
        if (myclass.waterRaise > 0) {
            engine.raiseWater(myclass.waterRaise);
        }
        //earthquake
        if (myclass.duration >= Time.Null && myclass.strength >= 0) {
            mEarthquake = new EarthQuakeDegrader(myclass.strength,
                myclass.degrade, engine.earthQuakeForce);
            engine.physicworld.addBaseObject(mEarthquake);
            //wait for it to finish
            mEndtime = engine.gameTime.current + myclass.duration;
        } else {
            done();
        }
    }

    override void simulate(float deltaT) {
        super.simulate(deltaT);
        if (engine.gameTime.current >= mEndtime) {
            mEarthquake.dead = true;
            mEarthquake = null;
            done();
        }
    }

    override void abort() {
        //make sure earthquake stops on abort
        //xxx not sure about that, what if worm drowns?
        if (mEarthquake) {
            mEarthquake.dead = true;
            mEarthquake = null;
        }
        super.abort();
    }
}

//------------------------------------------------------------------------
