module game.netclient;

public import game.netshared;

import str = std.string;

import game.levelgen.level;
import game.setup;
import utils.configfile;
import utils.time;
import utils.vector2;

class NetClient {
    private {
        GameState state;
        GSFunctions stuff;
        char[][] commands;
        NetEventQueue update;
        GameConfig config;
    }

    this(PseudoNetwork pseudo) {
        state = pseudo.server_to_client;
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
        //oh well, everything is done automatically?
    }

    //in case of real networking: will return null until fully initialized
    GameEnginePublic game() {
        return stuff;
    }

    //same here
    //gametask.d will need to load resources and render the level
    GameConfig gameConfig() {
        return config;
    }
}

//just implements the interfaces and redirects calls to GameState etc.
class GSFunctions : GameEnginePublic, GameLogicPublic, GameEngineAdmin,
    TeamMemberControl
{
    GameState state;
    GSTeam[] teams;
    Team[] teams2; //lol
    NetClient client;

    this(NetClient a_client) {
        client = a_client;
        state = client.state;
        foreach (TeamState t; state.teams) {
            teams ~= new GSTeam(t);
            teams2 ~= teams[$-1];
            assert (teams.length - 1 == t.index);
        }
    }

    //--- GameEnginePublic

    GameEngineAdmin requestAdmin() {
        return this; //lol
    }

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

    //--- GameEngineAdmin

    void raiseWater(int by) {
        client.commands ~= str.format("raise_water %s", by);
    }

    void setWindSpeed(float speed) {
        client.commands ~= str.format("set_wind %s", speed);
    }

    void setPaused(bool paused) {
        client.commands ~= str.format("set_pause %s", paused);
    }

    void setSlowDown(float slow) {
        client.commands ~= str.format("slow_down %s", slow);
    }

    //--- GameLogicPublic

    Team[] getTeams() {
        return teams2;
    }

    RoundState currentRoundState() {
        return state.roundstate;
    }

    Time currentRoundTime() {
        return state.roundtime;
    }

    Time currentPrepareTime() {
        return state.preparetime;
    }

    TeamMemberControl getControl() {
        return this; //hurrr
    }

    WeaponHandle[] weaponList() {
        return state.weaponlist;
    }

    int getMessageChangeCounter() {
        return state.msgcounter;
    }

    void getLastMessage(out char[] msgid, out char[][] msg) {
        msgid = state.msgid;
        msg = state.msg;
    }

    int getWeaponListChangeCounter() {
        return state.weaponlistcc;
    }

    //--- TeamMemberControl

    //xxx: most of control probably needs to be changed so, that it is
    //     connection-specific

    TeamMember getActiveMember() {
        if (!state.active_member)
            return null;
        MemberState m = state.active_member;
        return teams[m.team.index].members[m.index];
    }

    Team getActiveTeam() {
        if (!state.active_member)
            return null;
        return teams[state.active_member.team.index];
    }

    Time currentLastAction() {
        return state.current_last_action;
    }

    WeaponHandle currentWeapon() {
        return state.current_weapon;
    }

    bool displayWeaponIcon() {
        return state.display_weapon_icon;
    }

    //"writing" functions

    void selectNextMember() {
        client.commands ~= "next_member";
    }

    void jump(JumpMode mode) {
        client.commands ~= str.format("jump %s", cast(int)mode);
    }

    void setMovement(Vector2i m) {
        client.commands ~= str.format("move %s %s", m.x, m.y);
    }

    void weaponDraw(WeaponHandle weaponId) {
        client.commands ~= str.format("draw_weapon %s", weaponId ?
            weaponId.name : "-");
    }

    void weaponSetTimer(Time timer) {
        client.commands ~= str.format("set_timer %s", timer.msecs());
    }

    void weaponSetTarget(Vector2i targetPos) {
        client.commands ~= str.format("set_target %s %s", targetPos.x, targetPos.y);
    }

    void weaponFire(bool is_down) {
        client.commands ~= str.format("weapon_fire %s", is_down);
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

    Graphic getGraphic() {
        return member.graphic;
    }
}
