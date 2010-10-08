module game.temp;

//No game. imports here!
import utils.misc;
import utils.time;

//enum dumping ground...
//http://d.puremagic.com/issues/show_bug.cgi?id=1160

enum GameZOrder {
    Invisible = 0,
    Background,
    Stars,
    BackLayer,
    BackWater,
    Landscape,
    LevelWater,  //water before the level, but behind drowning objects
    Particles,
    Objects,
    FrontObjects,
    Names,       //stuff drawn by gameview.d
    Crosshair,
    Effects, //whatw as that
    Clouds,
    FrontWater,
    RangeArrow,  //object-off-level-area arrow
    Splat,   //Fullscreen effect
}

//... and dumping ground for client/server shared stuff

//fixed framerate for the game logic (all of GameEngine)
//also check physic frame length cPhysTimeStepMs in world.d
const Time cFrameLength = timeMsecs(20);

//see GameShell.engineHash()
//type of hash might be changed in the future
//special case: if the struct is EngineHash.init, the hash is invalid
struct EngineHash {
    uint hash;

    char[] toString() {
        return myformat("0x{:x}", hash);
    }
}

