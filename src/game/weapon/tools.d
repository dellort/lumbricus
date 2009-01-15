module game.weapon.tools;

import game.game;
import game.sprite;
import game.weapon.weapon;
import game.worm;
import game.gamepublic;
import physics.world;
import utils.configfile;
import utils.factory;
import utils.reflection;
import utils.time;
import utils.vector2;
import utils.color;
import utils.misc;

import std.string : format;
import std.math : signbit;

debug import std.stdio;

//sub-factory used by ToolClass (stupid double-factory)
class ToolsFactory : StaticFactory!(Tool, ToolClass, WormSprite) {
}

//covers tools like jetpack, beamer, superrope
//these are not actually weapons, but the weapon-code is generic enough to
//cover these tools (including weapon window etc.)
class ToolClass : WeaponClass {
    private {
        char[] mSubType;
    }

    this(GameEngine engine, ConfigNode node) {
        super(engine, node);
        mSubType = node.getStringValue("subtype", "none");
    }

    //xxx class
    this (ReflectCtor c) {
        super(c);
    }

    override Shooter createShooter(GObjectSprite go) {
        //for now, only worms are enabled to use tools
        //(because of special control methods, i.e. for jetpacks, ropes...)
        auto worm = cast(WormSprite)(go);
        if (!worm)
            throw new Exception(format("not a worm: %s", go));
        return ToolsFactory.instantiate(mSubType, this, worm);
    }

    static this() {
        WeaponClassFactory.register!(typeof(this))("tool");
    }
}

abstract class Tool : Shooter {
    protected ToolClass mToolClass;
    protected WormSprite mWorm;

    override bool delayedAction() {
        return false;
    }

    this(ToolClass base, WormSprite a_owner) {
        super(base, a_owner, a_owner.engine);
        mToolClass = base;
        mWorm = a_owner;
    }

    this (ReflectCtor c) {
        super(c);
    }

    bool activity() {
        return active;
    }
}

class Jetpack : Tool {
    this(ToolClass b, WormSprite o) {
        super(b, o);
    }

    this (ReflectCtor c) {
        super(c);
    }

    override protected void doFire(FireInfo info) {
        reduceAmmo();
        mWorm.activateJetpack(true);
        active = true;
    }

    override protected bool doRefire() {
        //second fire: deactivate jetpack again
        mWorm.activateJetpack(false);
        active = false;
        finished();
        return true;
    }

    override void simulate(float deltaT) {
        super.simulate(deltaT);
        //if it was used but it's not active anymore => die
        if (!mWorm.jetpackActivated()) {
            active = false;
            finished();
        }
    }

    static this() {
        ToolsFactory.register!(typeof(this))("jetpack");
    }
}

class Rope : Tool {
    private {
        bool mUsed;
        PhysicConstraint mRope;
        LineGraphic mLine;
        bool mShooting;
        Vector2f mShootDir;
        Time mShootStart;
        Vector2f mMoveVec;

        const cShootSpeed = 1000;
        const cMaxLength = 1000;
        const cMoveSpeed = 500;
        const cSwingForce = 3000;

        //segments go from anchor to object
        //(because segments are added in LIFO-order as the object moves around)
        RopeSegment[] ropeSegments;

        struct RopeSegment {
            Vector2f start, end;
            //side on which the rope was hit (sign bit of scalar product)
            //(invalid for the last segment)
            bool hit;
            LineGraphic line;

            Vector2f direction() {
                return (end-start).normal;
            }
        }
    }

    this(ToolClass b, WormSprite o) {
        super(b, o);
    }

    this (ReflectCtor c) {
        super(c);
    }

    override protected void doFire(FireInfo info) {
        mShooting = true;
        mShootDir = info.dir;
        mShootStart = engine.gameTime.current;
        mLine = engine.graphics.createLine;
        mLine.setColor(Color(1,0,0));
        active = true;
        /*if (!engine.physicworld.thickRay(mWorm.physics.pos, info.pointto, 3, hit1, hit2)) {
            hit2 = mWorm.physics.pos;
            hit1 = info.pointto;
        }
        mLine2.setPos(toVector2i(hit2), toVector2i(info.pointto));*/
        /*float len = (mWorm.physics.pos - info.pointto).length * 0.9f;
        mRope = new PhysicConstraint(mWorm.physics, info.pointto, len, 0.1, true);
        engine.physicworld.add(mRope);
        active = true;*/
    }

    override protected bool doRefire() {
        //second fire: deactivate rope
        abortShoot();
        abortRope();
        finished();
        return true;
    }

    override void interruptFiring() {
        if (active) {
            abortShoot();
            abortRope();
            finished();
        }
    }

    private void abortShoot() {
        active = false;
        mShooting = false;
        if (mLine)
            mLine.remove;
        mLine = null;
    }

    private void abortRope() {
        if (!mRope)
            return;
        mRope.dead = true;
        mRope = null;
        foreach (ref seg; ropeSegments) {
            segmentDead(seg);
        }
        ropeSegments = null;
        mWorm.activateRope(null);
    }

    private void segmentDead(ref RopeSegment seg) {
        if (seg.line)
            seg.line.remove();
        seg.line = null;
    }

    private void segmentInit(ref RopeSegment seg) {
        seg.line = engine.graphics.createLine();
        seg.line.setColor(Color(0,1,0));
    }

    private void ropeMove(Vector2f mv) {
        mMoveVec = mv;
    }

    override void simulate(float deltaT) {
        super.simulate(deltaT);
        if (mShooting) {
            float t = (engine.gameTime.current - mShootStart).secsf;
            auto p2 = mWorm.physics.pos + mShootDir*cShootSpeed*t;
            mLine.setPos(toVector2i(mWorm.physics.pos), toVector2i(p2));
            float len = (mWorm.physics.pos-p2).length;
            if (len > cMaxLength) {
                abortShoot();
                return;
            }

            Vector2f hit1, hit2;
            if (engine.physicworld.thickRay(mWorm.physics.pos, p2, 3,
                hit1, hit2))
            {
                abortShoot();
                if (len > 15) {
                    ropeSegments.length = 1;
                    ropeSegments[0].start = hit1;
                    ropeSegments[0].end = mWorm.physics.pos;
                    segmentInit(ropeSegments[0]);
                    mRope = new PhysicConstraint(mWorm.physics, hit1, len, 0.8, false);
                    engine.physicworld.add(mRope);
                    mWorm.activateRope(&ropeMove);
                    active = true;
                }
            }
        }

        if (!mRope)
            return;

        Vector2f wormPos = mWorm.physics.pos;

        ropeSegments[$-1].end = wormPos;

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
                bool d = !!signbit((old.start-old.end)*(old.end-wormPos).orthogonal);
                if (d != old.hit) {
                    debug writefln("remove segment");
                    //remove it
                    segmentDead(ropeSegments[$-1]);
                    ropeSegments.length = ropeSegments.length - 1;
                    ropeSegments[$-1].end = wormPos;
                    mRope.length = (wormPos - old.start).length;
                    //NOTE: .hit is invalid for the last segment
                    //try more
                    continue outer_loop;
                }
            }

            //2. check for a new connection point (which creates a line segment)
            //walk along the
            //I think to make it 100% correct you had to pick the best match
            //of all of the possible collisions, but it isn't worth it
            Vector2f hit1, hit2;
            if (engine.physicworld.thickRay(ropeSegments[$-1].start, wormPos, 3,
                hit1, hit2) && (wormPos-hit1).quad_length > 3)
            {
                if (hit1 != hit2)
                    debug writefln("seg: h1 %s, h2 %s, worm %s",hit1,hit2, wormPos);
                else
                    debug writefln("seg: h1 %s, worm %s",hit1, wormPos);
                //collided => new segment to attach the rope to the
                //  connection point
                ropeSegments.length = ropeSegments.length + 1;
                segmentInit(ropeSegments[$-1]);
                auto st = ropeSegments[$-2].start;
                ropeSegments[$-2].hit =
                    !!signbit((st-hit1)*(hit1-wormPos).orthogonal);
                ropeSegments[$-2].end = hit1;
                ropeSegments[$-1].start = hit1;
                ropeSegments[$-1].end = wormPos;
                mRope.length = (wormPos - hit1).length;
                //.hit is invalid
                //try for more collisions or whatever
                continue outer_loop;
            }

            //3. nothing to do anymore, bye!
            break;
        }

        mRope.anchor = ropeSegments[$-1].start;

        auto swingdir = -(mRope.anchor - mWorm.physics.pos).normal.orthogonal;
        //mWorm.physics.selfForce = swingdir*mMoveVec.x*cSwingForce;
        mWorm.physics.selfForce = mMoveVec.X*cSwingForce;

        if (mMoveVec.y) {
            float rope_len = 0;
            foreach (ref seg; ropeSegments[0..$-1]) {
                rope_len += (seg.end - seg.start).length;
            }
            auto lastSegLen = (ropeSegments[$-1].end - ropeSegments[$-1].start).length;
            auto maxLen = cMaxLength - rope_len;
            auto nlen = lastSegLen + mMoveVec.y*cMoveSpeed*deltaT;
            auto destlen = clampRangeC!(float)(nlen, 0, maxLen);
            if (destlen > 0)
                mRope.length = destlen;
        }

        foreach (ref seg; ropeSegments) {
            assert (!!seg.line);
            seg.line.setPos(toVector2i(seg.start), toVector2i(seg.end));
        }
        mWorm.physics.forceLook(swingdir);
    }

    static this() {
        ToolsFactory.register!(typeof(this))("rope");
    }
}
