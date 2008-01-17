module physics.trigger;

import utils.vector2;
import utils.mylist;

import physics.base;
import physics.physobj;
import physics.plane;

//base class for trigger regions
//objects can be inside or outside and will trigger a callback when inside
//remember to set id for trigger handler
class PhysicTrigger : PhysicBase {
    package mixin ListNodeMixin triggers_node;

    void delegate(PhysicTrigger sender, PhysicObject other) onTrigger;

    //return true when object is inside, false otherwise
    bool collide(PhysicObject obj) {
        bool coll = doCollide(obj.pos, obj.posp.radius);
        if (coll && onTrigger)
            onTrigger(this, obj);
        return coll;
    }

    abstract protected bool doCollide(Vector2f pos, float radius);

    override /+package+/ void doRemove() {
        super.doRemove();
        world.mTriggers.remove(this);
    }
}

//plane separating world, objects can be on one side (in) or the other (out)
class PlaneTrigger : PhysicTrigger {
    Plane plane;

    this(Vector2f from, Vector2f to) {
        plane.define(from, to);
    }

    this() {
    }

    override bool doCollide(Vector2f pos, float radius) {
        return plane.collide(pos, radius);
    }
}

//circular trigger area with position and radius
//(you could call it proximity sensor)
class CircularTrigger : PhysicTrigger {
    float radius;
    Vector2f pos;

    this(Vector2f pos, float rad) {
        radius = rad;
        this.pos = pos;
    }

    override bool doCollide(Vector2f opos, float orad) {
        return (opos-pos).quad_length < (radius*radius + orad*orad);
    }

}
