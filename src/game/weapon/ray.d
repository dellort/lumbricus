module game.weapon.ray;

import game.game;
import game.gfxset;
import game.gobject;
import physics.world;
import game.action.base;
import game.sprite;
import game.weapon.weapon;
import game.weapon.helpers;
import game.weapon.actionweapon;
import tango.math.Math: PI;
import utils.vector2;
import utils.configfile;
import utils.color;
import utils.log;
import utils.random;
import utils.time;

class RayWeapon: ActionWeapon {
    float spread = 0;      //random spread (degrees)
    Time lineTime;         //time for which a laser-like line is displayed
    Color[2] lineColors;   //[cold, hot] colors (interpolated during lineTime)

    this(char[] prefix, GfxSet gfx, ConfigNode node) {
        super(prefix, gfx, node);
        //always directed with fixed strength
        fireMode.variableThrowStrength = false;
        spread = node.getFloatValue("spread", spread);
        lineTime = node.getValue("linetime", lineTime);
        lineColors[0] = node.getValue!(Color)("color1");
        lineColors[1] = node.getValue!(Color)("color2");
    }

    //using SpecialShooter here leads to dmd lockup (at least with dsss)
    RayShooter createShooter(Sprite owner, GameEngine engine) {
        return new RayShooter(this, owner, engine);
    }

    static this() {
        WeaponClassFactory.register!(typeof(this))("ray");
    }
}

class RayShooter: ActionShooter {
    RayWeapon base;

    this(RayWeapon base, Sprite a_owner, GameEngine engine) {
        super(base, a_owner, engine);
        this.base = base;
    }

    override void fireRound() {
        //shoot the ray with random spread and adjust fireinfo
        float a = base.spread*engine.rnd.nextDouble() - base.spread/2.0f;
        float dist = owner.physics.posp.radius + 2;
        Vector2f ndir = fireInfo.info.dir.rotated(a*PI/180.0f);
        Vector2f npos = owner.physics.pos + ndir*dist;
        PhysicObject o;
        Vector2f hitPoint, normal;
        bool hit = engine.physicworld.shootRay(npos, ndir,
            /+engine.level.size.length+/ 1000, hitPoint, o, normal);
        if (hit) {
            fireInfo.info.pos = hitPoint;
        } else {
            fireInfo.info.pos = Vector2f.nan;
        }
        //away from shooting object, so don't use radius
        fireInfo.info.shootbyRadius = 0;
        fireInfo.info.surfNormal = normal;
        if (base.lineTime > Time.Null) {
            //xxx: evil memory allocation (array literals)
            new RenderLaser(engine, npos, hitPoint, base.lineTime,
                [base.lineColors[0], base.lineColors[1], base.lineColors[0]]);
        }
    }
}
