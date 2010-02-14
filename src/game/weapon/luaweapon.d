module game.weapon.luaweapon;

import framework.framework;
import game.controller_events;
import game.game;
import game.gfxset;
import game.gobject;
import game.sprite;
import game.weapon.weapon;
import game.weapon.types;
import utils.configfile;
import utils.misc;
import utils.time;

class LuaWeaponClass : WeaponClass {
    void delegate(Shooter, FireInfo) onFire;
    WeaponSelector delegate(Sprite) onCreateSelector;
    void delegate(Shooter, bool) onInterrupt;
    //if you set onRefire, don't forget canRefire
    bool delegate(Shooter) onRefire;
    bool canRefire = false;

    this(GfxSet a_gfx, char[] a_name) {
        super(a_gfx, a_name);
    }

    override WeaponSelector createSelector(Sprite selected_by) {
        if (!onCreateSelector)
            return null;
        return onCreateSelector(selected_by);
    }

    override Shooter createShooter(Sprite go, GameEngine engine) {
        return new LuaShooter(this, go, engine);
    }
}

class LuaShooter : Shooter {
    private {
        LuaWeaponClass myclass;
        bool mIsFixed;
    }

    this(LuaWeaponClass base, Sprite a_owner, GameEngine engine) {
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

    override void interruptFiring(bool outOfAmmo) {
        if (myclass.onInterrupt) {
            myclass.onInterrupt(this, outOfAmmo);
        }
        super.interruptFiring(outOfAmmo);
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
