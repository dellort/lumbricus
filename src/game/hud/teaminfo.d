//shared GUI specific game data
//at least the file-/module-name is completely wrong
module game.hud.teaminfo;

import game.controller;
import game.core;
import game.gameshell;
import utils.rect2;
import utils.misc;
import utils.time;

class GameInfo {
    GameCore engine;
    GameShell shell;
    GameController controller;
    ClientControl control;
    SimpleNetConnection connection;

    this(GameShell a_shell, ClientControl ct) {
        shell = a_shell;
        engine = shell.serverEngine();
        controller = engine.singleton!(GameController)();
        engine.addSingleton(this);
        control = ct;
    }
}

