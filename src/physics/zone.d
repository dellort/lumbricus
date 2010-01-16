module physics.zone;

///A "zone" is a region in space, which objects can occupy (or not)
///Base functionality is to check if an object is inside

import utils.vector2;
import utils.rect2;
import utils.list2;

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
}

//circular trigger area with position and radius
//(you could call it proximity sensor)
class PhysicZoneCircle : PhysicZone {
    float radius;
    Vector2f pos;

    this(Vector2f pos, float rad) {
        radius = rad;
        this.pos = pos;
    }

    override bool checkCircle(Vector2f opos, float orad) {
        return (opos-pos).quad_length < (radius*radius + orad*orad);
    }
}

//rectangular zone
class PhysicZoneRect : PhysicZone {
    Rect2f rect;

    this(Rect2f r) {
        rect = r;
    }

    override bool checkCircle(Vector2f pos, float radius) {
        //xxx checks if center of object (i.e. half object) is inside
        return rect.isInside(pos);
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
