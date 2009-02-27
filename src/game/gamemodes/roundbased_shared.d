module game.gamemodes.roundbased_shared;

import utils.time;
import utils.reflection;

enum RoundState : int {
    prepare,    //player ready
    playing,    //round running
    retreat,    //still moving after firing a weapon
    waitForSilence, //before entering cleaningUp: wait for no-activity
    cleaningUp, //worms losing hp etc, may occur during round
    nextOnHold, //next round about to start (drop crates, ...)
    winning,    //short state to show the happy survivors
    end = -1,        //everything ended!
}

//this is for GUI elements that are dependent from the game mode
//currently game/hud/gametimer.d and game/hud/preparedisplay.d
class RoundbasedStatus {
    this() {
    }
    this(ReflectCtor c) {
    }

    //xxx maybe replace by collection of bool flags
    //  e.g. show prepare display? show timer? etc.
    //  RoundState could be fully internal, then.
    RoundState state;
    Time roundRemaining;
    Time prepareRemaining;
    Time gameRemaining;
    bool timePaused;
    bool suddenDeath;
}
