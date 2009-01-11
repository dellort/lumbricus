module game.gamemodes.base;

import framework.framework;
import framework.timesource;
import game.game;
import game.controller;
import game.gamepublic;

import utils.factory;
import utils.mybox;

//factory to instantiate gamemodes
static class GamemodeFactory
    : StaticFactory!(Gamemode, GameController, ConfigNode)
{
}

class Gamemode {
    GameEngine engine;
    GameController logic;

    this(GameController parent, ConfigNode config) {
        engine = parent.engine;
        logic = parent;
    }

    ///Initialize gamemode (check requirements or whatever)
    ///Called after controller initialization and client connection
    ///Throw exception if anything is not according to plan
    void initialize() {
    }

    ///Start a new game, called before first simulate call
    void startGame() {
    }

    ///Called every frame, run gamemode-specific code here
    abstract void simulate();

    ///Called by controller every frame, after simulate
    ///Return true if the game is over
    ///It is the Gamemode's task to make a team win before
    abstract bool ended();

    ///Return a mode-specific state identifier
    ///-1 means the game has ended
    abstract int state();

    ///get mode-specific status information
    ///clients have to know about the mode implementation to use it
    abstract MyBox getStatus();
}
