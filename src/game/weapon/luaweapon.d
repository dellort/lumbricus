module game.weapon.luaweapon;

import framework.framework;
import game.animation;
import game.action;
import game.actionsprite;
import game.game;
import game.gobject;
import game.sprite;
import game.sequence;
import game.weapon.weapon;
import game.weapon.projectile;
import lua.all;
import physics.world;
import utils.array;
import utils.misc;
import utils.mybox;
import utils.vector2;
import utils.configfile;
import utils.log;
import utils.factory;
import utils.reflection;



class LuaWeapon : WeaponClass {
    //precompiled script code
    ubyte[] scriptCode;

    //xxx class
    this (ReflectCtor c) {
        super(c);
    }

    this(GameEngine aengine, ConfigNode node) {
        super(aengine, node);
        //load and compile the script, so loading is faster later
        //  (well, I hope so)
        scope L = new LuaState(
            (char[] msg) { gDefaultOutput.writefln("{}", msg); });
        L.load(node.getStringValue("script"), "LuaWeaponScript");
        scriptCode = cast(ubyte[])L.dump();
        L.pop();
    }

    LuaShooter createShooter(GObjectSprite go) {
        return new LuaShooter(this, go, mEngine);
    }

    static this() {
        WeaponClassFactory.register!(typeof(this))("lua");
    }
}

class LuaShooter : Shooter, ProjectileFeedback {
    private {
        LuaWeapon myclass;
        LuaState mScript;
    }

    this(LuaWeapon base, GObjectSprite a_owner, GameEngine engine) {
        super(base, a_owner, engine);
        myclass = base;
        mScript = new LuaState(
            (char[] msg) { gDefaultOutput.writefln("{}", msg); });
        mScript.doString(true, cast(char[])myclass.scriptCode);
    }
    this (ReflectCtor c) {
        super(c);
    }

    override bool activity() {
        return false;
    }

    override bool delayedAction() {
        return false;
    }

    //interface ProjectileFeedback.addSprite
    void addRefire(ProjectileSprite s) {
        //mRefireSprites ~= s;
    }

    void removeRefire(ProjectileSprite s) {
        //arrayRemoveUnordered(mRefireSprites, s, true);
        //if (!activity)
            //all possible refire sprites died by themselves
        //    finished();
    }

    override void readjust(Vector2f dir) {
    }

    override protected void doFire(FireInfo info) {
    }

    override protected bool doRefire() {
        return false;
    }

    override bool isFixed() {
        return super.isFixed();
    }

    override void interruptFiring() {
    }
}
