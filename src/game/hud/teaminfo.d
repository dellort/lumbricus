//shared GUI specific game data
//manage some client-side GUI infos about the game, mostly the teams
//at least the file-/module-name is completely wrong
module game.hud.teaminfo;

import framework.font;
import framework.framework;
import framework.timesource;
import game.gfxset;
import game.clientengine;
import game.controller;
import game.gameshell;
import game.weapon.weapon;
import game.game;
import gui.rendertext;
import gui.label;
import gui.widget;
import utils.rect2;
import utils.time;
import utils.misc;
import utils.vector2;
import utils.time;

public import game.controller : Team, TeamMember;

class GameInfo {
    ClientGameEngine cengine;
    GameEngine engine;
    GameController logic;
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

    this(ClientGameEngine a_engine, ClientControl ct) {
        cengine = a_engine;
        engine = cengine.engine();
        logic = engine.logic;
        control = ct;

        clientTime = cengine.engineTime;
        serverTime = engine.gameTime;
        interpolateTime = engine.callbacks.interpolateTime;

        //doesn't necessarily belong here
        engine.callbacks.getControlledTeamMember = &controlled;
    }

    private TeamMember controlled() {
        return control.getControlledMember();
    }
}

