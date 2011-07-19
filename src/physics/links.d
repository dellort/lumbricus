module physics.links;

import framework.drawing;

import std.math;
import utils.misc;
import utils.vector2;

import physics.base;
import physics.contact;
import physics.physobj;
import physics.misc;
import physics.plane;

class PhysicConstraint : PhysicContactGen {
    PhysicObject obj;
    ///fixed point in the world
    Vector2f anchor;
    ///desired length
    float length, lengthChange;
    ///length limit (for lengthChange)
    float maxLength = float.infinity;
    ///cor (bounciness) for this cable
    float restitution;
    ///false will also enforce minimum length
    bool isCable;

    private enum cTolerance = 0.01f;
    private float lcInt;

    this(PhysicObject obj, Vector2f anchor, float length, float restitution = 0,
        bool isCable = false)
    {
        argcheck(obj);
        this.obj = obj;
        this.anchor = anchor;
        this.length = length;
        this.restitution = restitution;
        this.isCable = isCable;
    }

    override void process(float deltaT, CollideDelegate contactHandler) {
        if (lengthChange > float.epsilon || lengthChange < -float.epsilon) {
            lcInt = lengthChange;
            if (lcInt > 0 && obj.mSurfaceCtr > 0) {
                //don't extend into the surface
                //float a = (anchor - obj.pos).normal*obj.surface_normal;
                //Trace.formatln("%s", a);
                //if (a > 0.5)
                    lcInt = 0;
            }
            length += lcInt*deltaT;
            if (length < float.epsilon)
                length = 0f;
            if (length > maxLength)
                length = maxLength;
        } else {
            lcInt = 0;
        }
        float currentLen = (obj.pos - anchor).length;
        float deltaLen = currentLen - length;

        //check if current length is within tolerance
        if (abs(deltaLen) < cTolerance)
            return;

        //generate contact to fix length difference
        Contact c;
        c.obj[0] = obj;
        c.obj[1] = null;
        c.source = ContactSource.generator;

        Vector2f n = (anchor - obj.pos).normal;
        assert(!n.isNaN);

        if (deltaLen > 0) {
            //too long
            c.normal = n;
            c.depth = deltaLen;
        } else if (!isCable) {
            //too short, only for rods
            c.normal = -n;
            c.depth = -deltaLen;
        } else {
            return;
        }

        c.restitution = restitution;

        contactHandler(c);
    }

    override void afterResolve(float deltaT) {
        //check if the length has been fully corrected by contact resolution
        float currentLen = (obj.pos - anchor).length;
        float deltaLen = currentLen - length;

        //if not, assume we hit something, and set new length to actual length
        //this check prevents shortening when no lengthChange is applied
        if ((deltaLen < -cTolerance && lcInt > float.epsilon)
            || (deltaLen > cTolerance && lcInt < -float.epsilon))
            length = currentLen;
    }
}

//hacked on top of PhysicConstraint
//Disclaimer: I know nothing about game physics (hey I didn't read that book)
class PhysicObjectsRod : PhysicContactGen {
    PhysicObject[2] obj;
    //fixed anchor point (used if obj[1] is null)
    Vector2f anchor;
    float length;
    //negative: magic value to default to old behaviour
    float springConstant = -1;
    //viscous damper
    float dampingCoeff = 0;

    private enum cTolerance = 0.01f;

    //length is intialized from current distance
    this(PhysicObject obj1, PhysicObject obj2) {
        argcheck(obj1);
        argcheck(obj2);
        obj[0] = obj1;
        obj[1] = obj2;
        length = (obj1.pos - obj2.pos).length;
    }

    //static anchor point
    this(PhysicObject obj1, Vector2f anchor) {
        argcheck(obj1);
        argcheck(!anchor.isNaN());
        obj[0] = obj1;
        this.anchor = anchor;
        length = (obj1.pos - anchor).length;
    }

    ///call after objects (for mass) and springConstant have been initialized
    ///will set dampingCoeff so the spring is damped by dampingRatio (where
    ///  <1.0f means underdamped, 1.0f critically damped, >1.0f overdamped)
    void setDampingRatio(float dampingRatio = 1.0f) {
        //only for spring using force
        if (springConstant <= 0)
            return;

        float m = obj[0].posp.mass;
        if (obj[1]) {
            //xxx not sure, wikipedia formula is for one object
            m = (m + obj[1].posp.mass) / 2.0f;
        }
        assert(m > 0);

        dampingCoeff = dampingRatio * 2.0f * m * sqrt(springConstant / m);
    }

    override void process(float deltaT, CollideDelegate contactHandler) {
        if (obj[0].dead || (obj[1] && obj[1].dead)) {
            kill();
            return;
        }
        Vector2f pos1 = anchor;
        Vector2f vel1;
        if (obj[1]) {
            pos1 = obj[1].pos;
            vel1 = obj[1].velocity;
        }
        auto diff = pos1 - obj[0].pos;
        float currentLen = diff.length;
        float deltaLen = currentLen - length;

        if (abs(deltaLen) < cTolerance)
            return;

        auto diffn = diff.normal();

        if (springConstant >= 0) {
            //using forces

            //relative velocity (for damping)
            float dv = (obj[0].velocity - vel1) * diffn;

            //see http://en.wikipedia.org/wiki/Damping
            auto springForce = springConstant * diffn * deltaLen
                - dampingCoeff * diffn * dv;
            obj[0].addForce(springForce);
            if (obj[1]) {
                obj[1].addForce(-springForce);
            }
        } else {
            //using contacts as it was done in that book

            Contact c;
            c.obj[] = obj;
            c.source = ContactSource.generator;

            assert(!diffn.isNaN);

            if (deltaLen > 0) {
                //too long
                c.normal = diffn;
                c.depth = deltaLen;
            } else {
                //too short
                c.normal = -diffn;
                c.depth = -deltaLen;
            }

            c.restitution = 0;

            contactHandler(c);
        }
    }

    override void debug_draw(Canvas c) {
        super.debug_draw(c);
        Vector2f pos0 = obj[0].pos;
        Vector2f pos1 = anchor;
        if (obj[1]) {
            pos1 = obj[1].pos;
        }
        float curLen = (pos1 - pos0).length;
        //0 (no deflection) to 1 (half length deflection)
        float ratio = clampRangeC!(float)(2.0f * abs(curLen - length) / length,
            0f, 1f);
        //could change color with length error, or so
        c.drawLine(toVector2i(pos0), toVector2i(pos1), map3(ratio,
            Color(0,1,0), Color(1,1,0), Color(1,0,0)));
    }
}

class PhysicFixate : PhysicContactGen {
    PhysicObject obj;
    //fixate vector, x/y != 0 to fixate on that axis
    private Vector2f mFixate;

    //position on time of fixate
    private Vector2f mFixatePos;

    private enum cTolerance = 0.01f;

    this(PhysicObject obj, Vector2f fixate) {
        argcheck(obj);
        this.obj = obj;
        this.fixate = fixate;
        updatePos();
    }

    void updatePos() {
        mFixatePos = obj.pos;
    }

    void fixate(Vector2f fix) {
        mFixate.x = fix.x>float.epsilon?0.0f:1.0f;
        mFixate.y = fix.y>float.epsilon?0.0f:1.0f;
    }

    override void process(float deltaT, CollideDelegate contactHandler) {
        //hack, so it won't generate a contact for a killed object
        if (!obj.active)
            return;
        Vector2f dist = (mFixatePos - obj.pos).mulEntries(mFixate);

        float distLen = dist.length;
        //check if current length is within tolerance
        if (abs(distLen) < cTolerance)
            return;

        //generate contact to fix position difference
        Contact c;
        c.obj[0] = obj;
        c.obj[1] = null;
        c.source = ContactSource.generator;

        Vector2f n = dist/distLen;
        assert(!n.isNaN);

        c.normal = n;
        c.depth = distLen;

        c.restitution = 0;

        contactHandler(c);
    }

    override void debug_draw(Canvas c) {
        super.debug_draw(c);
        //just make it visible in some arbitrary way
        auto p = toVector2i(obj.pos);
        auto d = Vector2i(10);
        c.drawRect(Rect2i(p-d, p+d), Color(0,0,1));
    }
}


//special contact gen to make objects bounce like stones on a water surface
//current implementation only works for horizontal surfaces
class WaterSurfaceGeometry : PhysicContactGen {
    Plane plane;

    this(float yPos) {
        updatePos(yPos);
    }
    this() {
    }

    void updatePos(float yPos) {
        plane.define(Vector2f(0, yPos), Vector2f(1, yPos));
    }

    override protected void addedToWorld() {
        //register fixed collision id "water_surface" on first call
        collision = world.collide.findCollisionID("water_surface");
    }

    override void process(float deltaT, CollideDelegate contactHandler) {
        void handler(ref Contact c) {
            PhysicObject obj = c.obj[0];
            //only works for horizontal surface
            float a = abs(obj.velocity.x) / obj.velocity.y;
            //~20°
            if (a > 2.7f) {
                Contact contact;
                contact.fromObj(obj, null, c.normal, c.depth);
                //no y speed reduction, or we get strange "sliding" effects
                contact.restitution = 1.0f;
                //don't blow up projectiles
                contact.source = ContactSource.generator;
                //xxx lol hack etc.: slow object down a little
                obj.velocity_int.x *= 0.85f;
                contactHandler(contact);
            }
        }
        world.dynamicObjects.collideShapeT(plane, collision, &handler);
    }
}
