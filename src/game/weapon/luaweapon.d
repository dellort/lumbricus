module game.weapon.luaweapon;

import framework.framework;
import game.core;
import game.sprite;
import game.weapon.weapon;
import game.weapon.types;
import utils.misc;
import utils.time;

class LuaWeaponClass : WeaponClass {
    void delegate(Shooter, FireInfo) onFire;
    WeaponSelector delegate(Sprite) onCreateSelector;
    void delegate(Shooter) onInterrupt;
    bool delegate(Shooter) onRefire;
    void delegate(Shooter, Vector2f) onReadjust;

    this(GameCore a_engine, char[] a_name) {
        super(a_engine, a_name);
    }

    override WeaponSelector createSelector(Sprite selected_by) {
        if (!onCreateSelector)
            return null;
        return onCreateSelector(selected_by);
    }

    override Shooter createShooter(Sprite go) {
        return new LuaShooter(this, go);
    }
}

class LuaShooter : Shooter {
    private {
        LuaWeaponClass myclass;
        bool mIsFixed, mIsDelayed;
    }

    this(LuaWeaponClass base, Sprite a_owner) {
        super(base, a_owner);
        myclass = base;
    }

    override protected void doFire() {
        mIsFixed = false;
        fireinfo.pos = owner.physics.pos;   //?
        if (myclass.onFire) {
            myclass.onFire(this, fireinfo);
        }
    }

    override bool doRefire() {
        if (!myclass.onRefire)
            return false;
        return myclass.onRefire(this);
    }

    override void doReadjust(Vector2f dir) {
        super.doReadjust(dir);
        if (myclass.onReadjust) {
            myclass.onReadjust(this, dir);
        }
    }

    override protected void onInterrupt() {
        if (myclass.onInterrupt)
            myclass.onInterrupt(this);
    }

    override bool isFixed() {
        return activity && mIsFixed;
    }
    void setFixed(bool fix, bool delayed = true) {
        mIsFixed = fix;
        mIsDelayed = delayed;
    }

    //xxx I don't know if it's always correct to link this to isFixed
    override bool delayedAction() {
        return activity && (currentState != WeaponState.fire || mIsDelayed);
    }
}
