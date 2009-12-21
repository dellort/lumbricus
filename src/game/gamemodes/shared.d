module game.gamemodes.shared;

import utils.time;
import utils.reflection;

//this is for GUI elements that are dependent from the game mode
//currently game/hud/gametimer.d and game/hud/preparedisplay.d

class TimeStatus {
    this() {
    }
    this(ReflectCtor c) {
    }

    bool showTurnTime, showGameTime;
    bool timePaused;
    Time turnRemaining, gameRemaining;
}

class PrepareStatus {
    this() {
    }
    this(ReflectCtor c) {
    }

    bool visible;
    Time prepareRemaining;
}
