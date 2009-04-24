module game.temp;

//enum dumping ground...
//http://d.puremagic.com/issues/show_bug.cgi?id=1160

///random infos for animation
enum WormAniState {
//xxx: no "stand" state? i.e. when it's _not_ walking
    walk,           ///worm is on the ground and could walk normally
    jetpackFly,     ///flying a jetpack
    //swing,          ///hanging on a rope
    //floating,       ///floating down on a parachute
    //remoteControl,  ///remote-controlling something (e.g. super sheep)
    noMovement,     ///worm is being thrown around/firing a weapon/waiting for
                    ///a state transition and cannot be controlled
    drowning,       ///worm is between water surface and water ground
    invisible,      ///no animation for the worm anywhere in the level
}

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

enum SplatType {
    nuke,
}
