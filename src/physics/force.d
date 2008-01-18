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

    abstract Vector2f getAccelFor(PhysicObject o, float deltaT);

    override /+package+/ void doRemove() {
        super.doRemove();
        //forces_node.removeFromList();
        world.mForceObjects.remove(this);
    }
}

class ConstantForce : PhysicForce {
    //directed force, in Wormtons
    //(1 Wormton = 10 Milli-Worms * 1 Pixel / Seconds^2 [F=ma])
    Vector2f accel;

    Vector2f getAccelFor(PhysicObject, float deltaT) {
        return accel;
    }
}

class WindyForce : ConstantForce {
    Vector2f getAccelFor(PhysicObject o, float deltaT) {
        return accel * o.posp.windInfluence;
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
    Vector2f getAccelFor(PhysicObject o, float deltaT) {
        float impulse = damage*cDamageToImpulse;
        Vector2f v = (pos-o.pos);
        float dist = v.length;
        if (dist > cDistDelta) {
            float r = max(radius-dist,0f)/radius;
            float before = o.lifepower;
            o.applyDamage(r*damage);
            float diff = before - o.lifepower;
            //corner cases; i.e. unvincible worm
            if (diff != diff || diff == typeof(diff).infinity)
                diff = 0;
            if (diff != 0 && onReportApply) {
                onReportApply(cause, o.backlink, diff);
            }
            return -v.normal()*(impulse/deltaT)*r/o.posp.mass
                    * o.posp.explosionInfluence;
        } else {
            return Vector2f(0,0);
        }
    }
}

class GravityCenter : PhysicForce {
    float accel, radius;
    Vector2f pos;

    private float cDistDelta = 0.01f;
    Vector2f getAccelFor(PhysicObject o, float deltaT) {
        Vector2f v = (pos-o.pos);
        float dist = v.length;
        if (dist > cDistDelta) {
            float r = (max(radius-dist,0f)/radius);
            return v.normal()*accel*r;
        } else {
            return Vector2f(0,0);
        }
    }
}

//Stokes's drag
//special case, because it reads the object's mediumViscosity value
//xxx would be better to apply this in a fixed region and store the viscosity
//    here (e.g. PhysicForceZone)
class StokesDrag : PhysicForce {
    //constant from Stokes's drag
    const cStokesConstant = 6*PI;

    Vector2f getAccelFor(PhysicObject o, float deltaT) {
        if (o.posp.mediumViscosity != 0.0f)
            return ((o.posp.mediumViscosity*cStokesConstant
                *o.posp.radius)* -o.velocity)/o.posp.mass;
        return Vector2f.init;
    }
}
