module game.temp;

//enum dumping ground...
//http://d.puremagic.com/issues/show_bug.cgi?id=1160

///which style a worm should jump
enum JumpMode {
    normal,      ///standard forward jump (return)
    smallBack,   ///little backwards jump (double return)
    backFlip,    ///large backwards jump/flip (double backspace)
    straightUp,  ///jump straight up (backspace)
}

enum CrateType {
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
    Objects,
    FrontObjects,
    Names,       //stuff drawn by gameview.d
    Crosshair,
    Effects, //whatw as that
    Particles,
    Clouds,
    FrontWater,
    RangeArrow,  //object-off-level-area arrow
    Splat,   //Fullscreen effect
}
