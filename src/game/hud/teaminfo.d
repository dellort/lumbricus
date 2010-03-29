//shared GUI specific game data
//manage some client-side GUI infos about the game, mostly the teams
//at least the file-/module-name is completely wrong
module game.hud.teaminfo;

import framework.font;
import framework.framework;
import utils.timesource;
import game.clientengine;
import game.controller;
import game.events;
import game.core;
import game.gameshell;
import utils.rect2;
import utils.time;
import utils.misc;
import utils.vector2;
import utils.time;

public import game.controller : Team, TeamMember;

class GameInfo {
    ClientGameEngine cengine;
    GameCore engine;
    GameShell shell;
    GameController logic;
    alias logic controller;
    ClientControl control;
    SimpleNetConnection connection;
    Time replayRemain;

    //clientTime is something linear, that stops with pause, but is arbitrary
    //interpolateTime is synchronous to serverTime (just that it's adjusted
    //  on every frame, not only engine frames), but time might go backwards on
    //  replays
    TimeSourcePublic clientTime, interpolateTime;
    //frame stepped engine time
    TimeSourcePublic serverTime;

    this(GameShell a_shell, ClientGameEngine a_engine, ClientControl ct) {
        shell = a_shell;
        cengine = a_engine;
        engine = cengine.engine();
        logic = engine.singleton!(GameController)();
        control = ct;

        clientTime = cengine.engineTime;
        serverTime = engine.gameTime;
        interpolateTime = engine.interpolateTime;

        //doesn't necessarily belong here
        engine.getControlledTeamMember = &controlled;
    }

    private Actor controlled() {
        return control.getControlledMember();
    }
}

