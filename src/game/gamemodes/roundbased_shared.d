module game.gamemodes.roundbased_shared;

import utils.time;

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

struct RoundbasedStatus {
    Time roundRemaining;
    Time prepareRemaining;
    Time gameRemaining;
    bool timePaused;
}

const cRoundbased = "roundbased";
