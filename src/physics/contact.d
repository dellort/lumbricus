module physics.contact;

import utils.list2;
import utils.vector2;

import physics.base;
import physics.collisionmap;
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

    ///how this contact was generated
    ContactSource source = ContactSource.object;

    //only used by links.d anymore
    void fromObj(PhysicObject obj1, PhysicObject obj2, Vector2f n, float d) {
        obj[0] = obj1;
        obj[1] = obj2;
        normal = n;
        depth = d;
        fromObjInit();
    }

    //init restitution and source fields
    void fromObjInit() {
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
        auto objShift0 = movePerIMass * obj[0].posp.inverseMass;
        obj[0].setPos(obj[0].pos + objShift0, true);
        if (obj[1]) {
            auto objShift1 = -movePerIMass * obj[1].posp.inverseMass;
            obj[1].setPos(obj[1].pos + objShift1, true);
        }
    }

    //merge another Contact into this one
    //this is for "geometry" objects
    //obj objShift restitution may contain garbage after this
    //xxx this may be total crap, we have no testcase
    void mergeFrom(ref Contact other) {
        assert(!!obj[0] && !obj[1]); //yyy assumptions for now
        if (depth == float.infinity)
            return;
        if (other.depth == float.infinity) {
            depth = float.infinity;
            return;
        }
        assert(depth == depth);
        assert(other.depth == other.depth);
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

        assert(!normal.isNaN);
        assert(!ieee.isNaN(depth));
        //obj[0] = o;
        //obj[1] = null;
        source = ContactSource.geometry;
        restitution = obj[0].posp.elasticity;
    }

    //this used to be in PhysicWorld.collideObjectWithGeometry()
    //not used with PhysicWorld.collideGeometry()
    //ch = simply the result of canCollide() (yyy remove)
    void geomPostprocess(ContactHandling ch) {
        assert(!!obj[0] && !obj[1]); //yyy assumptions for now
        PhysicObject o = obj[0]; //non-static one
        //kind of hack for LevelGeometry
        //if the pos didn't change at all, but a collision was
        //reported, assume the object is completely within the
        //landscape...
        //(xxx: uh, actually a dangerous hack)
        if (depth == float.infinity) {
            if (o.lastPos.isNaN) {
                //we don't know a safe position, so pull it out
                //  along the velocity vector
                normal = -o.velocity.normal;
                //assert(!ncont.normal.isNaN);
                depth = o.posp.radius*2;
            } else {
                //we know a safe position, so pull it back there
                Vector2f d = o.lastPos - o.pos;
                normal = d.normal;
                //assert(!ncont.normal.isNaN);
                depth = d.length;
            }
        } else if (ch == ContactHandling.pushBack) {
            //back along velocity vector
            //only allowed if less than 90° off from surface normal
            Vector2f vn = -o.velocity.normal;
            float a = vn * normal;
            if (a > 0)
                normal = vn;
        }
    }
}

class PhysicContactGen : PhysicBase {
    ObjListNode!(typeof(this)) cgen_node;

    abstract void process(float deltaT, CollideDelegate contactHandler);

    void afterResolve(float deltaT) {
    }

    this() {
    }
}

class PhysicCollider : PhysicBase {
    ObjListNode!(typeof(this)) coll_node;

    this() {
    }

    abstract bool collide(PhysicObject obj, CollideDelegate contactHandler);
}
