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
    Drowning,
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

        bool mIsDead;

        SpriteAnimationInfo* mGravestone;
    }

    float weaponAngle() {
        return mWeaponAngle;
    }

    //if can move etc.
    bool haveAnyControl() {
        return !isDead();
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
    //actually, object can have any state, it even can be dead
    //you should prefer isDead()
    bool shouldDie() {
        return physics.lifepower <= 0;
    }

    //if worm is dead (including if worm is waiting to commit suicide)
    bool isDead() {
        return shouldDie() || isReallyDead();
    }
    //less strict than isDead(): return false for not-yet-suicided worms
    bool isReallyDead() {
        return mIsDead;
    }

    //if suicide animation played
    bool isDelayedDying() {
        return isReallyDead() && currentTransition;
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

    void updateControl() {
        if (!haveAnyControl()) {
            drawWeapon(false);
            activateJetpack(false);
        }
    }

    protected this (GameObjectHandler handler, GameEngine engine, WormSpriteClass spriteclass) {
        super(handler, engine, spriteclass);
        wsc = spriteclass;
        //blah
        mStates[WormState.Stand] = findState("sit");
        mStates[WormState.Fly] = findState("fly");
        mStates[WormState.Walk] = findState("walk");
        mStates[WormState.Jet] = findState("jetpack");
        mStates[WormState.Weapon] = findState("weapon");
        mStates[WormState.Death] = findState("death");
        mStates[WormState.Drowning] = findState("drowning");

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
        StateTransition st)
    {
        //xxx this sucks make better
        auto to_w = st.to is mStates[WormState.Weapon];
        auto from_w = st.from is mStates[WormState.Weapon];
        if ((to_w || from_w) && mWeapon) {
            return mWeapon.weapon.animations[to_w
                ? WeaponWormAnimations.Arm : WeaponWormAnimations.UnArm];
        } else {
            return super.getAnimationInfoForTransition(st);
        }
    }

    //movement for walking/jetpack
    void move(Vector2f dir) {
        if (jetpackActivated) {
            //velocity or force? sigh.
            Vector2f jetForce = dir.mulEntries(wsc.jetpackAccel);
            //don't accelerate down
            if (jetForce.y > 0)
                jetForce.y = 0;
            physics.selfForce = jetForce;
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
        if (draw) {
            if (currentState !is mStates[WormState.Stand])
                return;
            if (!haveAnyControl())
                return;
            if (!mWeapon)
                return;
        }

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
        super.stateTransition(from, to);
        //hm... no animations while holding a weapon, because the animation here
        //isn't really an animation, instead each frame is for a specific angle
        //to hold the weapon...
        //so, updateAnimation() sets paused to true, and this resets it again
        if (!weaponDrawn) {
            graphic.paused = false;
            mWeaponMove = 0;
        }

        if ((currentState is mStates[WormState.Death])
            || (currentState is mStates[WormState.Drowning]))
        {
            mIsDead = true;
        }
    }

    override protected void transitionEnd() {
        if (currentState is mStates[WormState.Weapon]) {
            mWeaponAngle = physics.lookey;
            mWeaponMove = 0;
        } else if (currentState is mStates[WormState.Death]) {
            //explosion!
            engine.explosionAt(physics.pos, wsc.suicideDamage);
        }
    }

    void fireWeapon() {
        assert(false);
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
        if (!isDelayedDying) {
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
        }
        super.physUpdate();
    }
}

//the factories work over the sprite classes, so we need one
class WormSpriteClass : GOSpriteClass {
    Vector2f jetpackAccel;
    float suicideDamage;
    SpriteAnimationInfo*[] gravestones;

    this(GameObjectHandler h, GameEngine e, char[] r) {
        super(h, e, r);
    }
    override void loadFromConfig(ConfigNode config) {
        super.loadFromConfig(config);
        float[] jetAc = config.getValueArray!(float)("jet_velocity", [0f,0f]);
        if (jetAc.length > 1)
            jetpackAccel = Vector2f(jetAc[0], jetAc[1]);
        else
            jetpackAccel = Vector2f(0);
        suicideDamage = config.getFloatValue("suicide_damage", 10);
        char[] grave = config.getStringValue("gravestones", "notfound");
        int count = config.getIntValue("gravestones_count");
        gravestones.length = count;
        foreach (int n, inout SpriteAnimationInfo* inf; gravestones) {
            inf = allocSpriteAnimationInfo();
            //violate capsulation a bit
            inf.ani2angle = Angle2AnimationMode.Simple;
            inf.animations = [globals.resources.anims(str.format("%s%d", grave, n))];
        }
    }
    override WormSprite createSprite() {
        return new WormSprite(handler, engine, this);
    }
}

