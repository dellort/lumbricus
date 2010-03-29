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
    //if you set onRefire, don't forget canRefire
    bool delegate(Shooter) onRefire;
    bool canRefire = false;
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
        return new LuaShooter(this, go, go.engine);
    }
}

class LuaShooter : Shooter {
    private {
        LuaWeaponClass myclass;
        bool mIsFixed;
    }

    this(LuaWeaponClass base, Sprite a_owner, GameCore engine) {
        super(base, a_owner, engine);
        myclass = base;
    }

    override bool activity() {
        return internal_active;
    }

    override protected void doFire(FireInfo info) {
        //xxx although simulate() is unused, we need this for the activity check
        internal_active = true;
        mIsFixed = false;
        info.pos = owner.physics.pos;   //?
        if (myclass.onFire) {
            myclass.onFire(this, info);
        }
    }

    override bool doRefire() {
        if (!(myclass.canRefire && myclass.onRefire))
            return false;
        return myclass.onRefire(this);
    }

    override void readjust(Vector2f dir) {
        super.readjust(dir);
        if (myclass.onReadjust) {
            myclass.onReadjust(this, dir);
        }
    }

    override void interruptFiring() {
        if (myclass.onInterrupt) {
            myclass.onInterrupt(this);
        }
        //No! will be handled by finished()
        //  super.interruptFiring(outOfAmmo);
    }

    override bool isFixed() {
        return activity && mIsFixed;
    }
    void isFixed(bool fix) {
        mIsFixed = fix;
    }

    //xxx I don't know if it's always correct to link this to isFixed
    override bool delayedAction() {
        return activity && mIsFixed;
    }
}
