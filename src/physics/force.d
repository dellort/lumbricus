module physics.force;

import utils.vector2;
import utils.reflection;
import utils.list2;
import utils.misc;

import physics.base;
import physics.physobj;
import physics.zone;
import physics.misc;

import math = tango.math.Math;
import ieee = tango.math.IEEE;

//wind, gravitation, ...
//what about explosions?
class PhysicForce : PhysicBase {
    ObjListNode!(typeof(this)) forces_node;

    abstract void applyTo(PhysicObject o, float deltaT);

    static void registerstuff(ReflectCtor c) {
        c.types().registerClasses!(ConstantForce, ConstantAccel, WindyForce,
            ExplosiveForce, GravityCenter, StokesDragObject, StokesDragFixed,
            ObjectForce, ForceZone);
    }
}

class ConstantForce : PhysicForce {
    //directed force, in Wormtons
    //(1 Wormton = 10 Milli-Worms * 1 Pixel / Seconds^2 [F=ma])
    Vector2f force;

    this() {
    }
    this (ReflectCtor c) {
    }

    void applyTo(PhysicObject o, float deltaT) {
        o.addForce(force, true);
    }
}

//like ConstantForce, but independent of object mass
class ConstantAccel: PhysicForce {
    Vector2f accel;

    this() {
    }
    this (ReflectCtor c) {
    }

    void applyTo(PhysicObject o, float deltaT) {
        o.addForce(accel * o.posp.mass, true);
    }
}

class WindyForce : PhysicForce {
    Vector2f windSpeed;
    private const cStokesConstant = 6*math.PI;

    this() {
    }
    this (ReflectCtor c) {
    }

    void applyTo(PhysicObject o, float deltaT) {
        //xxx physical crap, but the way Worms does it (using windSpeed as
        //    acceleration)
        o.addForce(windSpeed * o.posp.mass * o.posp.windInfluence, true);
        if (o.posp.airResistance > 0)
            //this is a more correct simulation: Stokes's law
            o.addForce(cStokesConstant*o.posp.radius*o.posp.airResistance
                *(windSpeed - o.velocity));
    }
}

//feature request to d0c: make it last more than one frame :)
//(over several frames should it should be more stable )
class ExplosiveForce : PhysicForce {
    float damage;
    Vector2f pos;
    Object cause;

    void delegate(Object cause, Object victim, float damage) onReportApply;

    //the force is only applied if true is returned
    bool delegate(ExplosiveForce sender, PhysicObject obj) onCheckApply;

    this (ReflectCtor c) {
    }

    this() {
        //one time
        lifeTime = 0;
    }

    private const cDamageToImpulse = 140.0f;
    private const cDamageToRadius = 2.0f;

    public float radius() {
        return damage*cDamageToRadius;
    }

    private float cDistDelta = 0.01f;
    void applyTo(PhysicObject o, float deltaT) {
        assert(damage != 0f && !ieee.isNaN(damage));
        float impulse = damage*cDamageToImpulse;
        Vector2f v = (pos-o.pos);
        float dist = v.length;
        if (dist > cDistDelta) {
            float r = max(radius-dist,0f)/radius;
            if (r < float.epsilon)
                return;
            if (onCheckApply && !onCheckApply(this, o))
                return;
            float before = o.lifepower;
            o.applyDamage(r*damage, DamageCause.explosion);
            float diff = before - o.lifepower;
            //corner cases; i.e. invincible worm
            if (diff != diff || diff == typeof(diff).infinity)
                diff = 0;
            if (diff != 0 && onReportApply) {
                onReportApply(cause, o.backlink, diff);
            }
            o.addImpulse(-v.normal()*impulse*r*o.posp.explosionInfluence);
        } else {
            //unglue objects at center of explosion
            o.doUnglue();
        }
    }
}

class GravityCenter : PhysicForce {
    float accel, radius;
    Vector2f pos;

    this() {
    }
    this (ReflectCtor c) {
    }

    private float cDistDelta = 0.01f;
    void applyTo(PhysicObject o, float deltaT) {
        Vector2f v = (pos-o.pos);
        float dist = v.length;
        if (dist > cDistDelta) {
            float r = (max(radius-dist,0f)/radius);
            if (r > float.epsilon)
                o.addForce((v.normal()*accel*r)*o.posp.mass);
        }
    }
}

//Stokes's drag
//special case, because it reads the object's mediumViscosity value
//(StokesDragFixed uses a force-specific fixed viscosity)
class StokesDragObject : PhysicForce {
    //constant from Stokes's drag
    private const cStokesConstant = -6*math.PI;

    this() {
    }
    this (ReflectCtor c) {
    }

    void applyTo(PhysicObject o, float deltaT) {
        if (o.posp.mediumViscosity != 0.0f) {
            //F = -6*PI*r*eta*v
            o.addForce(cStokesConstant*o.posp.radius*o.posp.mediumViscosity
                *o.velocity*o.posp.stokesModifier);
        }
    }
}

//Stokes's drag, applies a fixed viscosity to all objects
//best used together with ForceZone
class StokesDragFixed : PhysicForce {
    //constant from Stokes's drag
    private const cStokesConstant = -6*math.PI;
    //medium viscosity
    float viscosity = 0.0f;

    this(float visc = 0.0f) {
        viscosity = visc;
    }

    this (ReflectCtor c) {
    }

    void applyTo(PhysicObject o, float deltaT) {
        if (viscosity != 0.0f) {
            //F = -6*PI*r*eta*v
            o.addForce(cStokesConstant*o.posp.radius*viscosity*o.velocity
                *o.posp.stokesModifier);
        }
    }
}

//proxy class to apply a force to one specific object
class ObjectForce : PhysicForce {
    PhysicObject target;
    PhysicForce force;

    this (ReflectCtor c) {
    }

    this(PhysicForce f, PhysicObject t) {
        force = f;
        target = t;
    }

    void applyTo(PhysicObject o, float deltaT) {
        if (o is target) {
            force.applyTo(target, deltaT);
        }
    }
}

//proxy class to apply a force only to objects inside a zone
class ForceZone : PhysicForce {
    PhysicForce force;
    PhysicZone zone;
    bool invert;

    this (ReflectCtor c) {
    }

    this(PhysicForce f, PhysicZone z, bool inv = false) {
        force = f;
        zone = z;
        invert = inv;
    }

    void applyTo(PhysicObject o, float deltaT) {
        if (zone.check(o) ^ invert) {
            force.applyTo(o, deltaT);
        }
    }
}
