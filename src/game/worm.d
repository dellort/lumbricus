module game.worm;

import game.gobject;
import game.animation;
import game.common;
import game.physic;
import game.game;
import game.sprite;
import utils.misc;
import utils.vector2;
import utils.mylist;
import utils.time;
import utils.log;
import std.math;

enum WormState {
    Stand = 0,
    Move,
    Jet,
}

class Worm : GObjectSprite {
    //indexed by WormState (not sure why I did that with an array)
    private StaticStateInfo[WormState.max+1] mStates;
    private float mJetVelocity;

    this (GameController controller) {
        super(controller, controller.findGOSpriteClass("worm"));
        //blah
        mStates[WormState.Stand] = findState("sit");
        mStates[WormState.Move] = findState("walk");
        mStates[WormState.Jet] = findState("jetpack");

        mJetVelocity = type.config.getFloatValue("jet_velocity", 0);
    }

    //movement for walking/jetpack
    void move(Vector2f dir) {
        if (jetpackActivated) {
            //velocity or force? sigh.
            physics.selfForce = dir*mJetVelocity;
        } else {
            physics.setWalking(dir);
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
            bool walk = physics.isWalking;
            setState(walk ? mStates[WormState.Move] : mStates[WormState.Stand]);
        }
        super.physUpdate();
    }
}

