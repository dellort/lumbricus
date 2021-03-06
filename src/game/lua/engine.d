module game.lua.engine;

import common.resset;
import game.core;
import game.events;
import game.game;
import game.glevel;
import game.particles;
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
        "benchStart");
    gScripting.properties_ro!(GameEngine, "events",
        "benchActive", "scene", "resources", "input");
    gScripting.properties!(GameEngine, "persistentState", "gameLandscapes",
        "enableDebugDraw");

    gScripting.method!(GameEngine, "placeObjectRandomScript")
        ("placeObjectRandom");

    gScripting.methods!(GameCore, "animationEffect");

    gScripting.properties_ro!(GameLandscape, "landscape", "rect");

    gScripting.methods!(LandscapeBitmap, "addPolygon", "drawBorder", "fill",
        "drawSegment", "drawCircle", "drawRect", "size");

    gScripting.methods!(ResourceSet, "addResource", "getDynamic",
        "findAllDynamic");

    gScripting.static_method!(WormLabels, "textCreate");

    gScripting.methods!(Level, "worldCenter");
    gScripting.properties_ro!(Level, "airstrikeAllow", "airstrikeY",
        "worldSize", "landBounds");

    gScripting.methods!(GameObject, "activity", "kill");
    gScripting.property!(GameObject, "createdBy");
    gScripting.property_ro!(GameObject, "objectAlive");

    gScripting.methods!(Sprite, "setPos", "activate", "setParticle");
    gScripting.properties!(Sprite, "graphic", "noActivity",
        "noActivityWhenGlued", "exceedVelocity", "notifyAnimationEnd");
    gScripting.properties_ro!(Sprite, "physics", "isUnderWater", "visible",
        "type");

    gScripting.ctor!(SpriteClass, GameCore, string)();
    gScripting.methods!(SpriteClass, "createSprite", "getInitSequenceState",
        "getInitSequenceType");
    gScripting.property_ro!(SpriteClass, "name");
    gScripting.properties!(SpriteClass, "initialHp", "initPhysic",
        "initParticle", "sequenceType", "sequenceState", "initNoActivity",
        "initNoActivityWhenGlued");

    gScripting.properties_ro!(SequenceState, "owner");

    gScripting.methods!(SequenceType, "findState");

    gScripting.methods!(Sequence, "setState", "queueState");
    gScripting.properties!(Sequence, "attachText", "cameraArrows",
        "positionArrow");
    gScripting.properties_ro!(Sequence, "currentState");

    gScripting.methods!(ParticleWorld, "emitParticle");

    //internal functions
    gScripting.properties_ro!(EventTarget, "eventTargetType");
    gScripting.methods!(Events, "scriptGetMarshallers", "perClassEvents");
    gScripting.properties_ro!(Events, "globalDummy");
}
