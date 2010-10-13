module physics.contact;

import utils.list2;
import utils.misc;
import utils.vector2;

import physics.base;
import physics.collisionmap;
import physics.physobj;
import physics.misc;

import math = tango.math.Math;
import ieee = tango.math.IEEE;

alias void delegate(ref Contact c) CollideDelegate;

//mostly stolen from "Game Physics Engine Development" by Ian Millington
struct Contact {
    ///colliding objects
    ///for collisions with static objects, obj[0] is the non-static one
    ///Broadphase.checkObjectCollisions specifically reorders obj[] so
    PhysicObject[2] obj;
    ///normal at contact point, pointing out of obj[1]
    Vector2f normal;
    ///penetration depth
    float depth;
    ///coeff. of restitution
    float restitution;

    ///how this contact was generated
    ContactSource source = ContactSource.object;
    ContactHandling handling;

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
        assert(!obj[0].isStatic);

        source = obj[1] && obj[1].isStatic
            ? ContactSource.geometry : ContactSource.object;

        //calculate cor (coeff. of restitution) of this collision
        //xxx I have absolutely no idea if this makes sense,
        //    there's no info on this anywhere
        restitution = obj[0].posp.elasticity;
        //stupid average, multiplication would also be possible
        if (obj[1] && source != ContactSource.geometry)
            restitution = (restitution + obj[1].posp.elasticity)/2.0f;
    }

    ///Resolve contact velocity and penetration
    //xxx ROFL, for geometry collisions, this was solved
    //    in 4 (four) lines before
    package void resolve(float deltaT) {
        if (handling != ContactHandling.noImpulse) {
            //normal, pushBack
            matchGlueState();
            resolveVel(deltaT);
            resolvePt(deltaT);
        } else {
            assert(!!obj[1]);
            //generate 2 contacts that behave like the objects hit a wall
            // (avoids special code in the complicated mess below)
            if (obj[0].velocity.length > float.epsilon || obj[0].isWalking()) {
                Contact c1 = *this;
                c1.obj[1] = null;
                c1.depth /= 2;
                c1.handling = ContactHandling.normal;
                c1.fromObjInit();
                c1.resolve(deltaT);
            }
            if (obj[1].velocity.length > float.epsilon || obj[1].isWalking()) {
                Contact c2 = *this;
                c2.obj[0] = c2.obj[1];
                c2.obj[1] = null;
                c2.depth /= 2;
                c2.normal = -c2.normal;
                c2.handling = ContactHandling.normal;
                c2.fromObjInit();
                c2.resolve(deltaT);
            }
        }
    }

    ///calculate the initial separating velocity of the contact
    package float calcSepVel() {
        Vector2f vRel = obj[0].velocity;
        if (obj[1] && source != ContactSource.geometry)
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
        //
        obj[0].doUnglue();
        if (obj[1])
            obj[1].doUnglue();
    }

    //resolve separating velocity, calculating the post-collide velocities
    //of both objects involved
    private void resolveVel(float deltaT) {
        assert(obj[0] !is null);
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
        //xxx: ignores acceleration caused by other forces (mForceAccum),
        //     includes only gravity => probably a bug
        Vector2f acc = obj[0].fullAcceleration;
        if (obj[1] && source != ContactSource.geometry)
            acc -= obj[1].fullAcceleration;
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
            //assert(!obj[1], "Only for geometry collisions");
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
        if (obj[1] && source != ContactSource.geometry) {
            auto objShift1 = -movePerIMass * obj[1].posp.inverseMass;
            obj[1].setPos(obj[1].pos + objShift1, true);
        }
    }

    //merge another Contact into this one
    //this is for collision tests with raw shapes (=> no PhysicObject)
    //the Contact can't be used for dynamics
    //xxx this may be total crap, we have no testcase
    void mergeFrom(ref Contact other) {
        obj[] = null;
        restitution = float.nan;
        source = ContactSource.geometry;

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
    }

    //this used to be in PhysicWorld.collideObjectWithGeometry()
    //not used with PhysicWorld.collideGeometry()
    void geomPostprocess() {
        PhysicObject o = obj[0]; //non-static one
        assert(!o.isStatic);
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
                assert(!normal.isNaN);
                depth = o.posp.radius*2;
            } else {
                //we know a safe position, so pull it back there
                Vector2f d = o.lastPos - o.pos;
                if (d.quad_length > float.epsilon) {
                    normal = d.normal;
                    assert(!normal.isNaN);
                    depth = d.length;
                } else {
                    //maybe the landscape "appeared" at the object position
                    //-> default to upwards pullout
                    normal = Vector2f(0, -1);
                    depth = o.posp.radius*2;  //step-by-step
                }
            }
        } else if (handling == ContactHandling.pushBack) {
            //back along velocity vector
            //only allowed if less than 90° off from surface normal
            Vector2f vn = -o.velocity.normal;
            float a = vn * normal;
            if (a > 0)
                normal = vn;
        }
    }
}

//for factoring out some code
struct ContactMerger {
    bool collided = false;
    Contact contact;

    void handleContact(ref Contact c) {
        if (!collided) {
            contact = c;
        } else {
            contact.mergeFrom(c);
        }
        collided = true;
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
