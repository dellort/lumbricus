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
}

class Worm : GObjectSprite {
    //indexed by WormState
    private StaticStateInfo[WormState.max+1] mStates;

    this (GameController controller) {
        super(controller, controller.findGOSpriteClass("worm"));
        //blah
        mStates[WormState.Stand] = findState("sit");
        mStates[WormState.Move] = findState("walk");
    }

    override protected void physUpdate() {
        bool walk = physics.isWalking;
        setState(walk ? mStates[WormState.Move] : mStates[WormState.Stand]);
        super.physUpdate();
    }
}

