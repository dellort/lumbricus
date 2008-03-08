//shared GUI specific game data
//manage some client-side GUI infos about the game, mostly the teams
//at least the file-/module-name is completely wrong
module game.gui.teaminfo;

import common.visual;
import framework.font;
import framework.framework;
import game.gamepublic;
import game.clientengine;
import game.weapon.weapon;
import gui.label;
import utils.rect2;
import utils.time;
import utils.misc;
import utils.vector2;

class GameInfo {
    ClientGameEngine cengine;
    GameEnginePublic engine;
    TeamInfo[Team] teams;
    TeamMemberInfo[TeamMember] allMembers;

    this(ClientGameEngine a_engine) {
        cengine = a_engine;
        engine = cengine.engine();

        foreach (t; engine.logic().getTeams()) {
            auto team = new TeamInfo(this, t);
            teams[t] = team;
        }
    }

    //called on each frame
    //do whatever there is useful to do
    void simulate() {
    }
}

class TeamInfo {
    GameInfo owner;
    Team team;
    Color color;
    Font font;
    BoxProperties box; //for labels
    TeamTheme theme; //game theme, partially used by the GUI
    //NOTE: in the game, foreign objects could appear, with are member of a team
    // (like the supersheep), these are not in this list
    TeamMemberInfo[] members;

    //create a Label in this worm's style
    //it's initialized with the team's name
    Label createLabel() {
        auto res = new Label();
        res.font = font;
        res.text = team.name();
        res.borderStyle = box;
        return res;
    }

    //the current health, possibly rapidly changing for the purpose of animation
    //(counting down the health after damage)
    int currentHealth() {
        return team.totalHealth();
    }

    this(GameInfo a_owner, Team t) {
        owner = a_owner;
        team = t;
        theme = t.color();
        color = theme.color;
        auto st = gFramework.fontManager.getStyle("wormfont");
        st.fore = color;
        font = new Font(st);
        //xxx load this from a configfile hurrrr
        box.border = Color(0.7);
        box.back = Color(0);
        box.cornerRadius = 3;

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

    //similar to TeamInfo.currentHealth(), only for the team member
    //also won't go below 0
    int currentHealth() {
        return member.health();
    }

    this(TeamInfo a_owner, TeamMember m) {
        owner = a_owner;
        member = m;
    }
}
