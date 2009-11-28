module game.lua;

import framework.framework;
import framework.lua;
import framework.timesource;
import game.game;
import game.gfxset;
import game.controller;
import game.gobject;
import game.sprite;
import game.levelgen.level;
import game.weapon.projectile;
import physics.world;
import utils.vector2;
import utils.rect2;
import utils.time;
import str = utils.string;

LuaRegistry gScripting;

char[] className(Object o) {
    char[] ret = o.classinfo.name;
    return ret[str.rfind(ret, '.')+1..$];
}

char[] fullClassName(Object o) {
    return o.classinfo.name;
}

static this() {
    gScripting = new typeof(gScripting)();
    gScripting.func!(className);
    gScripting.func!(fullClassName);

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
    gScripting.methods!(Level, "worldCenter");
    gScripting.property_ro!(Level, "airstrikeAllow");
    gScripting.property_ro!(Level, "airstrikeY");

    gScripting.setClassPrefix!(GameController)("Control");
    gScripting.methods!(GameController, "getPlugin", "currentRound",
        "checkDyingWorms", "updateHealth", "needUpdateHealth", "teams",
        "activateTeam", "deactivateAll", "addMemberGameObject",
        "memberFromGameObject", "weaponFromGameObject", "controlFromGameObject",
        "dropCrate", "startSuddenDeath");

    gScripting.setClassPrefix!(TeamMember)("Member");
    gScripting.methods!(TeamMember, "control", "updateHealth",
        "needUpdateHealth", "name", "team", "active", "alive", "currentHealth",
        "health", "sprite", "lifeLost", "addHealth", "setActive");
    gScripting.methods!(Team, "name", "id", "alive", "active", "totalHealth",
        "getMembers", "hasCrateSpy", "hasDoubleDamage", "setOnHold",
        "nextActive", "teamAction", "isIdle", "checkDyingMembers",
        "youWinNow", "updateHealth", "needUpdateHealth", "addWeapon",
        "skipTurn", "surrenderTeam", "addDoubleDamage", "addCrateSpy");
    gScripting.properties!(Team, "current", "allowSelect", "globalWins");

    gScripting.setClassPrefix!(GameObject)("Obj");
    gScripting.methods!(GameObject, "activity");
    gScripting.property!(GameObject, "createdBy");
    gScripting.setClassPrefix!(GObjectSprite)("Sprite");
    gScripting.methods!(GObjectSprite, "setPos", "pleasedie", "type",
        "activate");
    gScripting.property_ro!(GObjectSprite, "physics");
    gScripting.setClassPrefix!(ProjectileSprite)("Projectile");
    gScripting.property!(ProjectileSprite, "detonateTimer");

    gScripting.setClassPrefix!(PhysicWorld)("World");
    //xxx loads of functions with ref/out parameters, need special handling
    //    (maybe use multiple return values, but how?)
    gScripting.methods!(PhysicWorld, "objectsAtPred");
    gScripting.setClassPrefix!(PhysicObject)("Phys");
    gScripting.methods!(PhysicObject, "isGlued", "pos", "velocity",
        "setInitialVelocity", "addForce", "addImpulse", "onSurface",
        "setPos", "move", "forceLook", "resetLook", "lookey", "applyDamage",
        "setWalking", "isWalkingMode", "isWalking");
    gScripting.property!(PhysicObject, "selfForce");
    gScripting.property!(PhysicObject, "acceleration");
    gScripting.property_ro!(PhysicObject, "surface_normal");
    gScripting.property_ro!(PhysicObject, "lifepower");
}

LuaState createScriptingObj(GameEngine engine) {
    auto state = new LuaState(LuaLib.safe);
    state.register(gScripting);
    state.addSingleton(engine);
    state.addSingleton(engine.controller);
    state.addSingleton(engine.gfx);
    state.addSingleton(engine.physicworld);
    state.addSingleton(engine.level);

    void loadscript(char[] filename) {
        filename = "lua/" ~ filename;
        auto st = gFS.open(filename);
        scope(exit) st.close();
        state.loadScript(filename, cast(char[])st.readAll());
    }

    loadscript("vector2.lua");
    state.addScriptType!(Vector2i)("Vector2");
    state.addScriptType!(Vector2f)("Vector2");
    loadscript("rect2.lua");
    state.addScriptType!(Rect2i)("Rect2");
    state.addScriptType!(Rect2f)("Rect2");
    loadscript("time.lua");
    state.addScriptType!(Time)("Time");

    loadscript("utils.lua");
    loadscript("gameutils.lua");

    return state;
}
