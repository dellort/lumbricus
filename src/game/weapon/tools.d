module game.weapon.tools;

import framework.framework;
import game.game;
import game.sprite;
import game.weapon.weapon;
import game.worm;
import game.gamepublic;
import game.sequence;
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


class RopeClass : WeaponClass {
    int shootSpeed = 1000;
    int maxLength = 1000;
    int moveSpeed = 500;
    int swingForce = 3000;
    Color ropeColor = Color(1);
    Resource!(Surface) ropeSegment;

    SequenceState anchorAnim;

    this(GameEngine engine, ConfigNode node) {
        super(engine, node);
        shootSpeed = node.getIntValue("shoot_speed", shootSpeed);
        maxLength = node.getIntValue("max_length", maxLength);
        moveSpeed = node.getIntValue("move_speed", moveSpeed);
        swingForce = node.getIntValue("swing_force", swingForce);

        ropeColor.parse(node["rope_color"]);
        auto resseg = node["rope_segment"];
        if (resseg.length)
            ropeSegment = engine.gfx.resources.resource!(Surface)(resseg);

        anchorAnim = engine.sequenceStates.findState(node["anchor_anim"]);
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
        return new Rope(this, worm);
    }

    static this() {
        WeaponClassFactory.register!(typeof(this))("rope");
    }
}

class Rope : Shooter {
    private {
        bool mUsed;
        PhysicConstraint mRope;
        LineGraphic mLine;
        bool mShooting;
        Vector2f mShootDir;
        Time mShootStart;
        Vector2f mMoveVec;
        SequenceUpdate mSeqUpdate;
        Sequence mAnchorGraphic;
        bool mSecondShot = false;
        const cSecondShotVector = Vector2f(0, -1000);
        //for calculating texoffset
        int segment_length = 1;

        const cSegmentRadius = 3;
        //segments go from anchor to object
        //(because segments are added in LIFO-order as the object moves around)
        RopeSegment[] ropeSegments;

        struct RopeSegment {
            Vector2f start, end;
            //side on which the rope was hit (sign bit of scalar product)
            //(invalid for the last segment)
            bool hit;
            LineGraphic line;
            //offset for texture, so that it is drawn continuously
            int texoffset;

            Vector2f direction() {
                return (end-start).normal;
            }
        }
        RopeClass myclass;
    }
    protected WormSprite mWorm;

    this(RopeClass base, WormSprite a_owner) {
        super(base, a_owner, a_owner.engine);
        myclass = base;
        mWorm = a_owner;
        mSeqUpdate = new SequenceUpdate();
        if (auto tex = myclass.ropeSegment.get()) {
            if (tex.size.x > 0)
                segment_length = tex.size.x;
        }
    }

    this (ReflectCtor c) {
        super(c);
        c.types().registerMethod(this, &ropeMove, "ropeMove");
    }

    override bool delayedAction() {
        return false;
    }

    bool activity() {
        return active;
    }

    override protected void doFire(FireInfo info) {
        active = true;
        mShootDir = info.dir;
        shootRope();
        /*if (!engine.physicworld.thickRay(mWorm.physics.pos, info.pointto, 3,
            hit1, hit2))
        {
            hit2 = mWorm.physics.pos;
            hit1 = info.pointto;
        }
        mLine2.setPos(toVector2i(hit2), toVector2i(info.pointto));*/
    }

    override protected bool doRefire() {
        //second fire: deactivate rope
        if (mRope) {
            //deactivated while swinging -> allow in-air refire
            mSecondShot = true;
            //angle of last rope segment, mirrored along y axis for next shot
            mShootDir = (ropeSegments[$-1].start - ropeSegments[$-1].end).normal;
            mShootDir.x = -mShootDir.x;
            abortShoot();
            abortRope();
        } else if (mSecondShot) {
            //velocity vector, rotated upwards, for next shot
            //  (not sure what's better)
            //Vector2f v = mWorm.physics.velocity;
            //mShootDir = (v + cSecondShotVector).normal;
            shootRope();
            mSecondShot = false;
        } else {
            //hit button while rope is still flying
            //xxx maybe not
            interruptFiring();
        }
        return true;
    }

    override void interruptFiring() {
        if (active) {
            active = false;
            abortShoot();
            abortRope();
            mSecondShot = false;
            finished();
        }
    }

    private void shootRope() {
        mShooting = true;
        mShootStart = engine.gameTime.current;
        mLine = createRopeLine();
        mAnchorGraphic = new Sequence(engine);
        mAnchorGraphic.setUpdater(mSeqUpdate);
        mAnchorGraphic.setState(myclass.anchorAnim);
    }

    //abort the flying (unattached) rope
    private void abortShoot() {
        mShooting = false;
        if (mLine)
            mLine.remove;
        mLine = null;
    }

    //abort the attached rope
    private void abortRope() {
        if (mAnchorGraphic) {
            mAnchorGraphic.remove();
            mAnchorGraphic = null;
        }
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

    private LineGraphic createRopeLine() {
        auto line = engine.graphics.createLine();
        line.setColor(myclass.ropeColor);
        line.setWidth(2);
        line.setTexture(myclass.ropeSegment);
        return line;
    }

    private void segmentInit(ref RopeSegment seg) {
        seg.line = createRopeLine();
    }

    private void ropeMove(Vector2f mv) {
        mMoveVec = mv;
    }

    private void updateAnchorAnim(Vector2f pos, Vector2f toAnchor) {
        mSeqUpdate.position = toVector2i(pos);
        mSeqUpdate.velocity = Vector2f(0);
        mSeqUpdate.rotation_angle = toAnchor.toAngle();
        mSeqUpdate.lifePercent = 1.0f;
        mAnchorGraphic.simulate();
    }

    override void simulate(float deltaT) {
        super.simulate(deltaT);
        if (mShooting) {
            float t = (engine.gameTime.current - mShootStart).secsf;
            auto p2 = mWorm.physics.pos + mShootDir*myclass.shootSpeed*t;
            mLine.setPos(toVector2i(mWorm.physics.pos), toVector2i(p2));
            updateAnchorAnim(p2, p2 - mWorm.physics.pos);
            float len = (mWorm.physics.pos-p2).length;
            if (len > myclass.maxLength) {
                interruptFiring();
                return;
            }

            Vector2f hit1, hit2;
            if (engine.physicworld.thickRay(mWorm.physics.pos, p2,
                cSegmentRadius, hit1, hit2))
            {
                abortShoot();
                if (len > 15) {
                    //first hit removes ammo, further ones don't
                    if (!mSecondShot)
                        reduceAmmo();
                    ropeSegments.length = 1;
                    ropeSegments[0].start = hit1;
                    ropeSegments[0].end = mWorm.physics.pos;
                    //not using len here because the rope might have overshot
                    auto ropeLen = (ropeSegments[0].end
                        - ropeSegments[0].start).length;
                    segmentInit(ropeSegments[0]);
                    mRope = new PhysicConstraint(mWorm.physics, hit1, ropeLen,
                        0.8, false);
                    engine.physicworld.add(mRope);
                    mWorm.activateRope(&ropeMove);
                } else {
                    interruptFiring();
                }
            }
        }

        if (!mRope) {
            if (mSecondShot && !mWorm.ropeCanRefire) {
                interruptFiring();
            }
            return;
        }

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
                bool d = !!signbit((old.start-old.end)
                    * (old.end-wormPos).orthogonal);
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
            if (engine.physicworld.thickRay(ropeSegments[$-1].start, wormPos,
                cSegmentRadius, hit1, hit2) && (wormPos-hit1).quad_length > 3)
            {
                if (hit1 != hit2)
                    debug writefln("seg: h1 %s, h2 %s, worm %s",hit1,hit2,
                        wormPos);
                else
                    debug writefln("seg: h1 %s, worm %s",hit1, wormPos);
                //collided => new segment to attach the rope to the
                //  connection point
                //xxx: small hack to make it more robust
                if (ropeSegments.length > 500)
                    break;
                ropeSegments.length = ropeSegments.length + 1;
                segmentInit(ropeSegments[$-1]);
                auto st = ropeSegments[$-2].start;
                ropeSegments[$-2].hit =
                    !!signbit((st-hit1)*(hit1-wormPos).orthogonal);
                ropeSegments[$-2].end = hit1;
                ropeSegments[$-1].start = hit1;
                ropeSegments[$-1].end = wormPos;
                auto len = (wormPos - hit1).length;
                ropeSegments[$-1].texoffset = (cast(int)len +
                    ropeSegments[$-2].texoffset) % segment_length;
                mRope.length = len;
                //.hit is invalid
                //try for more collisions or whatever
                continue outer_loop;
            }

            //3. nothing to do anymore, bye!
            break;
        }

        mRope.anchor = ropeSegments[$-1].start;

        auto swingdir = -(mRope.anchor - mWorm.physics.pos).normal.orthogonal;
        //worm swinging (left/right keys)
        mWorm.physics.selfForce = mMoveVec.X*myclass.swingForce;

        if (mMoveVec.y) {
            //length adjustment of rope (up/down keys)
            //calculate length, excluding last segment
            float rope_len = 0;
            foreach (ref seg; ropeSegments[0..$-1]) {
                rope_len += (seg.end - seg.start).length;
            }
            auto lastSegLen = (ropeSegments[$-1].end
                - ropeSegments[$-1].start).length;
            //max length of last segment
            auto maxLen = myclass.maxLength - rope_len;
            //new length of last segment
            auto nlen = lastSegLen + mMoveVec.y*myclass.moveSpeed*deltaT;
            auto destlen = clampRangeC!(float)(nlen, 0, maxLen);
            if (destlen > 0)
                mRope.length = destlen;
        }

        foreach (ref seg; ropeSegments) {
            assert (!!seg.line);
            seg.line.setPos(toVector2i(seg.start), toVector2i(seg.end));
            seg.line.setTextureOffset(seg.texoffset);
        }
        mWorm.physics.forceLook(swingdir);
        updateAnchorAnim(ropeSegments[0].start, ropeSegments[0].start
            - ropeSegments[0].end);
    }
}
