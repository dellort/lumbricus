module game.weapon.rope;

import framework.framework;
import common.animation;
import common.resset;
import common.scene;
import game.game;
import game.gfxset;
import game.sprite;
import game.weapon.weapon;
import game.worm;
import game.sequence;
import game.temp : GameZOrder;
import physics.world;
import utils.configfile;
import utils.factory;
import utils.reflection;
import utils.time;
import utils.vector2;
import utils.color;
import utils.log;
import utils.misc;

import math = tango.math.Math;
import tango.math.IEEE : signbit;


class RopeClass : ConfWeaponClass {
    int shootSpeed = 1000;     //speed when firing
    int maxLength = 1000;      //max full rope length
    int moveSpeed = 200;       //up/down speed along rope
    int swingForce = 3000;     //force applied when rope points down
    int swingForceUp = 1000;   //force when rope points up
    Color ropeColor = Color(1);
    Surface ropeSegment;

    Animation anchorAnim;

    this(GfxSet gfx, ConfigNode node) {
        super(gfx, node);
        shootSpeed = node.getIntValue("shoot_speed", shootSpeed);
        maxLength = node.getIntValue("max_length", maxLength);
        moveSpeed = node.getIntValue("move_speed", moveSpeed);
        swingForce = node.getIntValue("swing_force", swingForce);
        swingForceUp = node.getIntValue("swing_force_up", swingForceUp);

        ropeColor = node.getValue("rope_color", ropeColor);
        auto resseg = node["rope_segment"];
        if (resseg.length)
            ropeSegment = gfx.resources.get!(Surface)(resseg);

        anchorAnim = gfx.resources.get!(Animation)(node["anchor_anim"]);
    }

    //xxx class
    this (ReflectCtor c) {
        super(c);
    }

    override Shooter createShooter(Sprite go, GameEngine engine) {
        //for now, only worms are enabled to use tools
        //(because of special control methods, i.e. for jetpacks, ropes...)
        auto worm = cast(WormSprite)(go);
        if (!worm)
            throw new Exception(myformat("not a worm: {}", go));
        return new Rope(this, worm);
    }

    static this() {
        WeaponClassFactory.register!(typeof(this))("rope");
    }
}

class Rope : Shooter {
    private {
        static LogStruct!("rope") log;
        bool mUsed;
        PhysicConstraint mRope;
        RenderRope mRender;
        bool mShooting;
        Vector2f mShootDir;
        Time mShootStart;
        Vector2f mMoveVec;
        Vector2f mAnchorPosition;
        float mAnchorAngle;
        bool mSecondShot = false;
        const cSecondShotVector = Vector2f(0, -1000);

        const cSegmentRadius = 3;
        //segments go from anchor to object
        //(because segments are added in LIFO-order as the object moves around)
        RopeSegment[] ropeSegments;

        struct RopeSegment {
            Vector2f start, end;
            //side on which the rope was hit (sign bit of scalar product)
            //(invalid for the last segment)
            bool hit;
            //offset for texture, so that it is drawn continuously
            int texoffset;

            Vector2f direction() {
                return (end-start).normal;
            }

            bool canRemove(Vector2f wormPos) {
                //check on which side of the plane (start, end) the new
                //position is
                bool d = !!signbit((start - end)
                    * (end - wormPos).orthogonal);
                return d != hit;
            }
        }
        RopeClass myclass;
    }
    protected WormSprite mWorm;

    this(RopeClass base, WormSprite a_owner) {
        super(base, a_owner, a_owner.engine);
        myclass = base;
        mWorm = a_owner;
    }

    this (ReflectCtor c) {
        super(c);
        c.types().registerMethod(this, &ropeMove, "ropeMove");
    }

    //check if rope anchor is still connected / can be connected
    private bool checkRopeAnchor(Vector2f anchorpos) {
        GeomContact dummy;
        return engine.physicworld.collideGeometry(anchorpos, cSegmentRadius + 2,
            dummy);
    }

    override bool delayedAction() {
        return false;
    }

    bool activity() {
        return internal_active;
    }

    override bool canReadjust() {
        return false;
    }

    override protected void doFire(FireInfo info) {
        internal_active = true;
        mShootDir = info.dir;
        shootRope();
    }

    override protected bool doRefire() {
        //second fire: deactivate rope
        if (mRope) {
            //deactivated while swinging -> allow in-air refire
            mSecondShot = true;
            //angle of last rope segment, mirrored along y axis for next shot
            mShootDir = ropeSegments[$-1].start - ropeSegments[$-1].end;
            mShootDir.x = -mShootDir.x;          //mirror along y axis
            mShootDir.y = -math.abs(mShootDir.y);//always shoot upwards
            float ax = -math.abs(mShootDir.x);   //at least 45deg up
            if (ax < mShootDir.y)
                mShootDir.y = ax;
            mShootDir = mShootDir.normal;
            abortShoot();
            abortRope();
        } else if (mSecondShot) {
            //velocity vector, rotated upwards, for next shot
            //  (not sure what's better)
            //Vector2f v = mWorm.physics.velocity;
            //mShootDir = (v + cSecondShotVector).normal;
            if (mShooting) {
                abortShoot();
                abortRope();
            } else
                shootRope();
        } else {
            //hit button while rope is still flying
            //xxx maybe not
            interruptFiring();
        }
        return true;
    }

    override void interruptFiring(bool outOfAmmo = false) {
        if (outOfAmmo)
            return;
        if (internal_active) {
            internal_active = false;
            abortShoot();
            abortRope();
            mSecondShot = false;
            finished();
        }
    }

    private void shootRope() {
        if (mShooting)
            return;
        mShooting = true;
        mShootStart = engine.gameTime.current;
        if (!mRender)
            mRender = new RenderRope(this);
        engine.scene.add(mRender);
    }

    //abort the flying (unattached) rope
    private void abortShoot() {
        mShooting = false;
        //if (mRender)
          //  mRender.removeThis();
    }

    //abort the attached rope
    private void abortRope() {
        if (mRope)
            mRope.dead = true;
        mRope = null;
        if (mRender)
            mRender.removeThis();
        ropeSegments = null;
        if (mWorm)
            mWorm.activateRope(null);
    }

    private void ropeMove(Vector2f mv) {
        mMoveVec = mv;
    }

    private void updateAnchorAnim(Vector2f pos, Vector2f toAnchor) {
        mAnchorPosition = pos;
        mAnchorAngle = toAnchor.toAngle();
    }

    override void simulate(float deltaT) {
        super.simulate(deltaT);
        if (mShooting) {
            float t = (engine.gameTime.current - mShootStart).secsf;
            auto p2 = mWorm.physics.pos + mShootDir*myclass.shootSpeed*t;
            updateAnchorAnim(p2, mShootDir);
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
                if (len > 15 && checkRopeAnchor(hit1)) {
                    //first hit removes ammo, further ones don't
                    if (!mSecondShot)
                        reduceAmmo();
                    ropeSegments.length = 1;
                    ropeSegments[0].start = hit1;
                    ropeSegments[0].end = mWorm.physics.pos;
                    //not using len here because the rope might have overshot
                    auto ropeLen = (ropeSegments[0].end
                        - ropeSegments[0].start).length;
                    //segmentInit(ropeSegments[0]);
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
        if (!mWorm.ropeActivated()) {
            interruptFiring();
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
                if (old.canRemove(wormPos)) {
                    log("remove segment");
                    //remove it
                    //segmentDead(ropeSegments[$-1]);
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
                cSegmentRadius, hit1, hit2) && (wormPos-hit1).quad_length > 150)
            {
                if (hit1 != hit2)
                    log("seg: h1 {}, h2 {}, worm {}", hit1, hit2, wormPos);
                else
                    log("seg: h1 {}, worm {}",hit1, wormPos);
                //collided => new segment to attach the rope to the
                //  connection point
                //xxx: small hack to make it more robust
                if (ropeSegments.length > 500)
                    break;
                auto st = ropeSegments[$-1].start;
                //no odd angles (lastHit - hit - wormPos should be close
                //  to a straight line)
                float a = (st-hit1)*(wormPos-hit1);
                if (a > -0.8)
                    break;
                if (ropeSegments.length < 2 ||
                    !ropeSegments[$-2].canRemove(hit1))
                {
                    ropeSegments.length = ropeSegments.length + 1;
                    //segmentInit(ropeSegments[$-1]);
                }
                ropeSegments[$-2].hit =
                    !!signbit((st-hit1)*(hit1-wormPos).orthogonal);
                ropeSegments[$-2].end = hit1;
                ropeSegments[$-1].start = hit1;
                ropeSegments[$-1].end = wormPos;
                auto len = (wormPos - hit1).length;
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
        if ((ropeSegments[$-1].end - ropeSegments[$-1].start).y < 0)
            mWorm.physics.selfForce = mMoveVec.X*myclass.swingForceUp;
        else
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
            if (rope_len + lastSegLen <= 15.1 && mMoveVec.y < 0) {
                //enforce minimum length
                mRope.lengthChange = 0;
                mRope.length = 15 - rope_len;
            } else {
                //max length of last segment
                mRope.maxLength = myclass.maxLength - rope_len;
                //new length of last segment
                mRope.lengthChange = mMoveVec.y*myclass.moveSpeed;
            }
        } else {
            mRope.lengthChange = 0;
        }

        mWorm.physics.forceLook(swingdir);
        mWorm.updateAnimation();
        updateAnchorAnim(ropeSegments[0].start, ropeSegments[0].start
            - ropeSegments[0].end);

        if (!checkRopeAnchor(ropeSegments[0].start))
            interruptFiring();
    }

    private void draw(Canvas c) {
        int texoffs = 0;

        void line(Vector2f s, Vector2f d) {
            Vector2i s2 = toVector2i(s), d2 = toVector2i(d);

            c.drawTexLine(s2, d2, myclass.ropeSegment, texoffs,
                myclass.ropeColor);

            texoffs += (d2 - s2).length;
        }

        if (mShooting) {
            line(toVector2f(mWorm.graphic.interpolated_position),
                mAnchorPosition);
        }

        texoffs = 0;
        foreach (int idx, ref seg; ropeSegments) {
            line(seg.start, (idx == ropeSegments.length-1)
                ? toVector2f(mWorm.graphic.interpolated_position) : seg.end);
        }

        AnimationParams ap;
        ap.p1 = cast(int)(mAnchorAngle/math.PI*180);
        myclass.anchorAnim.draw(c, toVector2i(mAnchorPosition), ap,
            mShootStart);
    }
}

class RenderRope : SceneObject {
    Rope rope;
    this(Rope r) {
        rope = r;
        zorder = GameZOrder.FrontObjects;
    }
    this(ReflectCtor c) {
    }
    override void draw(Canvas c) {
        rope.draw(c);
    }
}
