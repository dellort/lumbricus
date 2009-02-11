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
import utils.randval;
import utils.reflection;

///Base class for weapon-activated actions (just for parameter handling)
class WeaponAction : Action {
    protected {
        //NO. JUST NO. FireInfo* mFireInfo;
        WrapFireInfo mFireInfo;
        GObjectSprite mShootbyObj; //parent sprite, for relative positioning
        GameObject mCreatedBy;  //parent object, for cause-victim relation
                                //can, but does not have to be, == mShootbyObj
    }

    this(ActionClass base, GameEngine eng) {
        super(base, eng);
    }

    this (ReflectCtor c) {
        super(c);
    }

    override protected ActionRes initialStep() {
        super.initialStep();
        mFireInfo = context.getPar!(WrapFireInfo)("fireinfo");
        mCreatedBy = context.getPar!(GameObject)("created_by");
        mShootbyObj = context.getPar!(GObjectSprite)("owner_sprite");
        //obligatory parameters for WeaponAction
        assert(mFireInfo && !!mShootbyObj && !!mCreatedBy);
        return ActionRes.done;
    }
}

//------------------------------------------------------------------------

///Causes an explosion at FireInfo.pos
class ExplosionActionClass : ActionClass {
    RandomFloat damage;

    //xxx class
    this (ReflectCtor c) {
        super(c);
    }
    this () {
    }

    void loadFromConfig(GameEngine eng, ConfigNode node) {
        damage = RandomFloat(node.getStringValue("damage", "5.0"));
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

    this (ReflectCtor c) {
        super(c);
    }

    override protected ActionRes initialStep() {
        super.initialStep();
        if (!mFireInfo.info.pos.isNaN)
            engine.explosionAt(mFireInfo.info.pos, myclass.damage.sample(),
                mCreatedBy);
        return ActionRes.done;
    }
}

//------------------------------------------------------------------------

///Teleports the owner (must be a worm sprite) to FireInfo.pos/FireInfo.pointto
class BeamActionClass : ActionClass {
    //beam to FireInfo.pos (FireInfo.pointto otherwise)
    bool usePos = false;

    //xxx class
    this (ReflectCtor c) {
        super(c);
    }
    this () {
    }

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

    this (ReflectCtor c) {
        super(c);
    }

    override protected ActionRes initialStep() {
        super.initialStep();
        //xxx parameter stuff is a bit weird
        mWorm = cast(WormSprite)mShootbyObj;
        if (!mFireInfo.info.pos.isNaN && mWorm) {
            if (myclass.usePos)
                mDest = mFireInfo.info.pos;
            else
                mDest = mFireInfo.info.pointto;
            //WormSprite.beamTo does all the work, just wait for it to finish
            log("start beaming");
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
            log("end beaming");
            mWorm = null;
            done();
        }
    }

    override void abort() {
        if (mWorm) {
            if (mWorm.isBeaming)
                mWorm.abortBeaming();
        }
        done();
    }
}

//------------------------------------------------------------------------

///Inserts a bitmap into the landscape at FireInfo.pos
class InsertBitmapActionClass : ActionClass {
    Resource!(Surface) bitmap;

    //xxx class
    this (ReflectCtor c) {
        super(c);
    }
    this () {
    }

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

    this (ReflectCtor c) {
        super(c);
    }

    override protected ActionRes initialStep() {
        super.initialStep();
        if (!mFireInfo.info.pos.isNaN && myclass.bitmap.get() !is null) {
            //centered at FireInfo.pos
            auto p = toVector2i(mFireInfo.info.pos);
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

    //xxx class
    this (ReflectCtor c) {
        super(c);
    }
    this () {
    }

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

    this (ReflectCtor c) {
        super(c);
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
