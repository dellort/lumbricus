module game.gamemodes.turnbased_shared;

import utils.time;
import utils.reflection;

enum TurnState : int {
    prepare,    //player ready
    playing,    //turn running
    retreat,    //still moving after firing a weapon
    waitForSilence, //before entering cleaningUp: wait for no-activity
    cleaningUp, //worms losing hp etc, may occur during turn
    nextOnHold, //next turn about to start (drop crates, ...)
    winning,    //short state to show the happy survivors
    end = -1,        //everything ended!
}

//this is for GUI elements that are dependent from the game mode
//currently game/hud/gametimer.d and game/hud/preparedisplay.d
class TurnbasedStatus {
    this() {
    }
    this(ReflectCtor c) {
    }

    //xxx maybe replace by collection of bool flags
    //  e.g. show prepare display? show timer? etc.
    //  TurnState could be fully internal, then.
    TurnState state;
    Time turnRemaining;
    Time prepareRemaining;
    Time gameRemaining;
    bool timePaused;
    bool suddenDeath;
}

//xxx this shouldn't be here
class RealtimeStatus {
    this() {
    }
    this(ReflectCtor c) {
    }

    Time gameRemaining, retreatRemaining;
    bool suddenDeath, gameEnding;
}
