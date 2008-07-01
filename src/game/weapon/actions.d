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

///Base class for weapon-activated actions (just for parameter handling)
class WeaponAction : Action {
    protected {
        FireInfo* mFireInfo;
        GameObject mShootbyObj;
    }

    this(ActionClass base, GameEngine eng) {
        super(base, eng);
    }

    override protected ActionRes initialStep() {
        super.initialStep();
        mFireInfo = context.getPar!(FireInfo*)("fireinfo");
        mShootbyObj = context.getPar!(GameObject)("owner_game");
        //obligatory parameters for WeaponAction
        assert(mFireInfo && !!mShootbyObj);
        return ActionRes.done;
    }
}

//------------------------------------------------------------------------

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

class ExplosionAction : WeaponAction {
    private {
        ExplosionActionClass myclass;
    }

    this(ExplosionActionClass base, GameEngine eng) {
        super(base, eng);
        myclass = base;
    }

    override protected ActionRes initialStep() {
        super.initialStep();
        if (!mFireInfo.pos.isNaN)
            engine.explosionAt(mFireInfo.pos, myclass.damage, mShootbyObj);
        return ActionRes.done;
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

class BeamAction : WeaponAction {
    private {
        BeamActionClass myclass;
        WormSprite mWorm;

        Vector2f mDest;
    }

    this(BeamActionClass base, GameEngine eng) {
        super(base, eng);
        myclass = base;
    }

    override protected ActionRes initialStep() {
        super.initialStep();
        //xxx parameter stuff is a bit weird
        mWorm = cast(WormSprite)mShootbyObj;
        if (!mFireInfo.pos.isNaN && mWorm) {
            if (myclass.usePos)
                mDest = mFireInfo.pos;
            else
                mDest = mFireInfo.pointto;
            //WormSprite.beamTo does all the work, just wait for it to finish
            engine.mLog("start beaming");
            mWorm.beamTo(mDest);
            return ActionRes.moreWork;
        } else {
            //error
            return ActionRes.done;
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

class InsertBitmapAction : WeaponAction {
    private {
        InsertBitmapActionClass myclass;
    }

    this(InsertBitmapActionClass base, GameEngine eng) {
        super(base, eng);
        myclass = base;
    }

    override protected ActionRes initialStep() {
        super.initialStep();
        if (!mFireInfo.pos.isNaN && myclass.bitmap.defined()) {
            //centered at FireInfo.pos
            auto p = toVector2i(mFireInfo.pos);
            auto res = myclass.bitmap;
            p -= res.get.size / 2;
            engine.insertIntoLandscape(p, res);
        }
        return ActionRes.done;
    }
}

//------------------------------------------------------------------------

///Causes an earthquake and returns only after its finished
class EarthquakeActionClass : TimedActionClass {
    float strength, degrade;
    int waterRaise;

    void loadFromConfig(GameEngine eng, ConfigNode node) {
        super.loadFromConfig(eng, node);
        strength = node.getFloatValue("strength", 100.0f);
        degrade = node.getFloatValue("degrade", 1.0f);
        waterRaise = node.getIntValue("water_raise", 0);
    }

    EarthquakeAction createInstance(GameEngine eng) {
        return new EarthquakeAction(this, eng);
    }

    static this() {
        ActionClassFactory.register!(typeof(this))("earthquake");
    }
}

class EarthquakeAction : TimedAction {
    private {
        EarthquakeActionClass myclass;
        PhysicBase mEarthquake;
    }

    this(EarthquakeActionClass base, GameEngine eng) {
        super(base, eng);
        myclass = base;
    }

    override protected ActionRes doImmediate() {
        if (myclass.waterRaise > 0) {
            engine.raiseWater(myclass.waterRaise);
        }
        return ActionRes.moreWork;
    }

    override protected ActionRes initDeferred() {
        if (myclass.strength > 0) {
            mEarthquake = new EarthQuakeDegrader(myclass.strength,
                myclass.degrade, engine.earthQuakeForce);
            engine.physicworld.add(mEarthquake);
            return ActionRes.moreWork;
        } else {
            return ActionRes.done;
        }
    }

    override protected void cleanupDeferred() {
        //xxx not sure about that, what if worm drowns?
        mEarthquake.dead = true;
        mEarthquake = null;
    }

    override void simulate(float deltaT) {
        if (mEarthquake.dead) {
            //earthquake has fully degraded
            cleanupDeferred();
            done();
        } else {
            super.simulate(deltaT);
        }
    }
}

//------------------------------------------------------------------------
