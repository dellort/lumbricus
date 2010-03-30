module game.lua.engine;

import common.resset;
import game.core;
import game.events;
import game.game;
import game.glevel;
import game.sequence;
import game.sprite;
import game.teamtheme;
import game.levelgen.level;
import game.levelgen.renderer;
import game.lua.base;

static this() {
    gScripting.setClassPrefix!(GameEngine)("Game");
    gScripting.setClassPrefix!(GameCore)("Game");

    gScripting.methods!(GameEngine, "gameTime", "waterOffset",
        "windSpeed", "setWindSpeed", "randomizeWind", "raiseWater",
        "addEarthQuake", "explosionAt", "damageLandscape",
        "insertIntoLandscape", "countSprites", "nukeSplatEffect",
        "checkForActivity", "gameObjectFirst", "gameObjectNext",
        "debug_pickObject", "benchStart", "activityDebug");
    gScripting.properties_ro!(GameEngine, "events", "globalEvents",
        "benchActive", "scene", "resources");
    gScripting.properties!(GameEngine, "persistentState", "gameLandscapes");

    gScripting.methods!(GameCore, "animationEffect");

    gScripting.properties_ro!(GameLandscape, "landscape", "rect");

    gScripting.methods!(LandscapeBitmap, "addPolygon", "drawBorder", "size");

    gScripting.methods!(ResourceSet, "addResource", "getDynamic",
        "findAllDynamic");

    gScripting.static_method!(WormLabels, "textCreate");

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

    gScripting.ctor!(SpriteClass, GameCore, char[])();
    gScripting.methods!(SpriteClass, "createSprite", "getInitSequenceState",
        "getInitSequenceType");
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
