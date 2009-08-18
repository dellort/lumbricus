module game.weapon.ray;

import common.scene;
import game.game;
import game.gobject;
import physics.world;
import game.action.base;
import game.sprite;
import game.weapon.weapon;
import game.gamepublic;
import game.weapon.actionweapon;
import tango.math.Math: PI;
import utils.vector2;
import utils.configfile;
import utils.color;
import utils.log;
import utils.random;
import utils.time;
import utils.reflection;

class RayWeapon: ActionWeapon {
    float spread = 0;      //random spread (degrees)
    Time lineTime;         //time for which a laser-like line is displayed
    Color[2] lineColors;   //[cold, hot] colors (interpolated during lineTime)

    this(GameEngine aengine, ConfigNode node) {
        super(aengine, node);
        //always directed with fixed strength
        fireMode.variableThrowStrength = false;
        spread = node.getFloatValue("spread", spread);
        lineTime = node.getValue("linetime", lineTime);
        lineColors[0] = node.getValue!(Color)("color1");
        lineColors[1] = node.getValue!(Color)("color2");
    }

    //xxx class
    this (ReflectCtor c) {
        super(c);
    }

    //using SpecialShooter here leads to dmd lockup (at least with dsss)
    RayShooter createShooter(GObjectSprite owner) {
        return new RayShooter(this, owner, engine);
    }

    static this() {
        WeaponClassFactory.register!(typeof(this))("ray");
    }
}

class RayShooter: ActionShooter {
    RayWeapon base;

    this(RayWeapon base, GObjectSprite a_owner, GameEngine engine) {
        super(base, a_owner, engine);
        this.base = base;
    }

    this (ReflectCtor c) {
        super(c);
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
            new RenderLaser(engine, [npos, hitPoint], base.lineTime,
                [base.lineColors[0], base.lineColors[1], base.lineColors[0]]);
        }
    }
}

//non-deterministic, transient, self-removing shoot effect
//xxx: this used to be derived from GameObject
//     now this functionality got lost: bool activity() { return active; }
//     if it's needed again, let RayShooter wait until end-time
class RenderLaser : SceneObject {
    private {
        GameEngineCallback base;
        Vector2i[2] mP;
        Time mStart, mEnd;
        Color[] mColors;
    }

    this(GameEngine aengine, Vector2f[2] p, Time duration, Color[] colors) {
        base = aengine.callbacks;
        zorder = GameZOrder.Effects;
        base.scene.add(this);
        mP[0] = toVector2i(p[0]);
        mP[1] = toVector2i(p[1]);
        mStart = base.interpolateTime.current;
        mEnd = mStart + duration;
        mColors = colors;
    }

    this (ReflectCtor c) {
        super(c);
    }

    override void draw(Canvas c) {
        auto cur = base.interpolateTime.current;
        assert(cur >= mStart);
        if (cur >= mEnd) {
            removeThis();
            return;
        }
        float pos = 1.0*(cur - mStart).msecs / (mEnd - mStart).msecs;
        // [0.0, 1.0] onto range [colors[0], ..., colors[$-1]]
        pos *= mColors.length;
        int segi = cast(int)(pos);
        float segmod = pos - segi;
        //assert(segi >= 0 && segi < mColors.length-1);
        if (!(segi >= 0 && segi < mColors.length-1)) {
            removeThis();
            return;
        }
        //linear interpolation between these
        auto col = mColors[segi] + (mColors[segi+1]-mColors[segi])*segmod;
        c.drawLine(mP[0], mP[1], col);
    }
}
