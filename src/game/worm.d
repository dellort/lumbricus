module game.worm;

import game.gobject;
import game.animation;
import game.common;
import game.physic;
import game.game;
import game.sprite;
import game.banana;
import utils.misc;
import utils.vector2;
import utils.time;
import utils.log;
import utils.misc;
import std.math;

enum WormState {
    Stand = 0,
    Fly,
    Walk,
    Jet,
    Weapon,
}

class Worm : GObjectSprite {
    private {
        //indexed by WormState (not sure why I did that with an array)
        StaticStateInfo[WormState.max+1] mStates;
        float mJetVelocity;

        float mWeaponAngle = 0;
        float mWeaponMove = 0;
    }

    this (GameController controller) {
        super(controller, controller.findGOSpriteClass("worm"));
        //blah
        mStates[WormState.Stand] = findState("sit");
        mStates[WormState.Fly] = findState("fly");
        mStates[WormState.Walk] = findState("walk");
        mStates[WormState.Jet] = findState("jetpack");
        mStates[WormState.Weapon] = findState("weapon");

        mJetVelocity = type.config.getFloatValue("jet_velocity", 0);
    }

    //movement for walking/jetpack
    void move(Vector2f dir) {
        if (jetpackActivated) {
            //velocity or force? sigh.
            physics.selfForce = dir*mJetVelocity;
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
            physics.push(Vector2f(10*look.x, -100));
        }
    }

    bool weaponDrawn() {
        return currentState is mStates[WormState.Weapon];
    }

    void updateAnimation() {
        super.updateAnimation();
        if (weaponDrawn && !currentTransition) {
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
        if (draw && !currentTransition) {
            mWeaponAngle = physics.lookey;
            mWeaponMove = 0;
        }
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
        }
    }

    //override protected void transitionEnd() {
    //}

    void fireWeapon() {
        if (!weaponDrawn)
            return; //go away
        //bananas only for now
        auto banana = new BananaBomb(controller);
        auto distance = physics.posp.radius+banana.physics.posp.radius+5;
        auto dir = Vector2f.fromPolar(distance, mWeaponAngle);
        banana.setPos(physics.pos + dir);
        //actually throw it *g*
        //btw: my (!) comment in physics.d says this field is "readonly" *shrug*
        banana.physics.velocity = dir*10;
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
        super.physUpdate();
    }
}

