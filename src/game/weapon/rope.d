module game.weapon.rope;

import framework.drawing;
import framework.surface;
import common.animation;
import common.resset;
import common.scene;
import game.controller;
import game.core;
import game.game;
import game.sprite;
import game.weapon.weapon;
import game.worm;
import game.sequence;
import game.temp;
import game.particles;
import game.wcontrol;
import physics.all;
import utils.time;
import utils.vector2;
import utils.color;
import utils.log;
import utils.misc;

import std.math;

class RopeClass : WeaponClass {
    float shootSpeed = 1000;     //speed when firing
    float maxLength = 1000;      //max full rope length
    float moveSpeed = 200;       //up/down speed along rope
    float swingForce = 3000;     //force applied when rope points down
    float swingForceUp = 1000;   //force when rope points up
    float hitImpulse = 700;      //impulse when pushing away from a wall
    Color ropeColor = Color(1);
    Surface ropeSegment;
    ParticleType impactParticle;

    Animation anchorAnim;

    this(GameCore core, string name) {
        super(core, name);
    }

    override Shooter createShooter(Sprite go) {
        //for now, only worms are enabled to use tools
        //(because of special control methods, i.e. for jetpacks, ropes...)
        auto worm = cast(WormSprite)(go);
        if (!worm)
            throw new CustomException(myformat("not a worm: %s", go));
        return new Rope(this, worm);
    }
}

class Rope : Shooter, Controllable {
    private {
        static LogStruct!("rope") log;
        bool mUsed;
        PhysicConstraint mRope;
        RenderRope mRender;
        bool mShooting;
        Vector2f mShootDir;
        Time mShootStart;
        Vector2f mMoveVec;
        WormControl mMember;
        Vector2f mAnchorPosition;
        float mAnchorAngle;
        bool mSecondShot = false;
        bool mCanRefire;

        enum cSegmentRadius = 3;
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
        super(base, a_owner);
        myclass = base;
        mWorm = a_owner;
        auto controller = engine.singleton!(GameController)();
        mMember = controller.controlFromGameObject(mWorm, false);
    }

    //check if rope anchor is still connected / can be connected
    private bool checkRopeAnchor(Vector2f anchorpos) {
        Contact dummy;
        return engine.physicWorld.collideGeometry(anchorpos, cSegmentRadius + 2,
            dummy);
    }

    override bool delayedAction() {
        return false;
    }

    override bool canReadjust() {
        return false;
    }

    override protected void doFire() {
        mShootDir = fireinfo.dir;
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
            mShootDir.y = -abs(mShootDir.y);//always shoot upwards
            float ax = -abs(mShootDir.x);   //at least 45deg up
            if (ax < mShootDir.y)
                mShootDir.y = ax;
            mShootDir = mShootDir.normal;
            abortShoot();
            abortRope();
        } else if (mSecondShot) {
            if (mShooting) {
                abortShoot();
                abortRope();
            } else
                shootRope();
        } else {
            //hit button while rope is still flying
            //xxx maybe not
            finished();
        }
        return true;
    }

    override protected void onWeaponActivate(bool active) {
        if (active) {
            OnSpriteImpact.handler(mWorm.instanceLocalEvents,
                &onSpriteImpact_Worm);
            OnDamage.handler(mWorm.instanceLocalEvents,
                &onSpriteDamage_Worm);
        } else {
            OnSpriteImpact.remove_handler(mWorm.instanceLocalEvents,
                &onSpriteImpact_Worm);
            OnDamage.remove_handler(mWorm.instanceLocalEvents,
                &onSpriteDamage_Worm);
            abortShoot();
            abortRope();
            mSecondShot = false;
            finished();
        }
    }

    private void shootRope() {
        if (mShooting)
            return;
        setParticle(myclass.fireParticle);
        mShooting = true;
        mShootStart = engine.gameTime.current;
        if (!mRender)
            mRender = new RenderRope(this);
        engine.scene.add(mRender);
    }

    //abort the flying (unattached) rope
    private void abortShoot() {
        mShooting = false;
        setParticle(null);
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
        wormRopeActivate(false);
    }

    private void wormRopeActivate(bool activate) {
        mWorm.activateRope(activate);
        if (activate) {
            mMember.pushControllable(this);
            mWorm.physics.doUnglue();
            mWorm.physics.resetLook();
        } else {
            mMember.releaseControllable(this);
        }
        mCanRefire = true;
    }

    private void updateAnchorAnim(Vector2f pos, Vector2f toAnchor) {
        mAnchorPosition = pos;
        mAnchorAngle = toAnchor.toAngle();
    }

    Vector2f ropeOrigin(Vector2f wormPos) {
        //xxx: the correct way is to make Sequence provide weapon "joint" points
        //  (they could be even animation specific; actually we could use that
        //  in this specific case)
        if (mShooting) {
            //mShootDir is only valid while shooting, not while swinging
            return wormPos + mShootDir * mWorm.physics.posp.radius;
        } else {
            //for the "swinging worm" animation, the joint is exactly at the
            //  animation center
            //xxx this is highly wwp specific; animation code should handle it
            //xxx2 there seem to be other bugs in this file which cause the rope
            //     to shorten on new/deleted segments if the joint is not
            //     centered; but this fixed it, so why bother
            return wormPos;
        }
    }

    override void simulate() {
        super.simulate();
        if (!weaponActive)
            return;
        Vector2f pstart = ropeOrigin(mWorm.physics.pos);
        if (mShooting) {
            float t = (engine.gameTime.current - mShootStart).secsf;
            auto p2 = pstart + mShootDir*myclass.shootSpeed*t;
            updateAnchorAnim(p2, mShootDir);
            float len = (pstart-p2).length;
            if (len > myclass.maxLength) {
                finished();
                return;
            }

            Vector2f hit1, hit2;
            if (engine.physicWorld.thickRay(pstart, p2,
                cSegmentRadius, hit1, hit2))
            {
                abortShoot();
                if (len > 15 && checkRopeAnchor(hit1)) {
                    //first hit removes ammo, further ones don't
                    if (!mSecondShot)
                        reduceAmmo();
                    ropeSegments.length = 1;
                    ropeSegments[0].start = hit1;
                    ropeSegments[0].end = pstart;
                    //not using len here because the rope might have overshot
                    auto ropeLen = (ropeSegments[0].end
                        - ropeSegments[0].start).length;
                    //segmentInit(ropeSegments[0]);
                    mRope = new PhysicConstraint(mWorm.physics, hit1, ropeLen,
                        0.8, false);
                    engine.physicWorld.add(mRope);
                    if (myclass.impactParticle) {
                        engine.particleWorld.emitParticle(owner.physics.pos,
                            owner.physics.velocity, myclass.impactParticle);
                    }
                    setParticle(myclass.impactParticle);
                    wormRopeActivate(true);
                } else {
                    finished();
                }
            }
        }

        if (!mRope) {
            if (mSecondShot && !mCanRefire) {
                finished();
            }
            return;
        }
        if (!mWorm.ropeActivated()) {
            finished();
            return;
        }

        ropeSegments[$-1].end = pstart;

        //check movement of the attached object
        //for now checks all the time (not only when moved)
        //the code assumes that everything what collides with the rope is static
        //(i.e. landscape; or it releases the rope when it changes (explisions))
        outer_loop: for (;;) {
            //1. check if current (= last) rope segment can be removed, because
            //   the rope moves away from the connection point
            if (ropeSegments.length >= 2) {
                auto old = ropeSegments[$-2];
                if (old.canRemove(pstart)) {
                    log("remove segment");
                    //remove it
                    //segmentDead(ropeSegments[$-1]);
                    ropeSegments.length = ropeSegments.length - 1;
                    ropeSegments[$-1].end = pstart;
                    mRope.length = (pstart - old.start).length;
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
            if (engine.physicWorld.thickRay(ropeSegments[$-1].start, pstart,
                cSegmentRadius, hit1, hit2) && (pstart-hit1).quad_length > 150)
            {
                if (hit1 != hit2)
                    log("seg: h1 %s, h2 %s, worm %s", hit1, hit2, pstart);
                else
                    log("seg: h1 %s, worm %s",hit1, pstart);
                //collided => new segment to attach the rope to the
                //  connection point
                //xxx: small hack to make it more robust
                if (ropeSegments.length > 500)
                    break;
                auto st = ropeSegments[$-1].start;
                //no odd angles (lastHit - hit - pstart should be close
                //  to a straight line)
                float a = (st-hit1)*(pstart-hit1);
                if (a > -0.8)
                    break;
                if (ropeSegments.length < 2 ||
                    !ropeSegments[$-2].canRemove(hit1))
                {
                    ropeSegments.length = ropeSegments.length + 1;
                    //segmentInit(ropeSegments[$-1]);
                }
                ropeSegments[$-2].hit =
                    !!signbit((st-hit1)*(hit1-pstart).orthogonal);
                ropeSegments[$-2].end = hit1;
                ropeSegments[$-1].start = hit1;
                ropeSegments[$-1].end = pstart;
                auto len = (pstart - hit1).length;
                mRope.length = len;
                //.hit is invalid
                //try for more collisions or whatever
                continue outer_loop;
            }

            //3. nothing to do anymore, bye!
            break;
        }

        mRope.anchor = ropeSegments[$-1].start;

        auto swingdir = -(mRope.anchor - pstart).normal.orthogonal;
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

        //forceLook is animation+aiming, rotationOverride is animation only
        //mWorm.physics.forceLook(swingdir);
        mWorm.rotationOverride = swingdir.toAngle;
        mWorm.updateAnimation();
        updateAnchorAnim(ropeSegments[0].start, ropeSegments[0].start
            - ropeSegments[0].end);

        if (!checkRopeAnchor(ropeSegments[0].start))
            finished();
    }

    private void onSpriteImpact_Worm(Sprite sender, PhysicObject other,
        Vector2f normal)
    {
        if (sender is mWorm) {
            //when hitting landscape while arrow key held down, push away
            if (mRope && other && other.isStatic && mMoveVec.x != 0) {
                mWorm.physics.addImpulse(normal * myclass.hitImpulse);
            }
            //no refire when hit
            mCanRefire = false;
        }
    }

    private void onSpriteDamage_Worm(Sprite sender, GameObject cause,
        DamageCause dmgType, float damage)
    {
        if (sender is mWorm) {
            //no refire when damaged
            mCanRefire = false;
        }
    }

    private void draw(Canvas c) {
        Vector2f wormPos = ropeOrigin(
            toVector2f(mWorm.graphic.interpolated_position));
        Vector2f anchorPos = mAnchorPosition;
        if (mShooting) {
            //interpolate anchor
            float t = (engine.interpolateTime.current - mShootStart).secsf;
            anchorPos = wormPos + mShootDir*myclass.shootSpeed*t;
        }

        int texoffs = 0;

        void line(Vector2f s, Vector2f d) {
            Vector2i s2 = toVector2i(s), d2 = toVector2i(d);

            c.drawTexLine(s2, d2, myclass.ropeSegment, texoffs,
                myclass.ropeColor);

            texoffs += (d2 - s2).length;
        }

        if (mShooting) {
            line(wormPos, anchorPos);
        }

        texoffs = 0;
        foreach (int idx, ref seg; ropeSegments) {
            line(seg.start, (idx == ropeSegments.length-1)
                ? wormPos : seg.end);
        }

        AnimationParams ap;
        ap.p[0] = cast(int)(mAnchorAngle/PI*180);
        myclass.anchorAnim.draw(c, toVector2i(anchorPos), ap,
            mShootStart);
    }

    //Controllable implementation -->

    bool fire(bool keyDown) {
        return false;
    }

    bool jump(JumpMode j) {
        return false;
    }

    bool move(Vector2f m) {
        mMoveVec = m;
        return true;
    }

    Sprite getSprite() {
        return mWorm;
    }

    //<-- Controllable end
}

class RenderRope : SceneObject {
    Rope rope;
    this(Rope r) {
        rope = r;
        zorder = GameZOrder.FrontObjects;
    }
    override void draw(Canvas c) {
        rope.draw(c);
    }
}
