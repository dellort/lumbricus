module physics.contact;

import utils.reflection;
import utils.list2;
import utils.vector2;

import physics.base;
import physics.physobj;
import physics.geometry;
import physics.misc;

import math = tango.math.Math;
import ieee = tango.math.IEEE;

alias void delegate(ref Contact c) CollideDelegate;

//mostly stolen from "Game Physics Engine Development" by Ian Millington
struct Contact {
    ///colliding objects, obj[1] will be null for geometry collisions
    PhysicObject[2] obj;
    ///normal at contact point, pointing out of obj[1] (or the geometry)
    Vector2f normal;
    ///penetration depth
    float depth;
    ///coeff. of restitution
    float restitution;

    ///(out) object position change due to penetration resolution
    Vector2f[2] objShift;

    ///how this contact was generated
    ContactSource source = ContactSource.object;

    ///Fill data from a geometry collision
    //xxx unify this
    void fromGeom(GeomContact c, PhysicObject o) {
        normal = c.normal;
        depth = c.depth;
        assert(!normal.isNaN);
        assert(!ieee.isNaN(depth));
        obj[0] = o;
        obj[1] = null;
        source = ContactSource.geometry;
        restitution = obj[0].posp.elasticity;
    }

    void fromObj(PhysicObject obj1, PhysicObject obj2, Vector2f n, float d) {
        obj[0] = obj1;
        obj[1] = obj2;
        normal = n;
        depth = d;
        assert(!normal.isNaN && !ieee.isNaN(depth));
        source = ContactSource.object;

        //calculate cor (coeff. of restitution) of this collision
        //xxx I have absolutely no idea if this makes sense,
        //    there's no info on this anywhere
        restitution = obj[0].posp.elasticity;
        if (obj[1])
            //stupid average, multiplication would also be possible
            restitution = (restitution + obj[1].posp.elasticity)/2.0f;
    }

    ///Resolve contact velocity and penetration
    //xxx ROFL, for geometry collisions, this was solved
    //    in 4 (four) lines before
    package void resolve(float deltaT) {
        matchGlueState();
        resolveVel(deltaT);
        resolvePt(deltaT);
    }

    ///calculate the initial separating velocity of the contact
    package float calcSepVel() {
        Vector2f vRel = obj[0].velocity;
        if (obj[1])
            vRel -= obj[1].velocity;
        return vRel * normal;
    }

    //make sure glued objects get unglued if necessary
    private void matchGlueState() {
        if (source != ContactSource.object)
            return;
        //xxx doesn't work because of walking, which collides 2 glued objects
        /*if (obj[0].isGlued ^ obj[1].isGlued) {
            if (obj[0].isGlued)
                obj[0].doUnglue();
            else
                obj[1].doUnglue();
        }*/
        if (obj[0].isGlued)
            obj[0].doUnglue();
        if (!obj[1])
            return;
        if (obj[1].isGlued)
            obj[1].doUnglue();
    }

    //resolve separating velocity, calculating the post-collide velocities
    //of both objects involved
    private void resolveVel(float deltaT) {
        float vSep = calcSepVel();
        if (vSep >= 0)
            //not moving, or moving apart (for whatever reason, dunno if ever)
            return;

        //new separating velocity, after collision
        float vSepNew = -vSep * restitution;

        //if not fast enough, a geometry bounce gets eaten
        //(note that we still apply gravity compensation)
        if (source == ContactSource.geometry
            && vSepNew < obj[0].posp.bounceAbsorb)
        {
            vSepNew = 0;
        }

        //calculate closing velocity caused by acceleration, and remove it
        //this is supposed to make resting contacts more stable
        Vector2f acc = obj[0].gravity + obj[0].acceleration;
        if (obj[1])
            acc -= obj[1].gravity + obj[1].acceleration;
        float accCausedSepVel = acc * normal * deltaT;
        if (accCausedSepVel < 0) {
            vSepNew += restitution*accCausedSepVel;
            if (vSepNew < 0)
                vSepNew = 0;
        }

        //total change in velocity
        float vDelta = vSepNew - vSep;

        float totalInvMass = obj[0].posp.inverseMass;
        if (obj[1])
            totalInvMass += obj[1].posp.inverseMass;
        if (totalInvMass <= 0)
            //total mass is infinite -> objects won't move
            return;

        float impulse = vDelta / totalInvMass;
        Vector2f impulsePerIMass = impulse * normal;

        //apply impulses
        obj[0].addImpulse(impulsePerIMass, source);
        if (obj[1])
            obj[1].addImpulse(-impulsePerIMass, source);
    }

    //resolve object penetration, to move objects out of each other
    private void resolvePt(float deltaT) {
        //no penetration -> skip
        if (depth <= 0)
            return;

        //depth = inf is set for objects entirely inside a geometry object
        if (depth == float.infinity) {
            assert(!obj[1], "Only for geometry collisions");
            //xxx
            return;
        }

        float totalInvMass = obj[0].posp.inverseMass;
        if (obj[1])
            totalInvMass += obj[1].posp.inverseMass;
        if (totalInvMass <= 0)
            //total mass is infinite -> objects won't move
            return;

        Vector2f movePerIMass = normal*(depth/totalInvMass);

        //calculate position change relative to object mass and apply
        objShift[0] = movePerIMass * obj[0].posp.inverseMass;
        obj[0].setPos(obj[0].pos + objShift[0], true);
        if (obj[1]) {
            objShift[1] = -movePerIMass * obj[1].posp.inverseMass;
            obj[1].setPos(obj[1].pos + objShift[1], true);
        } else {
            objShift[1] = Vector2f.init;
        }
    }
}

class PhysicContactGen : PhysicBase {
    package ListNode cgen_node;

    abstract void process(float deltaT, CollideDelegate contactHandler);

    void afterResolve(float deltaT) {
    }

    this() {
    }
    this (ReflectCtor c) {
    }
}

class PhysicCollider : PhysicBase {
    package ListNode coll_node;

    this() {
    }
    this (ReflectCtor c) {
    }

    abstract bool collide(PhysicObject obj, CollideDelegate contactHandler);
}
