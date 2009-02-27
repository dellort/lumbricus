module game.netserver;

import framework.commandline;
import game.game;
import game.controller;
import game.netshared;
import game.weapon.weapon;
import utils.misc;
import utils.time;
import utils.vector2;
import utils.mybox;

import common.common : globals;

//used by server-side
class NetServer {
    private {
        class Connection {
            PseudoNetwork net;
            //there should be one client for each connection
            //additionally, each client would have a list of teams which it can
            //control
            ClientControl client;
        }

        GameEngine engine;
        InitPacket init;
        GameState state;
        MemberState[TeamMember] member_server2state;
        Connection[] mConnections;
    }

    //create a server for pseudo-networking
    //(otherwise, it'd also take a NetPeer parameter or whatever)
    this(GameEngine a_engine) {
        engine = a_engine;
        writeState();
        init = new InitPacket();
        init.config = engine.gameConfig.save.writeAsString();
    }

    //establish a client connection
    PseudoNetwork connect() {
        //only one connection for now
        assert(mConnections.length == 0, "TODO");
        auto con = new Connection();
        con.net = new PseudoNetwork();
        con.net.client_init = init;
        con.net.shared_state = state;
        con.net.client_to_server = new NetEventQueue();
        //xxx: establish a per-client controller connection here
        con.client = new ClientControlImpl(engine.controller);
        mConnections ~= con;
        writeState();
        return con.net;
    }

    //receive a frame from a client
    //dispatches input
    void frame_receive() {
        foreach (con; mConnections) {
            NetEvent[] events = con.net.client_to_server.receive();
            foreach (e; events) {
                auto ce = castStrict!(ClientEvent)(e);
                foreach (char[] cmd; ce.commands) {
                    con.client.executeCommand(cmd);
                }
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

        bool init;
        if (!state) {
            state = new GameState();
            init = true;
        }

        if (init) {
            state.graphics = engine.getGraphics();
            state.level = engine.level();
            state.world_size = engine.worldSize();
            state.world_center = engine.worldCenter();

            state.weaponlist = logic.weaponList();
            state.gamemode = logic.gamemode();
        }

        state.servertime = state.graphics.timebase.current();

        state.water_offset = engine.waterOffset();
        state.wind_speed = engine.windSpeed();
        state.earth_quake_strength = engine.earthQuakeStrength();
        state.paused = engine.paused();
        state.slow_down = engine.slowDown();

        state.game_ended = logic.gameEnded();
        state.gamemodestatus = logic.gamemodeStatus();
        state.msgcounter = logic.getMessageChangeCounter();
        logic.getLastMessage(state.msgid, state.msg, state.msg_rnd);

        bool weapons_changed;
        int oldwcounter = logic.getWeaponListChangeCounter();
        weapons_changed = init || (oldwcounter != state.weaponlistcc);
        state.weaponlistcc = oldwcounter;

        state.activeteams.length = logic.getActiveTeams().length;
        int activeCtr = 0;  //xxx
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
            }
            //normal fields (but still won't change very often)
            ts.active = t.active();
            ts.allowselect = t.allowSelect();
            if (weapons_changed)
                ts.weapons = t.getWeapons();
            if (ts.active) {
                //avoid reserving memory
                assert(activeCtr < state.activeteams.length);
                state.activeteams[activeCtr] = ts;
                activeCtr++;
            }
        }

        foreach (con; mConnections) {
            writeClientState(con);
        }
    }

    private void writeClientState(Connection con) {
        if (!con.net.client_state) {
            con.net.client_state = new ClientState();
        }
        auto m = con.client.getControlledMember();
        if (m) {
            con.net.client_state.controlledMember = member_server2state[m];
        } else {
            con.net.client_state.controlledMember = null;
        }
    }
}
