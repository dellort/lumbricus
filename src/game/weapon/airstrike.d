module game.weapon.airstrike;

import framework.drawing;
import common.animation;
import game.controller;
import game.sprite;
import game.weapon.weapon;
import game.wcontrol;
import physics.all;
import utils.time;
import utils.vector2;
import utils.misc;
import utils.interpolate;

import game.worm; //for JumpMode
import std.math;

//draws the arrow mouse cursor, and updates FireInfo with the selected direction
class AirstrikeControl : WeaponSelector, Controllable {
    private {
        Sprite mOwner;
        WormControl mControl;
        InterpolateExp!(float, 3.0f) mIP;  //for rotating the cursor
        int mCurSide;  //index into c...Angles
        //[left to right, right to left]
        enum cFireAngles = [40, 140];   //how the strike is fired
        //xxx the animation has a strange rotation
        enum cMouseAngles = [230, 310]; //how the cursor animation is rotated
    }

    this(Sprite a_owner) {
        super(a_owner);
        mOwner = a_owner;

        auto controller = mOwner.engine.singleton!(GameController)();

        mControl = controller.controlFromGameObject(mOwner, true);
        initIP();
    }

    private void initIP() {
        mIP.init_done(timeMsecs(350), cMouseAngles[1 - mCurSide],
            cMouseAngles[mCurSide]);
    }

    override void onSelect() {
        mControl.pushControllable(this);
        mControl.addRenderOnMouse(&mouseRender);
    }

    override void onUnselect() {
        mControl.removeRenderOnMouse(&mouseRender);
        mControl.releaseControllable(this);
    }

    bool mouseRender(Canvas c, Vector2i mousepos) {
        AnimationParams ap;
        ap.p[0] = cast(int)mIP.value();
        mControl.color.cursor.draw(c, mousepos, ap, Time.Null);
        return false;
    }

    override bool canFire(ref FireInfo info) {
        //insert throwing direction
        info.dir = Vector2f.fromPolar(1.0f,
            cFireAngles[mCurSide]*PI/180.0f);
        return true;
    }

    //0: coming in from left to right; 1: from right to left
    private void setOrientation(int o) {
        mCurSide = o;
        mIP.setParams(cMouseAngles[1 - mCurSide], cMouseAngles[mCurSide]);
    }

    //--- Controllable
    bool fire(bool keyDown) {
        return false;
    }
    bool jump(JumpMode j) {
        return false;
    }
    bool move(Vector2f m) {
        if (m.x > 0) {
            setOrientation(0);
        } else if (m.x < 0) {
            setOrientation(1);
        } else {
            return false;
        }
        return true;
    }
    Sprite getSprite() {
        return null;
    }
    //--- /Controllable
}
