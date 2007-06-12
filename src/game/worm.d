module game.worm;

import game.gobject;
import game.animation;
import game.common;
import game.physic;
import game.game;
import game.sprite;
import game.weapon;
import utils.misc;
import utils.vector2;
import utils.time;
import utils.log;
import utils.misc;
import std.math;
import str = std.string;

static this() {
    gSpriteClassFactory.register!(WormSpriteClass)("worm_mc");
}

enum WormState {
    Stand = 0,
    Fly,
    Walk,
    Jet,
    Weapon,
    Death,
}

/+
  just an idea:
  thing which can be controlled like a worm
  game/controller.d would only have a sprite, which could have this interface...

interface IControllable {
    void move(Vector2f dir);
    void jump();
    void activateJetpack(bool activate);
    void drawWeapon(bool draw);
    bool weaponDrawn();
    void shooter(Shooter w);
    Shooter shooter();
    xxx not uptodate
}
+/

class WormSprite : GObjectSprite {
    private {
        WormSpriteClass wsc;

        //indexed by WormState (not sure why I did that with an array)
        //also could be moved to wsc (i.e. when killing that array...)
        StaticStateInfo[WormState.max+1] mStates;

        float mWeaponAngle = 0;
        float mWeaponMove = 0;

        //selected weapon
        Shooter mWeapon;

        //by default off, GameController can use this
        bool mDelayedDeath;

        SpriteAnimationInfo* mGravestone;
    }

    //if can move etc.
    bool haveAnyControl() {
        return !shouldDie();
    }

    void gravestone(int grave) {
        assert(grave >= 0 && grave < wsc.gravestones.length);
        mGravestone = wsc.gravestones[grave];
    }

    void delayedDeath(bool delay) {
        mDelayedDeath = delay;
    }
    bool delayedDeath() {
        return mDelayedDeath;
    }

    //if object wants to die; if true, call finallyDie() (etc.)
    //xxx unclear what this means if object is really dead (active==false)
    //so, horribly fail if really dead now
    bool shouldDie() {
        assert(active());
        return physics.lifepower <= 0;
    }

    bool isDelayedDying() {
        return currentState is mStates[WormState.Death];
    }

    void finallyDie() {
        if (active) {
            if (isDelayedDying())
                return;
            //assert(delayedDeath());
            assert(shouldDie());
            setState(mStates[WormState.Death]);
        }
    }

    protected this (GameEngine engine, WormSpriteClass spriteclass) {
        super(engine, spriteclass);
        wsc = spriteclass;
        //blah
        mStates[WormState.Stand] = findState("sit");
        mStates[WormState.Fly] = findState("fly");
        mStates[WormState.Walk] = findState("walk");
        mStates[WormState.Jet] = findState("jetpack");
        mStates[WormState.Weapon] = findState("weapon");
        mStates[WormState.Death] = findState("death");

        gravestone = 0;
    }

    protected SpriteAnimationInfo* getAnimationInfoForState(StaticStateInfo info)
    {
        if (currentState is mStates[WormState.Weapon] && mWeapon) {
            return mWeapon.weapon.animations[WeaponWormAnimations.Hold];
        } else if (currentState is mStates[WormState.Death]) {
            return mGravestone;
        } else {
            return super.getAnimationInfoForState(info);
        }
    }
    protected SpriteAnimationInfo* getAnimationInfoForTransition(
        StateTransition st, bool reverse)
    {
        //xxx this sucks make better
        if ((st.to is mStates[WormState.Weapon]
            || st.from is mStates[WormState.Weapon])
            && mWeapon)
        {
            return mWeapon.weapon.animations[!reverse
                ? WeaponWormAnimations.Arm : WeaponWormAnimations.UnArm];
        } else {
            return super.getAnimationInfoForTransition(st, reverse);
        }
    }

    //movement for walking/jetpack
    void move(Vector2f dir) {
        if (jetpackActivated) {
            //velocity or force? sigh.
            physics.selfForce = dir * wsc.jetpackVelocity;
        } else if (weaponDrawn) {
            mWeaponMove = dir.y;
        } else {
            physics.setWalking(dir);
        }
    }

    //overwritten from GObject.simulate()
    override void simulate(float deltaT) {
        super.simulate(deltaT);
        if (weaponDrawn) {
            //when user presses key to change weapon angle
            //can rotate through all 360 degrees in 5 seconds
            //(given abs(mWeaponMove) == 1)
            mWeaponAngle += mWeaponMove*deltaT*PI*2/5;
            updateAnimation();
        }
    }

    void jump() {
        if (physics.isGlued && !jetpackActivated) {
            auto look = Vector2f.fromPolar(1, physics.lookey);
            look.y = 0;
            look = look.normal(); //get sign *g*
            physics.push(Vector2f(100*look.x, -100));
        }
    }

    void updateAnimation() {
        super.updateAnimation();
        if (weaponDrawn && !currentTransition) {
            if (!graphic.currentAnimation)
                return;
            //-angle: animations are clockwise in the bitmap
            //+PI/2*3: animations start at 270 degrees
            //+PI: huh? I don't really know...
            auto angle = realmod(-mWeaponAngle+PI/2*3+PI, PI*2)/(PI);
            if (angle > 1.0f) {
                angle = 2.0f - angle;
                //NOTE: since super.updateAnimation() resets the animation,
                //      graphic.currentAnimation will always be unmirrored first
                graphic.setAnimation(graphic.currentAnimation.getMirroredY());
            }
            graphic.paused = true;
            graphic.setFrame(
                cast(int)(angle*graphic.currentAnimation.frameCount));
        }
    }

    void drawWeapon(bool draw) {
        if (draw == weaponDrawn)
            return;
        if (draw && currentState !is mStates[WormState.Stand])
            return;

        setState(draw ? mStates[WormState.Weapon] : mStates[WormState.Stand]);
    }
    bool weaponDrawn() {
        return currentState is mStates[WormState.Weapon];
    }

    //xxx: clearify relationship between shooter and so on
    void shooter(Shooter sh) {
        mWeapon = sh;
        if (!sh) {
            drawWeapon(false);
        }
        //xxx: if weapon is changed, play the correct animations
        updateAnimation();
    }
    Shooter shooter() {
        return mWeapon;
    }

    override protected void stateTransition(StaticStateInfo from,
        StaticStateInfo to)
    {
        //hm... no animations while holding a weapon, because the animation here
        //isn't really an animation, instead each frame is for a specific angle
        //to hold the weapon...
        //so, updateAnimation() sets paused to true, and this resets it again
        if (!weaponDrawn) {
            graphic.paused = false;
            mWeaponMove = 0;
        }
    }

    override protected void transitionEnd() {
        if (currentState is mStates[WormState.Weapon]) {
            mWeaponAngle = physics.lookey;
            mWeaponMove = 0;
        }
    }

    void fireWeapon() {
        if (!weaponDrawn || !mWeapon)
            return; //go away
        //xxx: I'll guess I'll move this into GameController?
        FireInfo info;
        info.dir = Vector2f.fromPolar(1.0f, mWeaponAngle);
        info.shootby = physics;
        info.strength = mWeapon.weapon.throwStrength;
        info.timer = mWeapon.weapon.timerFrom;
        mWeapon.fire(info);
    }

    bool jetpackActivated() {
        return currentState is mStates[WormState.Jet];
    }

    //activate = activate/deactivate the jetpack
    void activateJetpack(bool activate) {
        StaticStateInfo wanted = activate ? mStates[WormState.Jet]
            : mStates[WormState.Stand];
        if (!activate) {
            physics.selfForce = Vector2f(0);
        }
        setState(wanted);
    }

    override protected void physUpdate() {
        if (!jetpackActivated) {
            //update walk animation
            if (physics.isGlued) {
                bool walk = physics.isWalking;
                setState(walk ?
                    mStates[WormState.Walk] : mStates[WormState.Stand]);
            }

            //update if worm is flying around...
            bool onGround = currentState is mStates[WormState.Stand]
                || currentState is mStates[WormState.Walk]
                || currentState is mStates[WormState.Weapon];
            if (physics.isGlued != onGround) {
                setState(physics.isGlued
                    ? mStates[WormState.Stand] : mStates[WormState.Fly]);
            }
        }
        //check death
        if (active && shouldDie() && !delayedDeath()) {
            finallyDie();
        }
        super.physUpdate();
    }
}

//the factories work over the sprite classes, so we need one
class WormSpriteClass : GOSpriteClass {
    float jetpackVelocity;
    SpriteAnimationInfo*[] gravestones;

    this(GameEngine e, char[] r) {
        super(e, r);
    }
    override void loadFromConfig(ConfigNode config) {
        super.loadFromConfig(config);
        jetpackVelocity = config.getFloatValue("jet_velocity", 0);
        char[] grave = config.getStringValue("gravestones", "notfound");
        int count = config.getIntValue("gravestones_count");
        gravestones.length = count;
        foreach (int n, inout SpriteAnimationInfo* inf; gravestones) {
            inf = allocSpriteAnimationInfo();
            //violate capsulation a bit
            inf.ani2angle = Angle2AnimationMode.Simple;
            inf.animations = [engine.findAnimation(str.format("%s%d", grave, n))];
        }
    }
    override WormSprite createSprite() {
        return new WormSprite(engine, this);
    }
}

