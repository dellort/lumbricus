module physics.geometry;

import utils.mylist;
import utils.vector2;

import physics.base;
import physics.plane;

//a geometric object which represent (almost) static parts of the map
//i.e. the deathzone (where worms go if they fly too far), the water, and solid
// border of the level (i.e. upper border in caves)
//also used for the bitmap part of the level
class PhysicGeometry : PhysicBase {
    package mixin ListNodeMixin geometries_node;

    //generation counter, increased on every change
    int generationNo = 0;
    package int lastKnownGen = -1;

    override protected void addedToWorld() {
        //register fixed collision id "ground" on first call
        collision = world.findCollisionID("ground", true);
    }


    //if outside geometry, return false and don't change pos
    //if inside or touching, return true and set pos to a corrected pos
    //(which is the old pos, moved along the normal at that point in the object)
    abstract bool collide(inout Vector2f pos, float radius);

    override /+package+/ void doRemove() {
        super.doRemove();
        world.mGeometryObjects.remove(this);
    }
}

//a plane which divides space into two regions (inside and outside plane)
class PlaneGeometry : PhysicGeometry {
    Plane plane;

    this(Vector2f from, Vector2f to) {
        plane.define(from, to);
    }

    this() {
    }

    bool collide(inout Vector2f pos, float radius) {
        return plane.collide(pos, radius);
    }
}
