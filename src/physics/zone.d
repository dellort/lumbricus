module physics.zone;

///A "zone" is a region in space, which objects can occupy (or not)
///Base functionality is to check if an object is inside

import framework.drawing;

import utils.vector2;
import utils.rect2;
import utils.list2;
import utils.misc;

import physics.base;
import physics.physobj;
import physics.plane;

//utility class, no extension of PhysicBase
class PhysicZone {
    this() {
    }

    bool check(PhysicObject obj) {
        //currently only circular objects, maybe more will follow (yeah, sure xD)
        return checkCircle(obj.pos, obj.posp.radius);
    }

    abstract bool checkCircle(Vector2f pos, float radius);

    void debug_draw(Canvas c) {
    }
}

//plane separating world, objects can be on one side (in) or the other (out)
class PhysicZonePlane : PhysicZone {
    Plane plane;

    this(Vector2f from, Vector2f to) {
        plane.define(from, to);
    }

    this() {
    }

    override bool checkCircle(Vector2f pos, float radius) {
        //out values of plane.collide are not used
        Vector2f n;
        float pd;
        return plane.collide(pos, radius, n, pd);
    }

    override void debug_draw(Canvas c) {
        super.debug_draw(c);
        //clip the plane with visible rect to get a line
        Vector2f[2] outp;
        if (plane.intersectRect(toRect2f(c.visibleArea), outp)) {
            c.drawLine(toVector2i(outp[0]), toVector2i(outp[1]), Color(0,1,0));
        }
    }
}

//circular trigger area with position and radius
//(you could call it proximity sensor)
class PhysicZoneCircle : PhysicZone {
    float radius;
    Vector2f pos;
    PhysicObject attach;

    this(Vector2f pos, float rad) {
        radius = rad;
        this.pos = pos;
    }

    this(PhysicObject attach, float rad) {
        argcheck(attach);
        radius = rad;
        this.attach = attach;
    }

    override bool checkCircle(Vector2f opos, float orad) {
        if (attach) {
            pos = attach.pos;
        }
        return (opos-pos).quad_length < (radius*radius + orad*orad);
    }

    override void debug_draw(Canvas c) {
        super.debug_draw(c);
        c.drawCircle(toVector2i(pos), cast(int)radius, Color(0,1,0));
    }
}

//rectangular zone
//signals collision if the circle touches the rect insides
class PhysicZoneRect : PhysicZone {
    Rect2f rect;

    this(Rect2f r) {
        rect = r;
    }

    override bool checkCircle(Vector2f pos, float radius) {
        //slightly incorrect results for corner cases
        return rect.collideCircleApprox(pos, radius);
    }

    override void debug_draw(Canvas c) {
        super.debug_draw(c);
        c.drawRect(toRect2i(rect), Color(0,1,0));
    }
}

class PhysicZoneXRange : PhysicZone {
    float xMin, xMax;
    bool whenTouched;  //true  -> triggers if object touches the range
                       //false -> triggers if object is fully inside

    this(float a_min, float a_max) {
        xMin = a_min;
        xMax = a_max;
    }

    override bool checkCircle(Vector2f pos, float radius) {
        if (whenTouched)
            return pos.x + radius > xMin && pos.x - radius < xMax;
        else
            return pos.x - radius > xMin && pos.x + radius < xMax;
    }
}
