module game.temp;

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
