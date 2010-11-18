module game.lua.control;

import game.controller;
import game.core;
import game.input;
import game.weapon.weapon;
import game.worm;
import game.wcontrol;
import game.hud.gameteams;
import game.hud.gametimer;
import game.hud.hudbase;
import game.hud.preparedisplay;
import game.lua.base;

static this() {
    gScripting.setClassPrefix!(GameController)("Control");
    gScripting.methods!(GameController, "currentRound",
        "checkDyingWorms", "updateHealth", "needUpdateHealth", "teams",
        "deactivateAll", "isIdle",
        "memberFromGameObject", "weaponFromGameObject", "controlFromGameObject",
        "startSuddenDeath", "endGame");

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
        "releaseControllable", "engaged", "setEngaged", "selectWeapon");

    gScripting.methods!(WormSprite, "beamTo", "freeze");
    gScripting.properties!(WormSprite, "poisoned");

    gScripting.ctor!(WormSpriteClass, GameCore, char[])();
    gScripting.methods!(WormSpriteClass, "finishLoading", "findState")();
    gScripting.properties!(WormSpriteClass, "jumpStrengthScript",
        "rollVelocity", "heavyVelocity", "suicideDamage", "hitParticleDamage",
        "hitParticle", "getupDelay")();

    gScripting.properties!(WormStateInfo, "physic", "noleave", "animation",
        "particle", "isGrounded", "canWalk", "canJump", "canAim", "canFire",
        "onAnimationEnd", "isUnderWater", "activity")();

    gScripting.properties!(HudElement, "visible");

    gScripting.ctor!(HudPrepare, GameCore);
    gScripting.properties!(HudPrepare, "prepareRemaining");

    gScripting.ctor!(HudGameTimer, GameCore);
    gScripting.properties!(HudGameTimer, "showTurnTime", "showGameTime",
        "timePaused", "turnRemaining", "gameRemaining");

    gScripting.ctor!(HudTeams, GameCore);

    /+
    gScripting.ctor!(InputScript)();
    gScripting.properties!(InputScript, "onCheckCommand", "onExecCommand",
        "accessList");
    gScripting.methods!(InputHandler, "enableGroup", "disableGroup",
        "setEnableGroup");
    +/
}
