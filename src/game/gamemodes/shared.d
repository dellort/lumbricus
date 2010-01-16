module game.gamemodes.shared;

import utils.time;

//this is for GUI elements that are dependent from the game mode
//currently game/hud/gametimer.d and game/hud/preparedisplay.d

class TimeStatus {
    this() {
    }

    bool showTurnTime, showGameTime;
    bool timePaused;
    Time turnRemaining, gameRemaining;
}

class PrepareStatus {
    this() {
    }

    bool visible;
    Time prepareRemaining;
}
