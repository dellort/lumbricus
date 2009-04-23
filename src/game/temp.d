module game.temp;

//enum dumping ground...

///this tells the client the state (i.e. possible interactions) of the currently
///active worm (no animation states etc)
///(client information only, to update the gui/map keys or something)
///note that targetting weapons are not affected by this, as target selection is
///a client thing
enum WalkState {
//xxx: no "stand" state? i.e. when it's _not_ walking
    walk,           ///worm is on the ground and could walk normally
    jetpackFly,     ///flying a jetpack
    swing,          ///hanging on a rope
    floating,       ///floating down on a parachute
    remoteControl,  ///remote-controlling something (e.g. super sheep)
    noMovement,     ///worm is being thrown around/firing a weapon/waiting for
                    ///a state transition and cannot be controlled
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
