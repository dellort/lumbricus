module game.netserver;

import framework.commandline;
import game.game;
import game.netshared;
import game.weapon.weapon;
import utils.misc;
import utils.time;
import utils.vector2;

import common.common : globals;

//used by server-side
class NetServer {
    private {
        GameEngine engine;
        GameState state;
        //xxx should be per-client
        ClientState clientstate;
        MemberState[TeamMember] member_server2state;
        PseudoNetwork net;
        //there should be one client for each connection
        //additionally, each client would have a list of teams which it can
        //control
        ClientInput client;
    }

    //create a server for pseudo-networking
    //(otherwise, it'd also take a NetPeer parameter or whatever)
    this(GameEngine a_engine) {
        engine = a_engine;
        writeState();
        net = new PseudoNetwork();
        net.client_init = new InitPacket();
        net.client_init.config = engine.gameConfig.save.writeAsString();
        net.server_to_client = state;
        net.server_to_one_client = clientstate;
        net.client_to_server = new NetEventQueue();
        client = new ClientInput(this);
    }

    PseudoNetwork pseudoNetwork() {
        return net;
    }

    //receive a frame from a client
    //dispatches input
    void frame_receive() {
        NetEvent[] events = net.client_to_server.receive();
        foreach (e; events) {
            auto ce = castStrict!(ClientEvent)(e);
            foreach (char[] cmd; ce.commands) {
                client.command(cmd);
            }
        }
    }

    //send data to all clients
    void frame_send() {
        writeState();
    }

    //dump all infos from the server into the shared state
    private void writeState() {
        GameLogicPublic logic = engine.logic();
        ClientControl control = logic.getControl();

        bool init;
        if (!state) {
            state = new GameState();
            init = true;
        }
        if (!clientstate) {
        	clientstate = new ClientState();
        }

        if (init) {
            state.graphics = engine.getGraphics();
            state.level = engine.level();
            state.world_size = engine.worldSize();
            state.world_center = engine.worldCenter();

            state.weaponlist = logic.weaponList();
        }

        state.servertime = state.graphics.timebase.current();

        state.water_offset = engine.waterOffset();
        state.wind_speed = engine.windSpeed();
        state.earth_quake_strength = engine.earthQuakeStrength();
        state.paused = engine.paused();
        state.slow_down = engine.slowDown();

        state.roundstate = logic.currentRoundState();
        state.roundtime = logic.currentRoundTime();
        state.preparetime = logic.currentPrepareTime();
        state.msgcounter = logic.getMessageChangeCounter();
        logic.getLastMessage(state.msgid, state.msg);
        state.weaponlistcc = logic.getWeaponListChangeCounter();

        state.activeteams = null;
        clientstate.controlledMember = null;
        foreach (int n, Team t; logic.getTeams()) {
            //xxx: actually, the team list is considered to be immutable
            //     this is only for initialization
            if (n >= state.teams.length) {
                assert(init);
                state.teams ~= new TeamState();
            }
            TeamState ts = state.teams[n];
            //immutable fields
            if (init) {
                ts.gamestate = state;
                ts.index = n;
                ts.name = t.name();
                ts.color = t.color();
            }
            foreach (int i, TeamMember m; t.getMembers()) {
                if (i >= ts.members.length) {
                    assert(init);
                    ts.members ~= new MemberState();
                }
                MemberState ms = ts.members[i];
                if (init) {
                    member_server2state[m] = ms;
                    ms.index = i;
                    ms.name = m.name();
                    ms.team = ts;
                }
                ms.alive = m.alive();
                ms.active = m.active();
                if (ms.active)
                	ts.active_member = ms;
                ms.current_health = m.currentHealth();
                ms.display_weapon_icon = m.displayWeaponIcon();
                ms.last_action = m.lastAction();
                ms.current_weapon = m.getCurrentWeapon();
                ms.graphic = m.getGraphic();
                if (m == control.getControlledMember())
                	clientstate.controlledMember = ms; 
            }
            //normal fields (but still won't change very often)
            ts.active = t.active();
            ts.weapons = t.getWeapons();
            if (ts.active)
            	state.activeteams ~= ts;
        }
    }
}

private class ClientInput {
    NetServer server;
    GameEngine engine;
    GameLogicPublic logic;
    ClientControl control;

    this(NetServer a_server) {
        server = a_server;
        engine = server.engine;
        logic = engine.logic();
        control = logic.getControl();
    }

    void command(char[] a_cmd) {
        control.executeCommand(a_cmd);
    }
}
