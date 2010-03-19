module game.temp;

//enum dumping ground...
//http://d.puremagic.com/issues/show_bug.cgi?id=1160

///which style a worm should jump
//keep in sync with worm.lua
enum JumpMode {
    normal,      ///standard forward jump (return)
    smallBack,   ///little backwards jump (double return)
    backFlip,    ///large backwards jump/flip (double backspace)
    straightUp,  ///jump straight up (backspace)
}

//keep in sync with Lua
enum CrateType {
    unknown,
    weapon,
    med,
    tool,
}

enum GameZOrder {
    Invisible = 0,
    Background,
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
