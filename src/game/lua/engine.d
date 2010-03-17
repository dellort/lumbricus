module game.lua.engine;

import game.lua.base;
import game.events;
import game.game;
import game.gfxset;
import game.glevel;
import game.gobject;
import game.sequence;
import game.sprite;
import game.levelgen.level;
import game.levelgen.renderer;

static this() {
    gScripting.setClassPrefix!(GameEngine)("Game");
    gScripting.methods!(GameEngine, "createSprite", "gameTime", "waterOffset",
        "windSpeed", "setWindSpeed", "randomizeWind", "gravity", "raiseWater",
        "addEarthQuake", "explosionAt", "damageLandscape",
        "insertIntoLandscape", "countSprites", "ownedTeam", "nukeSplatEffect",
        "checkForActivity", "gameObjectFirst", "gameObjectNext",
        "debug_pickObject", "benchStart");
    gScripting.properties_ro!(GameEngine, "events", "globalEvents",
        "benchActive");
    gScripting.properties!(GameEngine, "persistentState", "gameLandscapes",
        "scene");

    gScripting.properties_ro!(GameLandscape, "landscape", "rect");

    gScripting.methods!(LandscapeBitmap, "addPolygon", "drawBorder", "size");

    gScripting.setClassPrefix!(GfxSet)("Gfx");
    gScripting.methods!(GfxSet, "findSpriteClass", "findWeaponClass",
        "weaponList", "registerWeapon", "registerSpriteClass",
        "findSequenceState");
    gScripting.static_method!(GfxSet, "textCreate");
    gScripting.method!(GfxSet, "scriptGetRes")("resource");

    gScripting.methods!(Level, "worldCenter");
    gScripting.properties_ro!(Level, "airstrikeAllow", "airstrikeY",
        "worldSize", "landBounds");

    gScripting.methods!(GameObject, "activity", "kill");
    gScripting.property!(GameObject, "createdBy");
    gScripting.property_ro!(GameObject, "objectAlive");

    gScripting.methods!(Sprite, "setPos", "type", "activate", "setParticle");
    gScripting.properties!(Sprite, "graphic", "noActivityWhenGlued",
        "exceedVelocity", "notifyAnimationEnd");
    gScripting.properties_ro!(Sprite, "physics", "isUnderWater", "visible");

    gScripting.ctor!(SpriteClass, GfxSet, char[])();
    gScripting.methods!(SpriteClass, "createSprite", "getInitSequenceState",
        "getInitSequenceType", "loadFromConfig" /+ <- worm.conf +/);
    gScripting.property_ro!(SpriteClass, "name");
    gScripting.properties!(SpriteClass, "initialHp", "initPhysic",
        "initParticle", "sequenceType", "sequenceState",
        "initNoActivityWhenGlued");

    gScripting.properties_ro!(SequenceState, "owner");

    gScripting.methods!(SequenceType, "findState");

    gScripting.methods!(Sequence, "setState", "queueState");
    gScripting.properties!(Sequence, "attachText");
    gScripting.properties_ro!(Sequence, "currentState");

    //internal functions
    gScripting.properties_ro!(EventTarget, "eventTargetType");
    gScripting.methods!(Events, "enableScriptHandler", "perClassEvents");
    gScripting.properties_ro!(Events, "scriptingEventsNamespace");
}
