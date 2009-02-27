module game.netclient;

public import game.netshared;

import str = stdx.string;

import game.levelgen.level;
import game.setup;
import game.gfxset;
import utils.array;
import utils.configfile;
import utils.time;
import utils.vector2;
import utils.mybox;

class NetClient {
    private {
        GameState state;
        ClientState clientstate;
        GSFunctions stuff;
        char[][] commands;
        NetEventQueue update;
        GameConfig config;
    }

    this(PseudoNetwork pseudo) {
        state = pseudo.shared_state;
        clientstate = pseudo.client_state;
        update = pseudo.client_to_server;
        stuff = new GSFunctions(this);
        //xxx: this shouldn't render the level or load resources
        //     it should be done by gametask.d afterwards
        //     the network join-phase should go in two phases:
        //        1. init basics (render level, load resources)
        //           the server waits so long
        //        2. singal the server that you're ready; the server will start
        //           the game and send the rest of the init data (GameState)
        auto configfile = new ConfigFile(pseudo.client_init.config,
            "gamedata.conf", null);
        config = loadGameConfig(configfile.rootnode());
    }

    //send a frame into network
    //xxx: maybe it would better if this sends a network frame on key presses?
    //     or here, as soon as commands is non-empty (ok, currently done anyway)
    void frame_send() {
        if (commands.length) {
            auto ev = new ClientEvent();
            ev.commands = commands;
            commands = null;
            update.add(ev);
        }
    }

    void frame_receive() {
        stuff.activeteams.length = state.activeteams.length;
        foreach (int i, ref TeamState t; state.activeteams) {
            stuff.activeteams[i] = stuff.teams2[t.index];
        }
        //oh well, everything else is done automatically?
    }

    //in case of real networking: will return null until fully initialized
    GameEnginePublic game() {
        return stuff;
    }

    ClientControl control() {
        //another hrhrhr
        return stuff;
    }

    //same here
    //gametask.d will need to load resources and render the level
    GameConfig gameConfig() {
        return config;
    }
}

//just implements the interfaces and redirects calls to GameState etc.
class GSFunctions : GameEnginePublic, GameLogicPublic, ClientControl
{
    GameState state;
    ClientState clientstate;
    GSTeam[] teams;
    Team[] teams2; //lol
    Team[] activeteams;
    NetClient client;

    this(NetClient a_client) {
        client = a_client;
        state = client.state;
        clientstate = client.clientstate;
        foreach (TeamState t; state.teams) {
            teams ~= new GSTeam(t);
            teams2 ~= teams[$-1];
            assert (teams.length - 1 == t.index);
        }
    }

    //--- GameEnginePublic

    int waterOffset() {
        return state.water_offset;
    }

    float windSpeed() {
        return state.wind_speed;
    }

    float earthQuakeStrength() {
        return state.earth_quake_strength;
    }

    Level level() {
        return state.level;
    }

    Vector2i worldSize() {
        return state.world_size;
    }

    Vector2i worldCenter() {
        return state.world_center;
    }

    bool paused() {
        return state.paused;
    }

    float slowDown() {
        return state.slow_down;
    }

    GameLogicPublic logic() {
        return this; //lol
    }

    GameEngineGraphics getGraphics() {
        return state.graphics;
    }

    //--- GameLogicPublic

    Team[] getTeams() {
        return teams2;
    }

    Team[] getActiveTeams() {
        return activeteams;
    }

    char[] gamemode() {
        return state.gamemode;
    }

    bool gameEnded() {
        return state.game_ended;
    }

    Object gamemodeStatus() {
        return state.gamemodestatus;
    }

    WeaponHandle[] weaponList() {
        return state.weaponlist;
    }

    int getMessageChangeCounter() {
        return state.msgcounter;
    }

    void getLastMessage(out char[] msgid, out char[][] msg, out uint rnd) {
        msgid = state.msgid;
        msg = state.msg;
        rnd = state.msg_rnd;
    }

    int getWeaponListChangeCounter() {
        return state.weaponlistcc;
    }

    //--- ClientControl

    //xxx: most of control probably needs to be changed so, that it is
    //     connection-specific

    TeamMember getControlledMember() {
        if (!clientstate.controlledMember)
            return null;
        GSTeam t = teams[clientstate.controlledMember.team.index];
        return t.members2[clientstate.controlledMember.index];
    }

    void executeCommand(char[] cmd) {
        client.commands ~= cmd;
    }
}

class GSTeam : Team {
    TeamState team;
    GSTeamMember[] members;
    TeamMember[] members2;

    this(TeamState st) {
        team = st;
        foreach (MemberState m; team.members) {
            members ~= new GSTeamMember(this, m);
            members2 ~= members[$-1];
            assert (members.length - 1 == m.index);
        }
    }

    char[] name() {
        return team.name;
    }

    TeamTheme color() {
        return team.color;
    }

    bool active() {
        return team.active;
    }

    WeaponList getWeapons() {
        return team.weapons;
    }

    TeamMember[] getMembers() {
        return members2;
    }

    TeamMember getActiveMember() {
        if (!team.active_member)
            return null;
        return members2[team.active_member.index];
    }

    bool allowSelect() {
        return team.allowselect;
    }
}

class GSTeamMember : TeamMember {
    MemberState member;
    GSTeam gsteam;

    this(GSTeam parent, MemberState st) {
        member = st;
        gsteam = parent;
    }

    char[] name() {
        return member.name;
    }

    Team team() {
        return gsteam;
    }

    bool alive() {
        return member.alive;
    }

    bool active() {
        return member.active;
    }

    int currentHealth() {
        return member.current_health;
    }

    Time lastAction() {
        return member.last_action;
    }

    WeaponHandle getCurrentWeapon() {
        return member.current_weapon;
    }

    bool displayWeaponIcon() {
        return member.display_weapon_icon;
    }

    Graphic getGraphic() {
        return member.graphic;
    }
}
