//shared GUI specific game data
//manage some client-side GUI infos about the game, mostly the teams
//at least the file-/module-name is completely wrong
module game.hud.teaminfo;

import common.visual;
import framework.font;
import framework.framework;
import framework.timesource;
import game.gamepublic;
import game.gfxset;
import game.clientengine;
import game.controller;
import game.gameshell;
import game.weapon.weapon;
import game.game;
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
    TeamInfo[Team] teams;
    TeamMemberInfo[TeamMember] allMembers;
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

        foreach (t; engine.logic().getTeams()) {
            auto team = new TeamInfo(this, t);
            teams[t] = team;
        }

        //doesn't necessarily belong here
        engine.callbacks.getControlledTeamMember = &controlled;
    }

    private TeamMember controlled() {
        return control.getControlledMember();
    }
}

class TeamInfo {
    GameInfo owner;
    Team team;
    Color color;
    Font font;
    Font font_flash; //when worm label is highlighted for blinking
    TeamTheme theme; //game theme, partially used by the GUI
    //NOTE: in the game, foreign objects could appear, with are member of a team
    // (like the supersheep), these are not in this list
    TeamMemberInfo[] members;

    //create a Label in this worm's style
    //it's initialized with the team's name
    Label createLabel() {
        auto res = new Label();
        res.styles.addClasses(["worm-label"]);
        res.font = font;
        res.text = team.name();
        res.setLayout(WidgetLayout.Aligned(-1, -1));
        return res;
    }

    //sum of all team member's TeamMemberInfo.currentHealth()
    int currentHealth() {
        int sum = 0;
        foreach (m; members) {
            sum += m.currentHealth;
        }
        return sum;
    }

    this(GameInfo a_owner, Team t) {
        owner = a_owner;
        team = t;
        theme = t.color();
        color = theme.color;
        auto st = gFramework.fontManager.getStyle("wormfont");
        st.fore = color;
        font = new Font(st);
        auto st_flash = st;
        st_flash.fore = Color(1);
        font_flash = new Font(st_flash);

        foreach (m; t.getMembers()) {
            auto member = new TeamMemberInfo(this, m);
            members ~= member;
            owner.allMembers[m] = member;
        }
    }
}

class TeamMemberInfo {
    TeamInfo owner;
    TeamMember member;

    //the "animated" health value, which is counted up/down to the real value
    //get the (not really) real value through realHealth()
    //(both this and realHealth are clipped to 0)
    //value changed in gameframe.d
    int currentHealth;

    //similar to member.currentHealth(), but clipped to 0
    int realHealth() {
        return max(member.currentHealth(), 0);
    }

    this(TeamInfo a_owner, TeamMember m) {
        owner = a_owner;
        member = m;
        currentHealth = realHealth();
    }
}
