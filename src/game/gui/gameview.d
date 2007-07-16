module game.gui.gameview;

import framework.framework;
import common.common;
import common.scene;
import game.gamepublic;
import game.clientengine;
import gui.widget;
import gui.container;
import gui.mousescroller;
import utils.vector2;

//GameView is everything which is scrolled
//it displays the game directly and also handles input directly
//also draws worm labels
class GameView : Widget, TeamMemberControlCallback {
    private {
        ClientGameEngine mEngine;
        GameLogicPublic mLogic;
        TeamMemberControl mController;
        Container mGuiFrame;

        //key state for LEFT/RIGHT and UP/DOWN
        Vector2i dirKeyState_lu = {0, 0};  //left/up
        Vector2i dirKeyState_rd = {0, 0};  //right/down
    }

    void delegate() onTeamChange;

    override bool canHaveFocus() {
        return true;
    }
    override bool greedyFocus() {
        return true;
    }

    this(ClientGameEngine engine) {
        mEngine = engine;
        scene.add(mEngine.scene);

        //hacky?
        mLogic = mEngine.logic;
        mController = mEngine.controller;

        mController.setTeamMemberControlCallback(this);
    }

    override Vector2i layoutSizeRequest() {
        return mEngine.scene.size;
    }

    override void onRelayout() {
    }

    // --- start TeamMemberControlCallback

    void controlMemberChanged() {
        //currently needed for weapon update
        if (onTeamChange) {
            onTeamChange();
        }
    }

    void controlWalkStateChanged() {
    }

    void controlWeaponModeChanged() {
    }

    // --- end TeamMemberControlCallback

    private bool handleDirKey(char[] bind, bool up) {
        int v = up ? 0 : 1;
        switch (bind) {
            case "left":
                dirKeyState_lu.x = v;
                break;
            case "right":
                dirKeyState_rd.x = v;
                break;
            case "up":
                dirKeyState_lu.y = v;
                break;
            case "down":
                dirKeyState_rd.y = v;
                break;
            default:
                return false;
        }

        auto movementVec = dirKeyState_rd-dirKeyState_lu;
        mController.setMovement(movementVec);

        return true;
    }

    override protected bool onKeyDown(char[] bind, KeyInfo info) {
        switch (bind) {
            case "selectworm": {
                mController.selectNextMember();
                return true;
            }
            case "pointy": {
                mController.weaponSetTarget(mousePos);
                return true;
            }
            default:
        }

        if (handleDirKey(bind, false))
            return true;

        switch (bind) {
            case "jump": {
                mController.jump(JumpMode.normal);
                return true;
            }
            case "jetpack": {
                mController.jetpack(mController.walkState()
                    != WalkState.jetpackFly);
                return true;
            }
            case "fire": {
                mController.weaponFire(1.0f);
                return true;
            }
            default:

        }
        //nothing found
        return false;
    }

    override protected bool onKeyUp(char[] bind, KeyInfo info) {
        if (handleDirKey(bind, true))
            return true;
        return false;
    }

    override protected bool onMouseMove(MouseInfo mouse) {
        return false;
    }
}
