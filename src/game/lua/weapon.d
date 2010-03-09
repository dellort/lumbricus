module game.lua.weapon;

import game.lua.base;
import game.game;
import game.controller;
import game.gfxset;
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
import utils.color;
import utils.time;
import utils.vector2;

static this() {
    gScripting.properties!(WeaponClass, "value", "category", "isAirstrike",
        "allowSecondary", "dontEndRound", "deselectAfterFire",
        "cooldown", "crateAmount", "icon", "fireMode", "animation");
    gScripting.properties_ro!(WeaponClass, "name");

    gScripting.methods!(Shooter, "finished", "reduceAmmo");
    gScripting.properties!(Shooter, "selector", "owner", "fireinfo");
    gScripting.func!(gameObjectFindShooter)();

    //------- specific weapons implemented in D

    gScripting.func!(spawnAirstrike)();
    gScripting.func!(spawnCluster)();

    gScripting.ctor!(GirderControl, Sprite);
    gScripting.methods!(GirderControl, "fireCheck");

    gScripting.ctor!(AirstrikeControl, Sprite);

    gScripting.ctor!(DrillClass, GfxSet, char[]);
    gScripting.properties!(DrillClass, "duration", "tunnelRadius", "interval",
        "blowtorch");

    gScripting.ctor!(ParachuteClass, GfxSet, char[]);
    gScripting.properties!(ParachuteClass, "sideForce");

    gScripting.ctor!(JetpackClass, GfxSet, char[]);
    gScripting.properties!(JetpackClass, "maxTime", "jetpackThrust",
        "stopOnDisable");

    gScripting.ctor!(RopeClass, GfxSet, char[]);
    gScripting.properties!(RopeClass, "shootSpeed", "maxLength", "moveSpeed",
        "swingForce", "swingForceUp", "ropeColor", "ropeSegment", "anchorAnim");

    gScripting.ctor!(WormSelectHelper, GameEngine, TeamMember);

    gScripting.ctor!(NapalmSpriteClass, GfxSet, char[]);
    gScripting.properties!(NapalmSpriteClass, "damage", "initialDelay",
        "repeatDelay", "decayTime", "physMedium", "physSmall",
        "lightupVelocity", "emitOnWater");

    gScripting.ctor!(StuckTrigger, Sprite, Time, float, bool)();
    gScripting.properties!(StuckTrigger, "onTrigger");

    gScripting.ctor!(ControlRotate, Sprite, float, float)();
    gScripting.properties!(ControlRotate, "direction");

    gScripting.ctor!(RenderLaser, GameEngine, Vector2f, Vector2f, Time,
        Color[]);

    //-----

    gScripting.ctor!(LuaWeaponClass, GfxSet, char[])();
    gScripting.properties!(LuaWeaponClass, "onFire",
        "onCreateSelector", "onInterrupt", "onRefire", "canRefire",
        "onReadjust");
    gScripting.properties!(LuaShooter, "isFixed");
}
