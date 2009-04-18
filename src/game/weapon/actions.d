module game.weapon.actions;

import common.resset;
import framework.framework;
import game.game;
import game.gobject;
import game.sprite;
import game.weapon.weapon;
import game.action;
import game.worm;
import game.glevel;
import game.levelgen.landscape;
import game.controller;
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
        damage = RandomFloat(node.getStringValue("damage", "5.0"), eng.rnd);
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
        usePos = node["target"] == "pos";
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
    Lexel bits;

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
        bits = Lexel.SolidSoft;
        //sorry, special cased
        if (node.getBoolValue("snow")) {
            bits |= cLandscapeSnowBit;
        }
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
            engine.insertIntoLandscape(p, res, myclass.bits);
        }
        return ActionRes.done;
    }
}

//------------------------------------------------------------------------

class DieActionClass : ActionClass {
    //xxx class
    this (ReflectCtor c) {
        super(c);
    }
    this () {
    }

    void loadFromConfig(GameEngine eng, ConfigNode node) {
    }

    DieAction createInstance(GameEngine eng) {
        return new DieAction(this, eng);
    }

    static this() {
        ActionClassFactory.register!(typeof(this))("die");
    }
}

class DieAction : WeaponAction {
    this(DieActionClass base, GameEngine eng) {
        super(base, eng);
    }

    this (ReflectCtor c) {
        super(c);
    }

    override protected ActionRes initialStep() {
        super.initialStep();
        mShootbyObj.pleasedie();
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

//team-affecting special commands: skip turn, surrender, enable worm switch
class TeamActionClass : ActionClass {
    char[] action;

    //xxx class
    this (ReflectCtor c) {
        super(c);
    }
    this () {
    }

    void loadFromConfig(GameEngine eng, ConfigNode node) {
        action = node["action"];
        if (action.length == 0)
            throw new Exception("Please set action");
    }

    TeamAction createInstance(GameEngine eng) {
        return new TeamAction(this, eng);
    }

    static this() {
        ActionClassFactory.register!(typeof(this))("team");
    }
}

class TeamAction : WeaponAction {
    private {
        TeamActionClass myclass;
        ServerTeamMember mMember;
    }

    this(TeamActionClass base, GameEngine eng) {
        super(base, eng);
        myclass = base;
    }

    this (ReflectCtor c) {
        super(c);
    }

    override protected ActionRes initialStep() {
        super.initialStep();
        auto w = cast(WormSprite)mShootbyObj;
        if (w) {
            mMember = engine.controller.memberFromGameObject(w, false);
            if (mMember) {
                switch (myclass.action) {
                    case "skipturn":
                        mMember.serverTeam.skipTurn();
                        engine.controller.messageAdd("msgskipturn",
                            [mMember.name(), mMember.serverTeam.name()]);
                        break;
                    case "surrender":
                        mMember.serverTeam.surrenderTeam();
                        engine.controller.messageAdd("msgsurrender",
                            [mMember.name(), mMember.serverTeam.name()]);
                        break;
                    case "wormselect":
                        return ActionRes.moreWork;
                        break;
                    default:
                }
            }
        }
        return ActionRes.done;
    }

    override void simulate(float deltaT) {
        super.simulate(deltaT);
        assert(!!mMember);
        //xxx: we just need the 1-frame delay for this because initialStep() is
        //     called from doFire, which will set mMember.mWormAction = true
        //     afterwards and would conflict with the code below
        mMember.serverTeam.allowSelect = true;
        mMember.resetActivity();
        done();
    }
}

//------------------------------------------------------------------------

//Base class for instant area-of-effect actions
abstract class AOEActionClass : ActionClass {
    float radius = 10.0f;
    bool[char[]] hit;

    //xxx class
    this (ReflectCtor c) {
        super(c);
    }
    this () {
    }

    void loadFromConfig(GameEngine eng, ConfigNode node) {
        radius = node.getValue!(float)("radius", radius);
        char[][] hitIds = node.getValue!(char[][])("hit", ["other"]);
        foreach (h; hitIds) {
            hit[h] = true;
        }
    }
}

abstract class AOEAction : WeaponAction {
    private {
        AOEActionClass myclass;
    }

    this(AOEActionClass base, GameEngine eng) {
        super(base, eng);
        myclass = base;
    }

    this (ReflectCtor c) {
        super(c);
    }

    private bool useObj(PhysicObject obj) {
        bool ret;
        bool isWorm = cast(WormSprite)obj.backlink !is null;
        bool isSelf = obj.backlink is mShootbyObj;
        bool isObject = cast(GObjectSprite)obj.backlink !is null;
        if ("other" in myclass.hit)
            ret |= isWorm && !isSelf;
        if ("self" in myclass.hit)
            ret |= isWorm && isSelf;
        if ("objects" in myclass.hit)
            ret |= !isWorm && isObject;
        return ret;
    }

    abstract protected void applyOn(GObjectSprite sprite);

    private void doApply(PhysicObject obj) {
        assert(!!obj.backlink);
        applyOn(cast(GObjectSprite)obj.backlink);
    }

    override protected ActionRes initialStep() {
        super.initialStep();
        if (mFireInfo.info.pos.isNaN())
            return ActionRes.done;
        engine.physicworld.objectsAtPred(mFireInfo.info.pos, myclass.radius,
            &doApply, &useObj);
        return ActionRes.done;
    }
}

//------------------------------------------------------------------------

//add an impulse to objects inside a circle
class ImpulseActionClass : AOEActionClass {
    float strength = 1000.0f;
    int directionMode = DirMode.fireInfo;
    Vector2f direction = Vector2f.nan;

    enum DirMode {
        fireInfo,
        outside,
        vector,
    }

    //xxx class
    this (ReflectCtor c) {
        super(c);
    }
    this () {
    }

    void loadFromConfig(GameEngine eng, ConfigNode node) {
        super.loadFromConfig(eng, node);
        strength = node.getValue!(float)("strength", strength);
        if (node["direction"] == "outside")
            directionMode = DirMode.outside;
        else if (node["direction"] != "") {
            directionMode = DirMode.vector;
            direction = node.getValue("direction", direction);
            if (direction.isNaN())
                throw new Exception("Direction vector is illegal");
        }
    }

    ImpulseAction createInstance(GameEngine eng) {
        return new ImpulseAction(this, eng);
    }

    static this() {
        ActionClassFactory.register!(typeof(this))("impulse");
    }
}

class ImpulseAction : AOEAction {
    private {
        ImpulseActionClass myclass;
    }

    this(ImpulseActionClass base, GameEngine eng) {
        super(base, eng);
        myclass = base;
    }

    this (ReflectCtor c) {
        super(c);
    }

    override protected void applyOn(GObjectSprite sprite) {
        Vector2f imp;
        switch (myclass.directionMode) {
            case ImpulseActionClass.DirMode.fireInfo:
                //FireInfo.dir (away from firing worm)
                imp = myclass.strength * mFireInfo.info.dir;
                break;
            case ImpulseActionClass.DirMode.outside:
                //away from center of hitpoint
                auto d = (sprite.physics.pos - mFireInfo.info.pos).normal;
                if (!d.isNaN())
                    imp = myclass.strength * d;
                break;
            default:
                //use direction vector from config file
                imp = myclass.strength * myclass.direction;
        }
        sprite.physics.addImpulse(imp);
    }
}

//------------------------------------------------------------------------

//add an impulse to objects inside a circle
class RelativeDamageActionClass : AOEActionClass {
    //how much damage relative to current HP the objects will receive
    float damage = 0.5f;

    //xxx class
    this (ReflectCtor c) {
        super(c);
    }
    this () {
    }

    void loadFromConfig(GameEngine eng, ConfigNode node) {
        super.loadFromConfig(eng, node);
        damage = node.getValue!(float)("damage", damage);
    }

    RelativeDamageAction createInstance(GameEngine eng) {
        return new RelativeDamageAction(this, eng);
    }

    static this() {
        ActionClassFactory.register!(typeof(this))("relativedmg");
    }
}

class RelativeDamageAction : AOEAction {
    private {
        RelativeDamageActionClass myclass;
    }

    this(RelativeDamageActionClass base, GameEngine eng) {
        super(base, eng);
        myclass = base;
    }

    this (ReflectCtor c) {
        super(c);
    }

    override protected void applyOn(GObjectSprite sprite) {
        float dmg = sprite.physics.lifepower*myclass.damage;
        if (myclass.damage < 1.0f-float.epsilon) {
            //don't kill
            dmg = min(dmg, sprite.physics.lifepower - 1.0f);
        }
        if (dmg <= 0)
            return;
        sprite.physics.applyDamage(dmg, DamageCause.special);
        //xxx stuck in the ground animation here
        sprite.physics.addImpulse(Vector2f(0, -1));
    }
}

