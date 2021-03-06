module game.lua.weapon;

import game.lua.base;
import game.core;
import game.controller;
import game.sprite;
import game.weapon.spawn;
import game.weapon.helpers;
import game.weapon.airstrike;
import game.weapon.drill;
import game.weapon.girder;
import game.weapon.jetpack;
import game.weapon.luaweapon;
import game.weapon.napalm;
import game.weapon.parachute;
import game.weapon.rope;
import game.weapon.weapon;
import game.weapon.weaponset;
import utils.color;
import utils.time;
import utils.vector2;

static this() {
    gScripting.properties!(WeaponClass, "value", "category", "isAirstrike",
        "allowSecondary", "dontEndRound", "deselectAfterFire",
        "cooldown", "crateAmount", "icon", "fireMode", "animation",
        "prepareParticle", "fireParticle");
    gScripting.properties_ro!(WeaponClass, "name");

    gScripting.methods!(Shooter, "finished", "reduceAmmo");
    gScripting.properties!(Shooter, "owner", "fireinfo", "selector");
    gScripting.func!(gameObjectFindShooter)();

    gScripting.methods!(WeaponSet, "addWeapon", "canUseWeapon",
        "decreaseWeapon");
    gScripting.method!(WeaponSet, "iterate2")("iterate");

    //------- specific weapons implemented in D

    gScripting.func!(spawnSprite)();
    gScripting.func!(spawnFromFireInfo)();
    //gScripting.func!(spawnFromShooter)();
    gScripting.func!(spawnAirstrike)();
    gScripting.func!(spawnCluster)();

    gScripting.ctor!(GirderControl, Sprite);
    gScripting.methods!(GirderControl, "fireCheck");

    gScripting.ctor!(AirstrikeControl, Sprite);

    gScripting.ctor!(DrillClass, GameCore, string);
    gScripting.properties!(DrillClass, "duration", "tunnelRadius", "interval",
        "blowtorch");

    gScripting.ctor!(ParachuteClass, GameCore, string);
    gScripting.properties!(ParachuteClass, "sideForce");

    gScripting.ctor!(JetpackClass, GameCore, string);
    gScripting.properties!(JetpackClass, "maxTime", "jetpackThrust",
        "stopOnDisable");

    gScripting.ctor!(RopeClass, GameCore, string);
    gScripting.properties!(RopeClass, "shootSpeed", "maxLength", "moveSpeed",
        "swingForce", "swingForceUp", "hitImpulse", "ropeColor", "ropeSegment",
        "anchorAnim", "impactParticle");

    gScripting.ctor!(NapalmSpriteClass, GameCore, string);
    gScripting.properties!(NapalmSpriteClass, "damage", "initialDelay",
        "repeatDelay", "decayTime", "physMedium", "physSmall",
        "lightupVelocity", "emitOnWater", "sticky", "decaySteps");
    gScripting.methods!(NapalmSpriteClass, "stepDecay");

    gScripting.ctor!(StuckTrigger, Sprite, Time, float, bool)();
    gScripting.properties!(StuckTrigger, "onTrigger");

    gScripting.ctor!(ControlRotate, Sprite, float, float)();
    gScripting.properties!(ControlRotate, "direction");

    gScripting.ctor!(RenderLaser, GameCore, Vector2f, Vector2f, Time,
        Color[]);

    //-----

    gScripting.ctor!(LuaWeaponClass, GameCore, string)();
    gScripting.properties!(LuaWeaponClass, "onFire",
        "onCreateSelector", "onInterrupt", "onRefire", "onReadjust");
    gScripting.properties!(LuaShooter, "fixed", "delayed");
}
