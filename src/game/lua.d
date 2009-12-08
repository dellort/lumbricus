module game.lua;

import framework.framework;
import framework.lua;
import framework.timesource;
import game.game;
import game.gfxset;
import game.controller;
import game.gobject;
import game.sprite;
import game.worm;
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
    gScripting.setClassPrefix!(WormSprite)("Worm");
    gScripting.methods!(WormSprite, "beamTo");

    gScripting.setClassPrefix!(PhysicWorld)("World");
    //xxx loads of functions with ref/out parameters, need special handling
    //    (maybe use multiple return values, but how?)
    //might help for ref-param detection:
    //  http://h3.team0xf.com/Bind.d (template at line 1084)
    //no way to distinguish ref and out params (except if you parse .stringof
    //  results or so; which would be incredibly dirty, evil and unethical)
    //maybe it would be better to create separate functions suited for scripting
    //  and use introduce marked structs, that expand into tuple returns?
    //  (e.g. struct Foo { const cTupleReturn = true; int x1; float x2; })
    //xxx ok, I implemented the struct hack above
    /+
    another way would be to use tuples:
        //this type is not the same as tango.core.Tuple.Tuple (lol.)
        struct Tuple(T...) {
            T whatever;
        }
        //can define the return type inline; no separate struct
        Tuple!(int, char[]) bla() {
            ...
            return Tuple!(int, char[])(123, "abc");
        }
    to support nil returns for Lua, one could introduce this bloaty stuff:
        struct Nullable(T) {
            T _value;
            bool isNull = true;
            T value() {
                assert(!isNull);
                return _value;
            }
            const Nullable!(T) Null;
            typeof(this) opCall(T v) {
                typeof(this) res;
                res._value = v;
                res.isNull = false;
                return res;
            }
        }
    and then have the marshaller template handle it
    one could also introduce a multiple choice type to avoid numReturnValues:
        struct Choice(T...) {
            bool isChosen!(Choice)() { ... }
            static typeof(this) Make(Choice)(Choice value) { ... }
        }
    then Nullable(T) would be something like:
        struct Null {} //dummy type to mark null value
        template(T) {
            alias Choice!(Null, T) Nullable;
        }
    +/
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
}

LuaState createScriptingObj(GameEngine engine) {
    auto state = new LuaState(LuaLib.safe);
    state.register(gScripting);
    state.addSingleton(engine);
    state.addSingleton(engine.controller);
    state.addSingleton(engine.gfx);
    state.addSingleton(engine.physicworld);
    state.addSingleton(engine.level);
    state.addSingleton(engine.rnd);

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

    return state;
}
