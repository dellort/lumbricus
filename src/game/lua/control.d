module game.lua.control;

import game.lua.base;
import game.controller;
import game.crate;
import game.gfxset;
import game.weapon.weapon;
import game.worm;
import game.wcontrol;
import game.gamemodes.shared;

static this() {
    gScripting.setClassPrefix!(GameController)("Control");
    gScripting.methods!(GameController, "currentRound",
        "checkDyingWorms", "updateHealth", "needUpdateHealth", "teams",
        "deactivateAll", "addMemberGameObject", "isIdle",
        "memberFromGameObject", "weaponFromGameObject", "controlFromGameObject",
        "dropCrate", "startSuddenDeath", "endGame", "addCrateTool");

    gScripting.setClassPrefix!(TeamMember)("Member");
    gScripting.methods!(TeamMember, "control", "updateHealth",
        "needUpdateHealth", "name", "team", "alive", "currentHealth",
        "health", "sprite", "lifeLost", "addHealth");
    gScripting.properties!(TeamMember, "active");
    gScripting.methods!(Team, "name", "id", "alive", "totalHealth",
        "getMembers", "hasCrateSpy", "hasDoubleDamage", "setOnHold",
        "nextActive","nextWasIdle", "teamAction", "isIdle", "checkDyingMembers",
        "youWinNow", "updateHealth", "needUpdateHealth", "addWeapon",
        "skipTurn", "surrenderTeam", "addDoubleDamage", "addCrateSpy");
    gScripting.properties!(Team, "current", "allowSelect", "globalWins",
        "active", "crateSpy", "doubleDmg");

    gScripting.methods!(WormControl, "isAlive", "sprite", "controlledSprite",
        "setLimitedMode", "weaponUsed", "resetActivity", "lastAction",
        "lastActivity", "actionPerformed", "forceAbort", "pushControllable",
        "releaseControllable");

    gScripting.setClassPrefix!(WormSprite)("Worm");
    gScripting.methods!(WormSprite, "beamTo");

    gScripting.ctor!(WormSpriteClass, GfxSet, char[])();
    gScripting.methods!(WormSpriteClass, "finishLoading", "findState")();
    gScripting.properties!(WormSpriteClass, "jumpStrengthScript",
        "rollVelocity", "ropeImpulse", "suicideDamage")();

    gScripting.properties!(WormStateInfo, "physic", "noleave", "animation",
        "particle", "isGrounded", "canWalk", "canAim", "canFire",
        "onAnimationEnd")();

    gScripting.ctor!(CrateSpriteClass, GfxSet, char[])();
    gScripting.properties!(CrateSpriteClass, "collectRadius");
    gScripting.methods!(CrateSprite, "blowStuffies")();
    gScripting.property_ro!(CrateSprite, "crateType")();

    gScripting.ctor!(TimeStatus)();
    gScripting.properties!(TimeStatus, "showTurnTime", "showGameTime",
        "timePaused", "turnRemaining", "gameRemaining");
    gScripting.ctor!(PrepareStatus)();
    gScripting.properties!(PrepareStatus, "visible", "prepareRemaining");

    //the class has no new members, but Lua gamemmode needs to identify it
    //the wrapper requires at least one method registered for awkward reasons
    gScripting.ctor!(CollectableToolDoubleTime)();
    gScripting.ctor!(CollectableToolCrateSpy)();
    gScripting.ctor!(CollectableToolDoubleDamage)();
    gScripting.ctor!(CollectableWeapon, WeaponClass, int)();
    gScripting.ctor!(CollectableBomb)();
    gScripting.ctor!(CollectableMedkit)();
}
