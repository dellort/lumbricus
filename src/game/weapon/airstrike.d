module game.weapon.airstrike;

import common.animation;
import framework.framework;
import game.action.base;
import game.action.wcontext;
import game.game;
import game.gfxset;
import game.sprite;
import game.temp : JumpMode;
import game.weapon.weapon;
import game.wcontrol;
import game.levelgen.landscape;
import physics.world;
import utils.configfile;
import utils.factory;
import utils.reflection;
import utils.time;
import utils.vector2;
import utils.log;
import utils.misc;
import utils.interpolate;

import math = tango.math.Math;

//draws the arrow mouse cursor, and updates FireInfo with the selected direction
class AirstrikeControl : WeaponSelector, Controllable {
    private {
        GameEngine mEngine;
        GObjectSprite mOwner;
        WormControl mControl;
        InterpolateExp!(float, 3.0f) mIP;  //for rotating the cursor
        int mCurSide;  //index into c...Angles
        //[left to right, right to left]
        const cFireAngles = [40, 140];   //how the strike is fired
        //xxx the animation has a strange rotation
        const cMouseAngles = [230, 310]; //how the cursor animation is rotated
    }

    mixin Methods!("mouseRender");

    this(WeaponClass wc, GObjectSprite a_owner) {
        super(wc, a_owner);
        mOwner = a_owner;
        mEngine = mOwner.engine;

        mControl = mEngine.controller.controlFromGameObject(mOwner, true);
        initIP();
    }

    this (ReflectCtor c) {
        super(c);
        c.transient(this, &mIP);
        if (c.recreateTransient)
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
        ap.p1 = cast(int)mIP.value();
        mControl.color.cursor.draw(c, mousepos, ap, Time.Null);
        return false;
    }

    override bool canFire(ref FireInfo info) {
        //insert throwing direction
        info.dir = Vector2f.fromPolar(1.0f,
            cFireAngles[mCurSide]*math.PI/180.0f);
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
    GObjectSprite getSprite() {
        return null;
    }
    //--- /Controllable

    static this() {
        WeaponSelectorFactory.register!(typeof(this))("airstrike_selector");
    }
}