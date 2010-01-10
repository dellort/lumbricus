module game.lua;

import framework.framework;
import framework.lua;
import utils.timesource;
import game.controller;
import game.events;
import game.game;
import game.gfxset;
import game.gobject;
import game.sprite;
import game.worm;
import game.gamemodes.shared;
import game.levelgen.level;
import game.levelgen.renderer;
import game.weapon.projectile;
import physics.world;
import utils.vector2;
import utils.rect2;
import utils.time;
import utils.random;
import str = utils.string;

public import framework.lua : ScriptingException;

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
    gScripting.methods!(Random, "rangei", "rangef");

    gScripting.setClassPrefix!(GameEngine)("Game");
    gScripting.methods!(GameEngine, "createSprite", "gameTime", "waterOffset",
        "windSpeed", "setWindSpeed", "randomizeWind", "gravity", "raiseWater",
        "addEarthQuake", "explosionAt", "damageLandscape", "landscapeBitmaps",
        "insertIntoLandscape", "countSprites", "ownedTeam");
    gScripting.properties_ro!(GameEngine, "events", "globalEvents");

    gScripting.methods!(LandscapeBitmap, "addPolygon", "drawBorder", "size");

    gScripting.setClassPrefix!(GfxSet)("Gfx");
    gScripting.methods!(GfxSet, "findSpriteClass", "findWeaponClass",
        "weaponList");
    gScripting.method!(GfxSet, "scriptGetRes")("resource");

    gScripting.methods!(Level, "worldCenter");
    gScripting.properties_ro!(Level, "airstrikeAllow", "airstrikeY",
        "worldSize", "landBounds");

    gScripting.setClassPrefix!(GameController)("Control");
    gScripting.methods!(GameController, "getPlugin", "currentRound",
        "checkDyingWorms", "updateHealth", "needUpdateHealth", "teams",
        "activateTeam", "deactivateAll", "addMemberGameObject",
        "memberFromGameObject", "weaponFromGameObject", "controlFromGameObject",
        "dropCrate", "startSuddenDeath", "endGame");

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
    gScripting.methods!(Sprite, "setPos", "pleasedie", "type",
        "activate");
    gScripting.property_ro!(Sprite, "physics");
    gScripting.setClassPrefix!(ProjectileSprite)("Projectile");
    gScripting.property!(ProjectileSprite, "detonateTimer");
    gScripting.setClassPrefix!(WormSprite)("Worm");
    gScripting.methods!(WormSprite, "beamTo");

    gScripting.methods!(SpriteClass, "createSprite", "getEvents");
    gScripting.property_ro!(SpriteClass, "name");

    gScripting.setClassPrefix!(PhysicWorld)("World");

    gScripting.methods!(PhysicWorld, "add", "objectsAtPred");
    gScripting.method!(PhysicWorld, "collideGeometryScript")("collideGeometry");
    gScripting.method!(PhysicWorld, "collideObjectWithGeometryScript")(
        "collideObjectWithGeometry");
    gScripting.method!(PhysicWorld, "shootRayScript")("shootRay");
    gScripting.method!(PhysicWorld, "thickLineScript")("thickLine");
    gScripting.method!(PhysicWorld, "thickRayScript")("thickRay");
    gScripting.method!(PhysicWorld, "freePointScript")("freePoint");

    gScripting.setClassPrefix!(PhysicObject)("Phys");
    gScripting.methods!(PhysicObject, "isGlued", "pos", "velocity",
        "setInitialVelocity", "addForce", "addImpulse", "onSurface",
        "setPos", "move", "forceLook", "resetLook", "lookey", "applyDamage",
        "setWalking", "isWalkingMode", "isWalking");
    gScripting.properties!(PhysicObject, "selfForce", "acceleration");
    gScripting.properties_ro!(PhysicObject, "surface_normal", "lifepower");
    gScripting.setClassPrefix!(PhysicBase)("Phys");
    gScripting.property_ro!(PhysicBase, "backlink");

    gScripting.ctor!(TimeStatus)();
    gScripting.properties!(TimeStatus, "showTurnTime", "showGameTime",
        "timePaused", "turnRemaining", "gameRemaining");
    gScripting.ctor!(PrepareStatus)();
    gScripting.properties!(PrepareStatus, "visible", "prepareRemaining");

    //internal functions
    gScripting.methods!(Events, "enableScriptHandler");
    gScripting.properties_ro!(Events, "scriptingEventsNamespace");
}

//SIGH, do we really need this singleton garbage?
void addSingletons(LuaState state, GameEngine engine) {
    state.addSingleton(engine);
    state.addSingleton(engine.controller);
    state.addSingleton(engine.gfx);
    state.addSingleton(engine.physicworld);
    state.addSingleton(engine.level);
    state.addSingleton(engine.rnd);

    state.scriptExec(`_G["Game"] = ...`, engine);
}

LuaState createScriptingObj(GameEngine engine) {
    auto state = new LuaState(LuaLib.safe);
    state.register(gScripting);

    void loadscript(char[] filename) {
        filename = "lua/" ~ filename;
        auto st = gFS.open(filename);
        scope(exit) st.close();
        state.loadScript(filename, st);
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
    loadscript("events.lua");
    loadscript("timer.lua");

    return state;
}
