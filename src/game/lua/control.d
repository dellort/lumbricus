module game.lua.control;

import game.lua.base;
import game.controller;
import game.core;
import game.crate;
import game.input;
import game.weapon.weapon;
import game.worm;
import game.wcontrol;
import game.gamemodes.shared;

static this() {
    gScripting.setClassPrefix!(GameController)("Control");
    gScripting.methods!(GameController, "currentRound",
        "checkDyingWorms", "updateHealth", "needUpdateHealth", "teams",
        "deactivateAll", "isIdle",
        "memberFromGameObject", "weaponFromGameObject", "controlFromGameObject",
        "dropCrate", "startSuddenDeath", "endGame", "addCrateTool");

    gScripting.setClassPrefix!(TeamMember)("Member");
    gScripting.methods!(TeamMember, "updateHealth", "lifeLost", "addHealth");
    gScripting.property_ro!(TeamMember, "active");
    gScripting.properties_ro!(TeamMember, "control", "name", "team", "alive",
        "needUpdateHealth", "currentHealth", "health", "sprite");
    gScripting.methods!(Team, "setOnHold", "nextWasIdle", "checkDyingMembers",
        "youWinNow", "updateHealth", "needUpdateHealth", "addWeapon",
        "skipTurn", "surrenderTeam", "addDoubleDamage", "addCrateSpy");
    gScripting.properties!(Team, "current", "allowSelect", "globalWins",
        "active", "crateSpy", "doubleDmg");
    gScripting.properties_ro!(Team, "weapons", "theme", "name", "id", "alive",
        "totalHealth", "members", "hasCrateSpy", "hasDoubleDamage",
        "nextActive", "teamAction", "isIdle");

    gScripting.methods!(WormControl, "isAlive", "sprite", "controlledSprite",
        "setLimitedMode", "weaponUsed", "resetActivity", "lastAction",
        "lastActivity", "actionPerformed", "forceAbort", "pushControllable",
        "releaseControllable", "engaged", "setEngaged");

    gScripting.setClassPrefix!(WormSprite)("Worm");
    gScripting.methods!(WormSprite, "beamTo", "freeze");

    gScripting.ctor!(WormSpriteClass, GameCore, char[])();
    gScripting.methods!(WormSpriteClass, "finishLoading", "findState")();
    gScripting.properties!(WormSpriteClass, "jumpStrengthScript",
        "rollVelocity", "ropeImpulse", "suicideDamage")();

    gScripting.properties!(WormStateInfo, "physic", "noleave", "animation",
        "particle", "isGrounded", "canWalk", "canAim", "canFire",
        "onAnimationEnd", "isUnderWater")();

    gScripting.ctor!(CrateSpriteClass, GameCore, char[])();
    gScripting.properties!(CrateSpriteClass, "collectRadius");
    gScripting.methods!(CrateSprite, "blowStuffies")();
    gScripting.property_ro!(CrateSprite, "crateType")();

    gScripting.ctor!(TimeStatus)();
    gScripting.properties!(TimeStatus, "showTurnTime", "showGameTime",
        "timePaused", "turnRemaining", "gameRemaining");
    gScripting.ctor!(PrepareStatus)();
    gScripting.properties!(PrepareStatus, "visible", "prepareRemaining");

    gScripting.ctor!(CollectableTool, char[])();
    gScripting.ctor!(CollectableWeapon, WeaponClass, int)();
    gScripting.ctor!(CollectableBomb)();
    gScripting.ctor!(CollectableMedkit)();

    /+
    gScripting.ctor!(InputScript)();
    gScripting.properties!(InputScript, "onCheckCommand", "onExecCommand",
        "accessList");
    gScripting.methods!(InputHandler, "enableGroup", "disableGroup",
        "setEnableGroup");
    +/
}
