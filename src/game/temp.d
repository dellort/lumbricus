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

///tells if and what kinds of weapons can be used (draw, aim, fire)
enum WeaponMode {
    none,        ///no use of weapons possible
                 ///(falling, retreating after fire, ...)
    full,        ///full weapon set available
    secondary,   ///limited weapon set (jetpack-flying, ...)
}

enum CrateType {
    weapon,
    med,
    tool,
}
