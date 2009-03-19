module physics.geometry;

import utils.reflection;
import utils.list2;
import utils.vector2;

import physics.base;
import physics.physobj;
import physics.plane;
import physics.misc;
import utils.misc;

import tango.math.Math : abs;

struct GeomContact {
    //Vector2f contactPoint;
    Vector2f normal;    //contact normal, directed out of geometry
    float depth;  //object depth depth (along normal)
    float friction = 1.0f; //multiplier for object fritction
    float restitutionOverride = float.nan; //nan -> no override
    bool noCall = false;

    //void calcPoint(Vector2f pos, float radius) {
    //    contactPoint = pos - normal * (radius - depth);
    //}

    //merge another ContactData into this one
    //xxx this may be total crap, we have no testcase
    void merge(GeomContact other) {
        if (depth == float.infinity)
            return;
        if (other.depth == float.infinity) {
            depth = float.infinity;
            return;
        }
        Vector2f tmp = (normal*depth) + (other.normal*other.depth);
        depth = tmp.length;
        if (depth < float.epsilon) {
            //depth can become 0, default to a save value
            normal = Vector2f(0, -1);
        } else {
            normal = tmp.normal;
        }
        assert (depth == depth);
        assert (!normal.isNaN);
        //contactPoint = (contactPoint + other.contactPoint)/2;
        friction = friction * other.friction;
        //result can be nan (meaning don't override)
        restitutionOverride = restitutionOverride * other.restitutionOverride;
        noCall = noCall && other.noCall;
    }
}

//a geometric object which represent (almost) static parts of the map
//i.e. the deathzone (where worms go if they fly too far), the water, and solid
// border of the level (i.e. upper border in caves)
//also used for the bitmap part of the level
class PhysicGeometry : PhysicBase {
    package ListNode geometries_node;

    //generation counter, increased on every change
    int generationNo = 0;
    package int lastKnownGen = -1;

    this() {
    }
    this (ReflectCtor c) {
        c.types().registerClass!(PlaneGeometry);
        c.types().registerClass!(WaterSurfaceGeometry);
    }

    override protected void addedToWorld() {
        //register fixed collision id "ground" on first call
        collision = world.collide.findCollisionID("ground");
    }


    bool collide(PhysicObject obj, bool extendRadius, out GeomContact contact) {
        return collide(obj.pos, obj.posp.radius+(extendRadius?4:0), contact);
    }

    //if outside geometry, return false and don't change pos
    //if inside or touching, return true and set pos to a corrected pos
    //(which is the old pos, moved along the normal at that point in the object)
    abstract bool collide(Vector2f pos, float radius, out GeomContact contact);
}

//a plane which divides space into two regions (inside and outside plane)
class PlaneGeometry : PhysicGeometry {
    Plane plane;

    this(Vector2f from, Vector2f to) {
        plane.define(from, to);
    }

    this() {
    }

    this (ReflectCtor c) {
    }

    bool collide(Vector2f pos, float radius, out GeomContact contact) {
        bool ret = plane.collide(pos, radius, contact.normal,
            contact.depth);
        //contact.calcPoint(pos, radius);
        return ret;
    }
}

//special geometry to make objects bounce like stones on a water surface
//current implementation only works for horizontal surfaces
class WaterSurfaceGeometry : PlaneGeometry {
    this() {
    }

    this (ReflectCtor c) {
    }

    //xxx depends on implementation in physics.world: checking an object
    //    tests velocity, just checking a position/radius (like raycasting)
    //    never collides

    override bool collide(PhysicObject obj, bool extendRadius,
        out GeomContact contact)
    {
        //xxx: only works for horizontal surface
        float a = abs(obj.velocity.x) / obj.velocity.y;
        //~20°
        if (a > 2.7f) {
            bool ret = plane.collide(obj.pos, obj.posp.radius, contact.normal,
                contact.depth);
            if (ret) {
                //no y speed reduction, or we get strange "sliding" effects
                contact.restitutionOverride = 1.0f;
                //don't blow up projectiles
                contact.noCall = true;
                //xxx lol hack etc.: slow object down a little
                obj.velocity_int.x *= 0.85f;
            }
            return ret;
        }
        return false;
    }

    bool collide(Vector2f pos, float radius, out GeomContact contact) {
        return false;
    }
}
