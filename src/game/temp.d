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
