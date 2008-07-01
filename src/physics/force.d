module physics.force;

import utils.vector2;
import utils.mylist;
import utils.misc;

import physics.base;
import physics.physobj;

//wind, gravitation, ...
//what about explosions?
class PhysicForce : PhysicBase {
    package mixin ListNodeMixin forces_node;

    abstract void applyTo(PhysicObject o, float deltaT);
}

class ConstantForce : PhysicForce {
    //directed force, in Wormtons
    //(1 Wormton = 10 Milli-Worms * 1 Pixel / Seconds^2 [F=ma])
    Vector2f force;

    void applyTo(PhysicObject o, float deltaT) {
        o.addForce(force, true);
    }
}

//like ConstantForce, but independent of object mass
class ConstantAccel: PhysicForce {
    Vector2f accel;

    void applyTo(PhysicObject o, float deltaT) {
        o.addForce(accel * o.posp.mass, true);
    }
}

class WindyForce : PhysicForce {
    Vector2f windSpeed;
    private const cStokesConstant = 6*PI;

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
        float impulse = damage*cDamageToImpulse;
        Vector2f v = (pos-o.pos);
        float dist = v.length;
        if (dist > cDistDelta) {
            float r = max(radius-dist,0f)/radius;
            if (r < float.epsilon)
                return;
            float before = o.lifepower;
            o.applyDamage(r*damage);
            float diff = before - o.lifepower;
            //corner cases; i.e. invincible worm
            if (diff != diff || diff == typeof(diff).infinity)
                diff = 0;
            if (diff != 0 && onReportApply) {
                onReportApply(cause, o.backlink, diff);
            }
            o.addImpulse(-v.normal()*impulse*r*o.posp.explosionInfluence);
        }
    }
}

class GravityCenter : PhysicForce {
    float accel, radius;
    Vector2f pos;

    private float cDistDelta = 0.01f;
    void applyTo(PhysicObject o, float deltaT) {
        Vector2f v = (pos-o.pos);
        float dist = v.length;
        if (dist > cDistDelta) {
            float r = (max(radius-dist,0f)/radius);
            o.addForce((v.normal()*accel*r)*o.posp.mass);
        }
    }
}

//Stokes's drag
//special case, because it reads the object's mediumViscosity value
//xxx would be better to apply this in a fixed region and store the viscosity
//    here (e.g. PhysicForceZone)
class StokesDrag : PhysicForce {
    //constant from Stokes's drag
    private const cStokesConstant = -6*PI;

    void applyTo(PhysicObject o, float deltaT) {
        if (o.posp.mediumViscosity != 0.0f) {
            //F = -6*PI*r*eta*v
            o.addForce(cStokesConstant*o.posp.radius*o.posp.mediumViscosity
                *o.velocity);
        }
    }
}

//proxy class to apply a force to one specific object
class ObjectForce : PhysicForce {
    PhysicObject target;
    PhysicForce force;

    void applyTo(PhysicObject o, float deltaT) {
        if (o == target) {
            force.applyTo(target, deltaT);
        }
    }
}
