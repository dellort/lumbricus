module physics.force;

import utils.vector2;
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
}

class ConstantForce : PhysicForce {
    //directed force, in Wormtons
    //(1 Wormton = 10 Milli-Worms * 1 Pixel / Seconds^2 [F=ma])
    Vector2f force;

    this() {
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

    void applyTo(PhysicObject o, float deltaT) {
        o.addForce(accel * o.posp.mass, true);
    }
}

class WindyForce : PhysicForce {
    Vector2f windSpeed;
    private const cStokesConstant = 6*math.PI;

    this() {
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

class GravityCenter : PhysicForce {
    float accel, radius;
    Vector2f pos;
    PhysicObject attach;

    this() {
    }
    this(PhysicObject attach, float acc, float rad) {
        argcheck(attach);
        this.attach = attach;
        accel = acc;
        radius = rad;
    }

    private float cDistDelta = 0.01f;
    void applyTo(PhysicObject o, float deltaT) {
        if (attach) {
            pos = attach.pos;
        }
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

//"homing missile" force: makes one object fly to another (or a position)
class HomingForce : PhysicForce {
    PhysicObject mover;         //the object being moved (i.e. the missile)
    Vector2f targetPos;         //fly to this position...
    PhysicObject targetObj;     //  ... or target this object (overrides pos)
    float forceA;               //acceleration force
    float forceT;               //turning force

    this(PhysicObject mover, float forceA, float forceT) {
        argcheck(mover);
        this.mover = mover;
        this.forceA = forceA;
        this.forceT = forceT;
    }

    private Vector2f calcForce(Vector2f target) {
        Vector2f totarget = target - mover.pos;
        //accelerate/brake
        Vector2f cmpAccel = totarget.project_vector(mover.velocity);
        float al = cmpAccel.length;
        float ald = totarget.project_vector_len(mover.velocity);
        //steering
        Vector2f cmpTurn = totarget.project_vector(mover.velocity.orthogonal);
        float tl = cmpTurn.length;

        Vector2f fAccel, fTurn;
        //acceleration force
        if (al > float.epsilon)
            fAccel = cmpAccel/al*forceA;
        //turn force
        if (tl > float.epsilon) {
            fTurn = cmpTurn/tl*forceT;
            if (ald > float.epsilon && 2.0f*tl < al) {
                //when flying towards target and angle is small enough, limit
                //  turning force to fly a nice arc
                Vector2f v1 = cmpTurn/tl;
                Vector2f v2 = v1 - 2*v1.project_vector(totarget);
                //compute radius of circle trajectory
                float r =  (totarget.y*v2.x - totarget.x*v2.y)
                    /(v2.x*v1.y - v1.x*v2.y);
                //  a = v^2 / r ; F = m * a
                float fOpt_val = mover.posp.mass
                    * mover.velocity.quad_length / r;
                //turn slower if we will still hit dead-on
                if (fOpt_val < forceT)
                    fTurn = fOpt_val*cmpTurn/tl;
            }
        }
        return fAccel + fTurn;
    }

    void applyTo(PhysicObject o, float deltaT) {
        if (o is mover) {
            auto pos = targetObj ? targetObj.pos : targetPos;
            o.addForce(calcForce(pos));
        }
    }
}
