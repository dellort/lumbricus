module game.action.weaponactions;

import common.resset;
import framework.framework;
import game.action.base;
import game.action.wcontext;
import game.game;
import game.gfxset;
import game.gobject;
import game.sprite;
import game.weapon.weapon;
import game.worm;
import game.glevel;
import game.levelgen.landscape;
import game.controller;
import game.actionsprite;
import game.weapon.projectile;
import physics.world;
import utils.configfile;
import utils.time;
import utils.vector2;
import utils.randval;
import utils.reflection;
import utils.misc;
import utils.log;

import tango.math.Math : sqrt;

private LogStruct!("WeaponActions") log;

void dummy(ActionContext ctx) {
}

static this() {
    regAction!(explosion, "damage = 5.0")("explosion");
    regAction!(bitmap, "source, snow")("bitmap");
    regAction!(beam, "pos")("beam");
    regAction!(die, "")("die");
    regAction!(earthquake, "strength = 100, degrade = true, water_raise, "
        ~ "bounce_objects, nuke_effect, duration = 1s")("earthquake");
    regAction!(homing, "force_a, force_t")("homing");

    regAction!(team, "action")("team");
    regAction!(kill_everyone_but_me, "")("kill_everyone_but_me");

    regAction!(nothing, "")("nothing");
}

void nothing(WeaponContext wx) {
}

void explosion(WeaponContext wx, float damage) {
    if (wx.fireInfo.info.pos.isNaN)
        return;
    if (wx.doubleDamage())
        damage *= 2.0f;
    wx.engine.explosionAt(wx.fireInfo.info.pos, damage, wx.createdBy);
}

void bitmap(WeaponContext wx, Surface bitmap, bool snow) {
    if (wx.fireInfo.info.pos.isNaN || bitmap is null)
        return;
    Lexel bits = Lexel.SolidSoft;
    //sorry, special cased
    if (snow) {
        bits |= cLandscapeSnowBit;
    }
    //centered at FireInfo.pos
    auto p = toVector2i(wx.fireInfo.info.pos);
    p -= bitmap.size / 2;
    wx.engine.insertIntoLandscape(p, bitmap, bits);
}

void beam(WeaponContext wx, bool usePos) {
    if (wx.fireInfo.info.pos.isNaN)
        return;
    auto worm = cast(WormSprite)wx.ownerSprite;
    if (!worm)
        return;
    Vector2f dest;
    if (usePos)
        dest = wx.fireInfo.info.pos;
    else
        dest = wx.fireInfo.info.pointto.currentPos;
    //WormSprite.beamTo does all the work, just wait for it to finish
    log("start beaming");
    worm.beamTo(dest);
    wx.putObj(new BeamHandler(wx.engine, worm));
}

void die(WeaponContext wx) {
    wx.ownerSprite.pleasedie();
}

void earthquake(ActionContext ctx, float strength, bool degrade,
    int waterRaise, bool bounce_objects, bool nuke_effect, Time duration)
{
    //water raise
    if (waterRaise > 0) {
        ctx.engine.raiseWater(waterRaise);
    }
    //earthquake
    ctx.engine.addEarthQuake(strength, duration, degrade, bounce_objects);
    //nuke effect
    if (nuke_effect) {
        ctx.engine.callbacks.nukeSplatEffect();
    }
}

void homing(WeaponContext wx, float forceA, float forceT) {
    auto pspr = cast(ProjectileSprite)wx.ownerSprite;
    if (!pspr)
        return;
    wx.putObj(new HomingAction(wx.engine, pspr, forceA, forceT));
}

void team(WeaponContext wx, char[] action) {
    auto w = wx.ownerSprite;
    if (!w)
        return;
    auto member = wx.engine.controller.memberFromGameObject(w, false);
    if (!member)
        return;
    switch (action) {
        case "skipturn":
            member.team.skipTurn();
            break;
        case "surrender":
            member.team.surrenderTeam();
            break;
        case "wormselect":
            new WormSelectHelper(wx.engine, member);
            break;
        default:
    }
}

void kill_everyone_but_me(WeaponContext wx) {
    auto w = wx.ownerSprite;
    if (!w)
        return;
    auto member = wx.engine.controller.memberFromGameObject(w, false);
    if (!member)
        return;
    foreach (Team t; wx.engine.controller.teams) {
        if (t is member.team)
            continue;
        foreach (TeamMember m; t.getMembers()) {
            //I thought this is funnier than killing "reliably"
            m.addHealth(-9999);
        }
    }
}


//------------------------------------------------------------------------

//waits until a worm has finished beaming (-> to abort when the worm was hit)
class BeamHandler : GameObject {
    WormSprite worm;
    this(GameEngine eng, WormSprite w) {
        super(eng, "beamhandler");
        active = true;
        worm = w;
    }
    this(ReflectCtor c) {
        super(c);
    }

    bool activity() {
        return active;
    }

    override void simulate(float deltaT) {
        super.simulate(deltaT);
        if (!worm.isBeaming) {
            //beaming is over, finish
            log("end beaming");
            worm = null;
            kill();
        }
    }

    override protected void updateActive() {
        //aborted
        if (!active && worm && worm.isBeaming())
            worm.abortBeaming();
    }
}

//------------------------------------------------------------------------

class HomingAction : GameObject {
    private {
        float forceA, forceT;
        ObjectForce objForce;
        ConstantForce homingForce;
        ProjectileSprite mParent;
    }

    this(GameEngine eng, ProjectileSprite parent, float forceA, float forceT) {
        super(eng, "homingaction");
        active = true;
        this.forceA = forceA;
        this.forceT = forceT;
        mParent = parent;
        assert(!!mParent);
        homingForce = new ConstantForce();
        objForce = new ObjectForce(homingForce, mParent.physics);
        engine.physicworld.add(objForce);
    }

    this (ReflectCtor c) {
        super(c);
    }

    bool activity() {
        return active;
    }

    override protected void updateActive() {
        if (!active)
            objForce.dead = true;
    }

    override void simulate(float deltaT) {
        super.simulate(deltaT);
        Vector2f totarget = mParent.target.currentPos
            - mParent.physics.pos;
        //accelerate/brake
        Vector2f cmpAccel = totarget.project_vector(
            mParent.physics.velocity);
        float al = cmpAccel.length;
        float ald = totarget.project_vector_len(
            mParent.physics.velocity);
        //steering
        Vector2f cmpTurn = totarget.project_vector(
            mParent.physics.velocity.orthogonal);
        float tl = cmpTurn.length;

        Vector2f fAccel, fTurn;
        //acceleration force
        if (al > float.epsilon)
            fAccel = cmpAccel/al*forceA;
        //turn force
        if (tl > float.epsilon) {
            fTurn = cmpTurn/tl*forceT;
            if (ald > float.epsilon && 2.0f*tl < al) {
                //when flying towards target and angle is small enough, limit
                //  turning force to fly a nice arc
                Vector2f v1 = cmpTurn/tl;
                Vector2f v2 = v1 - 2*v1.project_vector(totarget);
                //compute radius of circle trajectory
                float r =  (totarget.y*v2.x - totarget.x*v2.y)
                    /(v2.x*v1.y - v1.x*v2.y);
                //  a = v^2 / r ; F = m * a
                float fOpt_val = mParent.physics.posp.mass
                    * mParent.physics.velocity.quad_length / r;
                //turn slower if we will still hit dead-on
                if (fOpt_val < forceT)
                    fTurn = fOpt_val*cmpTurn/tl;
            }
        }
        homingForce.force = fAccel + fTurn;
    }
}

//------------------------------------------------------------------------

//Base class for instant area-of-effect actions
abstract class AoEActionClass : ActionClass {
    float radius = 10.0f;
    bool[char[]] hit;

    //xxx class
    this (ReflectCtor c) {
        super(c);
    }
    this (GfxSet gfx, ConfigNode node, char[] a_name) {
        super(a_name);
        radius = node.getValue!(float)("radius", radius);
        char[][] hitIds = node.getValue!(char[][])("hit", ["other"]);
        foreach (h; hitIds) {
            hit[h] = true;
        }
    }

    abstract protected void applyOn(WeaponContext wx, GObjectSprite sprite);

    void execute(ActionContext ctx) {
        auto wx = cast(WeaponContext)ctx;
        if (!wx || wx.fireInfo.info.pos.isNaN())
            return;

        bool useObj(PhysicObject obj) {
            bool ret;
            bool isWorm = cast(WormSprite)obj.backlink !is null;
            bool isSelf = obj.backlink is wx.ownerSprite;
            bool isObject = cast(GObjectSprite)obj.backlink !is null;
            if ("other" in hit)
                ret |= isWorm && !isSelf;
            if ("self" in hit)
                ret |= isWorm && isSelf;
            if ("objects" in hit)
                ret |= !isWorm && isObject;
            return ret;
        }

        bool doApply(PhysicObject obj) {
            assert(!!obj.backlink);
            applyOn(wx, cast(GObjectSprite)obj.backlink);
            return true;
        }

        wx.engine.physicworld.objectsAtPred(wx.fireInfo.info.pos, radius,
            &doApply, &useObj);
    }
}

//------------------------------------------------------------------------

//add an impulse to objects inside a circle
class ImpulseActionClass : AoEActionClass {
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
    this (GfxSet gfx, ConfigNode node, char[] a_name) {
        super(gfx, node, a_name);
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

    override protected void applyOn(WeaponContext wx, GObjectSprite sprite) {
        Vector2f imp;
        switch (directionMode) {
            case ImpulseActionClass.DirMode.fireInfo:
                //FireInfo.dir (away from firing worm)
                imp = strength * wx.fireInfo.info.dir;
                break;
            case ImpulseActionClass.DirMode.outside:
                //away from center of hitpoint
                auto d = (sprite.physics.pos - wx.fireInfo.info.pos).normal;
                if (!d.isNaN())
                    imp = strength * d;
                break;
            default:
                //use direction vector from config file
                imp = strength * direction;
        }
        sprite.physics.addImpulse(imp);
    }

    static this() {
        ActionClassFactory.register!(typeof(this))("impulse");
    }
}

//------------------------------------------------------------------------

//damages objects inside a circle, either absolute or relative
class AoEDamageActionClass : AoEActionClass {
    //how much damage the objects will receive
    //if <= 1.0f, damage is relative to current HP, otherwise absolute
    float damage = 0.5f;

    //xxx class
    this (ReflectCtor c) {
        super(c);
    }
    this (GfxSet gfx, ConfigNode node, char[] a_name) {
        super(gfx, node, a_name);
        damage = node.getValue!(float)("damage", damage);
    }

    override protected void applyOn(WeaponContext wx, GObjectSprite sprite) {
        float dmg;
        if (damage < 1.0f+float.epsilon) {
            //xxx not so sure about that; e.g. 0.5 -> 0.70
            float dmgPerc = wx.doubleDamage?sqrt(damage):damage;
            //relative damage
            dmg = sprite.physics.lifepower*dmgPerc;
            if (dmgPerc < 1.0f-float.epsilon) {
                //don't kill
                dmg = min(dmg, sprite.physics.lifepower - 1.0f);
            }
            if (dmg <= 0)
                return;
        } else {
            //absolute damage
            dmg = wx.doubleDamage?damage*2.0f:damage;
        }
        sprite.physics.applyDamage(dmg, DamageCause.special);
        //xxx stuck in the ground animation here
        sprite.physics.addImpulse(Vector2f(0, -1));
    }

    static this() {
        ActionClassFactory.register!(typeof(this))("aoedamage");
    }
}

class WormSelectHelper : GameObject {
    private {
        TeamMember mMember;
    }

    this(GameEngine eng, TeamMember member) {
        super(eng, "wormselecthelper");
        active = true;
        mMember = member;
        assert(!!mMember);
    }

    this (ReflectCtor c) {
        super(c);
    }

    bool activity() {
        return active;
    }

    override void simulate(float deltaT) {
        super.simulate(deltaT);
        //xxx: we just need the 1-frame delay for this because initialStep() is
        //     called from doFire, which will set mMember.mWormAction = true
        //     afterwards and would conflict with the code below
        mMember.team.allowSelect = true;
        mMember.control.resetActivity();
        kill();
    }
}
