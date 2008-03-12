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
import gui.widget;
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

    //the "animated" health value, which is counted up/down to the real value
    //get the (not really) real value through realHealth()
    //(both this and realHealth are clipped to 0)
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
