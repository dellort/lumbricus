module physics.movehandler;

import std.math : signbit;
import utils.vector2;

import physics.base;
import physics.physobj;
import physics.geometry;

interface MoveHandler {
    //object which is handled by this object
    PhysicObject handledObject();
    //move an object
    void doMove(Vector2f delta);
    //set position (i.e. beam or when calliding)
    //  npos = new requested position
    //  correct_only = just a small correction to unstuck objects which collided
    void setPosition(Vector2f npos, bool correct_only);
}

//handles an object hanging on a rope and the objects for the rope itself,
//including movement of that stuff etc.
//xxx: used directly by PhysicObject and PhysicWorld
//     maybe should be abstracted out (together with walking-code)
class RopeHandler : PhysicBase, MoveHandler {
    //max. length of the rope (=> number of segments)
    const cRopeMaxLength = 300;
    //size of a segment (smaller is better and slower)
    const cSegmentRadius = 3;
    //add to radius for spacing between segments
    const cSegmentSpacing = 1;

    bool isShooting; //if anchor is being shooted
    bool isAttached; //anchor is attached, rope is valid

    //shooter = object attached to the rope
    PhysicObject shooter, anchor;

    //segments go from anchor to object
    //(because segments are added in LIFO-order as the object moves around)
    RopeSegment[] ropeSegments;

    struct RopeSegment {
        Vector2f start, end;
        //side on which the rope was hit (sign bit of scalar product)
        //(invalid for the last segment)
        bool hit;

        Vector2f direction() {
            return (end-start).normal;
        }
    }

    PhysicObject handledObject() {
        return dead ? null : shooter;
    }

    //call dg for each line segment
    void iterateSegments(void delegate(Vector2f start, Vector2f end) dg) {
        foreach (s; ropeSegments) {
            dg(s.start, s.end);
        }
    }

    override /+package+/ void simulate(float deltaT) {
        super.simulate(deltaT);

        assert(!dead);

        if (shooter.dead || anchor.dead) {
            dead = true;
            return;
        }

        if (isShooting) {
            ropeSegments.length = 1;
            ropeSegments[0].start = anchor.pos;
            ropeSegments[0].end = shooter.pos;
            if (!anchor.isGlued)
                return;
            //anchor got glued => enter attached state
            isShooting = false;
            isAttached = true;
        }

        assert(isAttached);
        assert(!isShooting);

        if (!anchor.isGlued) {
            //break the rope
            dead = true;
            isAttached = false;
            return;
        }

        ropeSegments[$-1].end = shooter.pos;

        //check movement of the attached object
        //for now checks all the time (not only when moved)
        //the code assumes that everything what collides with the rope is static
        //(i.e. landscape; or it releases the rope when it changes (explisions))
        outer_loop: for (;;) {
            //1. check if current (= last) rope segment can be removed, because
            //   the rope moves away from the connection point
            if (ropeSegments.length >= 2) {
                auto old = ropeSegments[$-2];
                //check on which side of the plane (old.start, old.end) the new
                //position is
                bool d = !!signbit((old.start-old.end)*(old.start-shooter.pos));
                if (d != old.hit) {
                    //remove it
                    ropeSegments.length = ropeSegments.length - 1;
                    ropeSegments[$-1].end = shooter.pos;
                    //NOTE: .hit is invalid for the last segment
                    //try more
                    continue outer_loop;
                }
            }

            //2. check for a new connection point (which creates a line segment)
            //walk along the
            //I think to make it 100% correct you had to pick the best match
            //of all of the possible collisions, but it isn't worth it
            auto dir = ropeSegments[$-1].end - ropeSegments[$-1].start;
            float len = dir.length;
            auto ndir = dir / len;
            const cHalfStep = cSegmentRadius+cSegmentSpacing;
            for (float d = 0; d < len; d += cHalfStep*2) {
                auto p = ropeSegments[$-1].start + ndir*(d+cHalfStep);
                GeomContact contact;
                if (world.collideGeometry(p, cSegmentRadius, contact)) {
                    p = p + contact.normal*contact.depth;
                    //collided => new segment to attach the rope to the
                    //  connection point
                    ropeSegments.length = ropeSegments.length + 1;
                    auto st = ropeSegments[$-2].start;
                    ropeSegments[$-2].hit =
                        !!signbit((st-p)*(st-shooter.pos));
                    ropeSegments[$-2].end = p;
                    ropeSegments[$-1].start = p;
                    ropeSegments[$-1].end = shooter.pos;
                    //.hit is invalid
                    //try for more collisions or whatever
                    continue outer_loop;
                }
            }

            //3. nothing to do anymore, bye!
            break;
        }
    }

    //called from the PhysicObject shooter
    //move the attached object by the delta vector; enforces pendulum movement
    //(and changes the vector in this way, length is cut according to it)
    //xxx: or what should happen with the length? I fail at physics
    void doMove(Vector2f delta) {
        auto ropedir = ropeSegments[$-1].direction;
        shooter.mPos += ropedir.orthogonal*(ropedir*delta);
    }

    //when position is corrected
    //xxx: possibly add a delta-vector to keep the rope length??
    //  also, break the rope if the new position is too far away
    //  (maybe could happen with beamers or so)
    void setPosition(Vector2f npos, bool correction) {
        shooter.mPos = npos;
        //break rope if complete reset of position
        if (!correction)
            dead = true;
    }

    //create a rope from this object
    this(PhysicObject from, float angle) {
        from.moveHandler = this;
        shooter = from;
        anchor = new PhysicObject();
        auto dir = Vector2f.fromPolar(1, angle);
        anchor.setPos(dir*(anchor.posp.radius+shooter.posp.radius), false);
        anchor.velocity_int = dir*10;//hm, speed
        from.world.add(anchor);
        //anchor is flying and searching for ground
        isShooting = true;
    }

    override void doDie() {
        if (shooter && shooter.moveHandler is this)
            shooter.moveHandler = null;
        anchor.dead = true;
        //just in case
        isAttached = isShooting = false;
        super.onDie();
    }
}
