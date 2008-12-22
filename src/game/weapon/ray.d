module game.weapon.ray;

import game.game;
import game.gobject;
import physics.world;
import game.action;
import game.sprite;
import game.weapon.weapon;
import game.weapon.projectile;
import game.gamepublic;
import game.weapon.actionweapon;
import std.math: PI;
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
        lineTime = timeSecs(node.getFloatValue("linetime", lineTime.secs));
        lineColors[0].parse(node["color1"]);
        lineColors[1].parse(node["color2"]);
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

    override void fireRound(Action sender) {
        //shoot the ray with random spread and adjust fireinfo
        float a = base.spread*engine.rnd.nextDouble() - base.spread/2.0f;
        float dist = owner.physics.posp.radius + 2;
        Vector2f ndir = fireInfo.dir.rotated(a*PI/180.0f);
        Vector2f npos = owner.physics.pos + ndir*dist;
        PhysicObject o;
        Vector2f hitPoint, normal;
        bool hit = engine.physicworld.shootRay(npos, ndir,
            /+engine.level.size.length+/ 1000, hitPoint, o, normal);
        if (hit) {
            fireInfo.pos = hitPoint;
        } else {
            fireInfo.pos = Vector2f.nan;
        }
        //away from shooting object, so don't use radius
        fireInfo.shootbyRadius = 0;
        fireInfo.surfNormal = normal;
        if (base.lineTime > timeSecs(0)) {
            new RenderLaser(engine, [npos, hitPoint], base.lineTime,
                [base.lineColors[0], base.lineColors[1], base.lineColors[0]]);
        }
    }

    override void roundFired(Action sender) {
        //no reduceAmmo here
    }

    override protected void doFire(FireInfo info) {
        super.doFire(info);
        reduceAmmo();
    }
}

class RenderLaser : GameObject {
    private {
        Time mStart, mEnd;
        Color[] mColors;
        LineGraphic mLine;
    }

    this(GameEngine aengine, Vector2f[2] p, Time duration, Color[] colors) {
        super(aengine, true);
        mLine = aengine.graphics.createLine();
        mLine.setPos(toVector2i(p[0]), toVector2i(p[1]));
        mStart = engine.gameTime.current;
        mEnd = mStart + duration;
        mColors = colors.dup;
    }

    this (ReflectCtor c) {
        super(c);
    }

    override void simulate(float deltaT) {
        auto cur = engine.gameTime.current;
        assert(cur >= mStart);
        if (cur >= mEnd) {
            active = false;
            return;
        }
        float pos = 1.0*(cur - mStart).msecs / (mEnd - mStart).msecs;
        // [0.0, 1.0] onto range [colors[0], ..., colors[$-1]]
        pos *= mColors.length;
        int segi = cast(int)(pos);
        float segmod = pos - segi;
        //assert(segi >= 0 && segi < mColors.length-1);
        if (!(segi >= 0 && segi < mColors.length-1)) {
            active = false;
            return;
        }
        //linear interpolation between these
        auto c = mColors[segi] + (mColors[segi+1]-mColors[segi])*segmod;
        mLine.setColor(c);
    }

    override protected void updateActive() {
        if (!active && mLine) {
            mLine.remove();
            mLine = null;
        }
    }

    bool activity() {
        return active;
    }
}
