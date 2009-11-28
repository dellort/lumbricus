module game.lua;

import framework.framework;
import framework.lua;
import framework.timesource;
import game.game;
import game.gfxset;
import game.controller;
import game.sprite;
import utils.vector2;
import utils.time;

LuaRegistry gScripting;

static this() {
    gScripting = new typeof(gScripting)();
    gScripting.setClassPrefix!(TimeSourcePublic)("Time");
    gScripting.methods!(TimeSourcePublic, "current", "difference");
    gScripting.setClassPrefix!(GameEngine)("Game");
    gScripting.methods!(GameEngine, "createSprite", "gameTime", "waterOffset",
        "windSpeed", "setWindSpeed", "randomizeWind", "gravity", "raiseWater",
        "addEarthQuake", "explosionAt", "damageLandscape",
        "insertIntoLandscape", "countSprites", "ownedTeam");
    gScripting.setClassPrefix!(GfxSet)("Gfx");
    gScripting.methods!(GfxSet, "findSpriteClass", "findWeaponClass",
        "weaponList");
    gScripting.setClassPrefix!(GameController)("Control");
    gScripting.methods!(GameController, "getPlugin", "currentRound",
        "checkDyingWorms", "updateHealth", "needUpdateHealth", "teams",
        "activateTeam", "deactivateAll", "addMemberGameObject",
        "memberFromGameObject", "weaponFromGameObject", "controlFromGameObject",
        "dropCrate", "startSuddenDeath");
    gScripting.methods!(TeamMember, "control", "updateHealth",
        "needUpdateHealth", "name", "team", "active", "alive", "currentHealth",
        "health", "sprite", "lifeLost", "addHealth", "setActive");
    gScripting.methods!(Team, "name", "id", "alive", "active", "totalHealth",
        "getMembers", "hasCrateSpy", "hasDoubleDamage", "setOnHold",
        "nextActive", "teamAction", "isIdle", "checkDyingMembers",
        "youWinNow", "updateHealth", "needUpdateHealth", "addWeapon",
        "skipTurn", "surrenderTeam", "addDoubleDamage", "addCrateSpy",
        "getActiveMember");
    gScripting.setClassPrefix!(GObjectSprite)("Sprite");
    gScripting.methods!(GObjectSprite, "setPos", "pleasedie", "activity",
        "type");
}

LuaState createScriptingObj(GameEngine engine) {
    auto state = new LuaState(LuaLib.safe);
    state.register(gScripting);
    state.addSingleton(engine);
    state.addSingleton(engine.controller);
    state.addSingleton(engine.gfx);

    void loadscript(char[] filename) {
        filename = "lua/" ~ filename;
        auto st = gFS.open(filename);
        scope(exit) st.close();
        state.luaLoadAndPush(filename, cast(char[])st.readAll());
        state.luaCall!(void)();
    }

    loadscript("vector2.lua");
    state.addScriptType!(Vector2i)("Vector2");
    state.addScriptType!(Vector2f)("Vector2");
    loadscript("time.lua");
    state.addScriptType!(Time)("Time");

    loadscript("utils.lua");

    return state;
}
