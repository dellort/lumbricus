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
        bool refire;
    }

    this(LuaWeaponClass base, Sprite a_owner, GameEngine engine) {
        super(base, a_owner, engine);
        myclass = base;
    }

    override bool activity() {
        return internal_active;
    }

    override protected void doFire(FireInfo info) {
        info.pos = owner.physics.pos;   //?
        //xxx this is probably wrong, but I don't understand the code in worm.d;
        //  but it really looks like doFire is called a second time on the same
        //  shooter object, which actually shouldn't be allowed...
        if (refire) {
            doRefire();
        } else {
            if (myclass.onFire) {
                myclass.onFire(this, info);
            }
        }
        refire = true;
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
}
