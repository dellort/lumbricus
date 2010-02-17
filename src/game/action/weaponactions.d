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
import game.weapon.girder;
import game.weapon.projectile;
import physics.world;
import utils.configfile;
import utils.time;
import utils.vector2;
import utils.randval;
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

    regAction!(nothing, "")("nothing");
    regAction!(putgirder, "")("putgirder");
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
}

void die(WeaponContext wx) {
    wx.ownerSprite.kill();
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

//depends on GirderControl
void putgirder(WeaponContext wx) {
    WeaponSelector sel = wx.shooter.selector;
    if (!sel)
        return; //???
    auto gsel = castStrict!(GirderControl)(sel);
    //(should never return false for failure if weapon code is correct)
    gsel.fireCheck(wx.fireInfo.info, true);
}

//------------------------------------------------------------------------

class HomingAction : GameObject {
    private {
        HomingForce homingForce;
        ProjectileSprite mParent;
    }

    this(GameEngine eng, ProjectileSprite parent, float forceA, float forceT) {
        super(eng, "homingaction");
        internal_active = true;
        mParent = parent;
        assert(!!mParent);
        homingForce = new HomingForce(mParent.physics, forceA, forceT);
        if (mParent.target.sprite) {
            homingForce.targetObj = mParent.target.sprite.physics;
        } else {
            homingForce.targetPos = mParent.target.pos;
        }
        engine.physicworld.add(homingForce);
    }

    bool activity() {
        return internal_active;
    }

    override protected void updateInternalActive() {
        if (!internal_active)
            homingForce.dead = true;
    }
}

//------------------------------------------------------------------------

//Base class for instant area-of-effect actions
abstract class AoEActionClass : ActionClass {
    float radius = 10.0f;
    bool[char[]] hit;

    this (GfxSet gfx, ConfigNode node, char[] a_name) {
        super(a_name);
        radius = node.getValue!(float)("radius", radius);
        char[][] hitIds = node.getValue!(char[][])("hit", ["other"]);
        foreach (h; hitIds) {
            hit[h] = true;
        }
    }

    abstract protected void applyOn(WeaponContext wx, Sprite sprite);

    void execute(ActionContext ctx) {
        auto wx = cast(WeaponContext)ctx;
        if (!wx || wx.fireInfo.info.pos.isNaN())
            return;

        bool useObj(PhysicObject obj) {
            bool ret;
            bool isWorm = cast(WormSprite)obj.backlink !is null;
            bool isSelf = obj.backlink is wx.ownerSprite;
            bool isObject = cast(Sprite)obj.backlink !is null;
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
            if (useObj(obj)) {
                applyOn(wx, cast(Sprite)obj.backlink);
            }
            return true;
        }

        wx.engine.physicworld.objectsAt(wx.fireInfo.info.pos, radius, &doApply);
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

    this (GfxSet gfx, ConfigNode node, char[] a_name) {
        super(gfx, node, a_name);
        strength = node.getValue!(float)("strength", strength);
        if (node["direction"] == "outside")
            directionMode = DirMode.outside;
        else if (node["direction"] != "") {
            directionMode = DirMode.vector;
            direction = node.getValue("direction", direction);
            if (direction.isNaN())
                throw new CustomException("Direction vector is illegal");
        }
    }

    override protected void applyOn(WeaponContext wx, Sprite sprite) {
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

    this (GfxSet gfx, ConfigNode node, char[] a_name) {
        super(gfx, node, a_name);
        damage = node.getValue!(float)("damage", damage);
    }

    override protected void applyOn(WeaponContext wx, Sprite sprite) {
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
        sprite.physics.applyDamage(dmg, DamageCause.special, wx.createdBy);
        //xxx stuck in the ground animation here
        sprite.physics.addImpulse(Vector2f(0, -1));
    }

    static this() {
        ActionClassFactory.register!(typeof(this))("aoedamage");
    }
}
