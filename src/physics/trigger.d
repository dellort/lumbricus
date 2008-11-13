module physics.trigger;

import utils.vector2;
import utils.mylist;

import physics.base;
import physics.physobj;
import physics.plane;
import physics.zone;

//base class for trigger regions
//objects can be inside or outside and will trigger a callback when inside
//remember to set id for trigger handler
class PhysicTrigger : PhysicBase {
    package mixin ListNodeMixin triggers_node;

    //trigger when object does _not_ collide
    bool inverse;

    void delegate(PhysicTrigger sender, PhysicObject other) onTrigger;

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

    override bool doCollide(PhysicObject obj) {
        return zone.check(obj);
    }
}
