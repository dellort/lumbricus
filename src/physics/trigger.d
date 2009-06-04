module physics.trigger;

import utils.reflection;
import utils.vector2;
import utils.list2;

import physics.base;
import physics.physobj;
import physics.plane;
import physics.zone;

//base class for trigger regions
//objects can be inside or outside and will trigger a callback when inside
//remember to set id for trigger handler
class PhysicTrigger : PhysicBase {
    ObjListNode!(typeof(this)) triggers_node;

    //trigger when object does _not_ collide
    bool inverse;

    void delegate(PhysicTrigger sender, PhysicObject other) onTrigger;

    this() {
    }
    this (ReflectCtor c) {
    }

    //return true when object is inside, false otherwise
    bool collide(PhysicObject obj) {
        bool coll = doCollide(obj);
        if ((coll ^ inverse) && onTrigger)
            onTrigger(this, obj);
        return coll;
    }

    abstract protected bool doCollide(PhysicObject obj);
}

//trigger that checks objects against a zone
//xxx are there really other types of triggers?
class ZoneTrigger : PhysicTrigger {
    PhysicZone zone;

    this(PhysicZone z) {
        zone = z;
    }

    this (ReflectCtor c) {
    }

    override bool doCollide(PhysicObject obj) {
        assert(!!zone);
        return zone.check(obj);
    }
}
