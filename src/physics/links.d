module physics.links;

import std.math: abs;
import utils.reflection;
import utils.vector2;

import physics.base;
import physics.contact;
import physics.physobj;

class PhysicConstraint : PhysicContactGen {
    PhysicObject obj;
    ///fixed point in the world
    Vector2f anchor;
    ///desired length
    float length;
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

    override void process(CollideDelegate contactHandler) {
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

    override void process(CollideDelegate contactHandler) {
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

        c.restitution = 1.0;

        contactHandler(c);
    }
}
