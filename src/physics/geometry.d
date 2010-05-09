module physics.geometry;

import utils.list2;
import utils.vector2;

import physics.base;
import physics.contact;
import physics.physobj;
import physics.plane;
import physics.misc;
import utils.misc;

import tango.math.Math : abs;

//a geometric object which represent (almost) static parts of the map
//i.e. the deathzone (where worms go if they fly too far), the water, and solid
// border of the level (i.e. upper border in caves)
//also used for the bitmap part of the level
class PhysicGeometry : PhysicBase {
    ObjListNode!(typeof(this)) geometries_node;

    //generation counter, increased on every change
    int generationNo = 0;
    package int lastKnownGen = -1;

    this() {
    }

    override protected void addedToWorld() {
        //register fixed collision id "ground" on first call
        collision = world.collide.findCollisionID("ground");
    }


    bool collide(PhysicObject obj, out Contact contact) {
        if (!collide(obj.pos, obj.posp.radius, contact))
            return false;
        //same as in Contact.fromObj
        contact.obj[0] = obj;
        contact.obj[1] = null;
        contact.restitution = contact.obj[0].posp.elasticity;
        contact.source = ContactSource.geometry;
        return true;
    }

    //if outside geometry, return false and don't change pos
    //if inside or touching, return true and set pos to a corrected pos
    //(which is the old pos, moved along the normal at that point in the object)
    abstract bool collide(Vector2f pos, float radius, out Contact contact);
}

//a plane which divides space into two regions (inside and outside plane)
class PlaneGeometry : PhysicGeometry {
    Plane plane;

    this(Vector2f from, Vector2f to) {
        plane.define(from, to);
    }

    this() {
    }

    bool collide(Vector2f pos, float radius, out Contact contact) {
        bool ret = plane.collide(pos, radius, contact.normal,
            contact.depth);
        //contact.calcPoint(pos, radius);
        return ret;
    }
}

//yay for code duplication
//don't fix this, rather make physic objects, geometry, triggers/zones, forces,
//  and everything else so that they can use the same shape code
class LineGeometry : PhysicGeometry {
    Line line;

    this(Vector2f from, Vector2f to, float width) {
        line.defineStartEnd(from, to, width);
    }

    this() {
    }

    bool collide(Vector2f pos, float radius, out Contact contact) {
        bool ret = line.collide(pos, radius, contact.normal,
            contact.depth);
        //contact.calcPoint(pos, radius);
        return ret;
    }
}
