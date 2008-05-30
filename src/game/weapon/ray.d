module game.weapon.ray;

import game.game;
import game.gobject;
import physics.world;
import game.sprite;
import game.weapon.weapon;
import game.gamepublic;
import std.math: PI;
import utils.vector2;
import utils.configfile;
import utils.color;
import utils.log;
import utils.random;
import utils.time;

class RayWeapon: WeaponClass {
    float damage = 5.0f;   //damage of one hit
    int count = 1;         //number of bullets
    Time delay;            //delay between bullets
    float spread = 0;      //random spread (degrees)
    Time lineTime;         //time for which a laser-like line is displayed
    Color[2] lineColors;   //[cold, hot] colors (interpolated during lineTime)

    this(GameEngine aengine, ConfigNode node) {
        super(aengine, node);
        //always directed with fixed strength
        fireMode.canThrow = true;
        fireMode.variableThrowStrength = false;
        damage = node.getFloatValue("damage", damage);
        count = node.getIntValue("count", count);
        delay = timeSecs(node.getFloatValue("delay", delay.secs));
        spread = node.getFloatValue("spread", spread);
        lineTime = timeSecs(node.getFloatValue("linetime", lineTime.secs));
        lineColors[0].parse(node["color1"]);
        lineColors[1].parse(node["color2"]);
    }

    //using SpecialShooter here leads to dmd lockup (at least with dsss)
    Shooter createShooter(GObjectSprite owner) {
        return new RayShooter(this, owner, engine);
    }

    static this() {
        WeaponClassFactory.register!(RayWeapon)("ray_mc");
    }
}

private class RayShooter: Shooter {
    RayWeapon base;
    FireInfo fireInfo;
    int remain;      //number of bullets still to fire
    Time lastShot;

    this(RayWeapon base, GObjectSprite a_owner, GameEngine engine) {
        super(base, a_owner, engine);
        this.base = base;
    }

    bool activity() {
        return active;
    }

    void fire(FireInfo info) {
        if (active) {
            //try to interrupt
            interruptFiring();
            //if still active: no.
            if (active)
                return;
        }

        fireInfo = info;
        remain = base.count;
        active = true;
    }

    //fires one shot with random spread
    private void fireRound() {
        float a = base.spread*engine.rnd.nextDouble() - base.spread/2.0f;
        float dist = owner.physics.posp.radius + 2;
        Vector2f ndir = fireInfo.dir.rotated(a*PI/180.0f);
        Vector2f npos = owner.physics.pos+ndir*dist;
        PhysicObject o;
        Vector2f hitPoint;
        bool hit = engine.physicworld.shootRay(npos, ndir,
            /+engine.level.size.length+/ 1000, hitPoint, o);
        if (hit) {
            engine.explosionAt(hitPoint, base.damage, owner);
        }
        if (base.lineTime > timeSecs(0)) {
            new RenderLaser(engine, [npos, hitPoint], base.lineTime,
                [base.lineColors[0], base.lineColors[1], base.lineColors[0]]);
        }
    }

    override void simulate(float deltaT) {
        //shoot bullets
        while (remain > 0
            && engine.gameTime.current - lastShot >= base.delay)
        {
            remain--;
            lastShot = engine.gameTime.current;

            fireRound();
        }
        if (remain == 0) {
            active = false;
        }
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
