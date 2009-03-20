module physics.links;

import tango.math.Math: abs;
import utils.reflection;
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

    private const cTolerance = 0.01f;

    this(PhysicObject obj, Vector2f anchor, float length, float restitution = 0,
        bool isCable = false)
    {
        this.obj = obj;
        this.anchor = anchor;
        this.length = length;
        this.restitution = restitution;
        this.isCable = isCable;
    }

    this (ReflectCtor c) {
    }

    override void process(float deltaT, CollideDelegate contactHandler) {
        if (lengthChange > float.epsilon || lengthChange < -float.epsilon) {
            length += lengthChange*deltaT;
            if (length < float.epsilon)
                length = 0f;
            if (length > maxLength)
                length = maxLength;
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
        if ((deltaLen < -cTolerance && lengthChange > float.epsilon)
            || (deltaLen > cTolerance && lengthChange < -float.epsilon))
            length = currentLen;
    }
}

class PhysicFixate : PhysicContactGen {
    PhysicObject obj;
    //fixate vector, x/y != 0 to fixate on that axis
    private Vector2f mFixate;

    //position on time of fixate
    private Vector2f mFixatePos;

    private const cTolerance = 0.01f;

    this(PhysicObject obj, Vector2f fixate) {
        this.obj = obj;
        this.fixate = fixate;
        updatePos();
    }

    this (ReflectCtor c) {
    }

    void updatePos() {
        mFixatePos = obj.pos;
    }

    void fixate(Vector2f fix) {
        mFixate.x = fix.x>float.epsilon?0.0f:1.0f;
        mFixate.y = fix.y>float.epsilon?0.0f:1.0f;
    }

    override void process(float deltaT, CollideDelegate contactHandler) {
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
}


//special geometry to make objects bounce like stones on a water surface
//current implementation only works for horizontal surfaces
class WaterSurfaceGeometry : PhysicCollider {
    Plane plane;

    this(float yPos) {
        updatePos(yPos);
    }
    this() {
    }

    this (ReflectCtor c) {
    }

    void updatePos(float yPos) {
        plane.define(Vector2f(0, yPos), Vector2f(1, yPos));
    }

    override protected void addedToWorld() {
        //register fixed collision id "water_surface" on first call
        collision = world.collide.findCollisionID("water_surface");
    }

    override bool collide(PhysicObject obj, CollideDelegate contactHandler) {
        //xxx: only works for horizontal surface
        float a = abs(obj.velocity.x) / obj.velocity.y;
        //~20°
        if (a > 2.7f) {
            Vector2f n; float d;
            bool ret = plane.collide(obj.pos, obj.posp.radius, n, d);
            if (ret) {
                Contact contact;
                contact.fromObj(obj, null, n, d);
                //no y speed reduction, or we get strange "sliding" effects
                contact.restitution = 1.0f;
                //don't blow up projectiles
                contact.source = ContactSource.generator;
                //xxx lol hack etc.: slow object down a little
                obj.velocity_int.x *= 0.85f;
                contactHandler(contact);
            }
            return ret;
        }
        return false;
    }
}
