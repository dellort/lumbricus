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
        TeamMemberControl control = logic.getControl();

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
                ms.current_health = m.currentHealth();
                ms.graphic = m.getGraphic();
            }
            //normal fields (but still won't change very often)
            ts.active = t.active();
            ts.weapons = t.getWeapons();
        }

        auto am = control.getActiveMember();
        state.active_member = am ? member_server2state[am] : null;
        state.current_last_action = control.currentLastAction();
        state.current_weapon = control.currentWeapon();
        state.display_weapon_icon = control.displayWeaponIcon();
    }
}

private class ClientInput {
    NetServer server;
    CommandLine cmd;
    CommandBucket cmds;
    GameEngine engine;
    GameLogicPublic logic;
    TeamMemberControl control;
    GameEngineAdmin admin;

    this(NetServer a_server) {
        server = a_server;
        engine = server.engine;
        logic = engine.logic();
        control = logic.getControl();
        admin = engine.requestAdmin();
        //output should be sent back to the client...?
        cmd = new CommandLine(globals.defaultOut);
        cmds = new CommandBucket();
        cmds.register(Command("next_member", &cmdNextMember, "-"));
        cmds.register(Command("jump", &cmdJump, "-", ["int:type"]));
        cmds.register(Command("move", &cmdMove, "-", ["int:x", "int:y"]));
        cmds.register(Command("draw_weapon", &cmdDrawWeapon, "-",
            ["text:name"]));
        cmds.register(Command("set_timer", &cmdSetTimer, "-", ["int:ms"]));
        cmds.register(Command("set_target", &cmdSetTarget, "-",
            ["int:x", "int:y"]));
        cmds.register(Command("weapon_fire", &cmdFire, "-", ["bool:is_down"]));
        cmds.register(Command("raise_water", &cmdRaiseWater, "-", ["int:by"]));
        cmds.register(Command("set_wind", &cmdSetWind, "-", ["float:speed"]));
        cmds.register(Command("set_pause", &cmdSetPause, "-", ["bool:state"]));
        cmds.register(Command("slow_down", &cmdSlowDown, "-", ["float:slow"]));
        cmds.bind(cmd);
    }

    private void cmdNextMember(MyBox[] args, Output write) {
        control.selectNextMember();
    }

    private void cmdJump(MyBox[] args, Output write) {
        control.jump(cast(JumpMode)args[0].unbox!(int));
    }

    private void cmdMove(MyBox[] args, Output write) {
        control.setMovement(Vector2i(args[0].unbox!(int), args[1].unbox!(int)));
    }

    private void cmdDrawWeapon(MyBox[] args, Output write) {
        char[] t = args[0].unbox!(char[]);
        WeaponClass wc;
        if (t != "-")
            wc = engine.findWeaponClass(t, true);
        //urgs
        WeaponHandle wh = wc ? engine.wc2wh(wc) : null;
        control.weaponDraw(wh);
    }

    private void cmdSetTimer(MyBox[] args, Output write) {
        control.weaponSetTimer(timeMsecs(args[0].unbox!(int)));
    }

    private void cmdSetTarget(MyBox[] args, Output write) {
        control.weaponSetTarget(Vector2i(args[0].unbox!(int),
            args[1].unbox!(int)));
    }

    private void cmdFire(MyBox[] args, Output write) {
        control.weaponFire(args[0].unbox!(bool));
    }

    private void cmdRaiseWater(MyBox[] args, Output write) {
        admin.raiseWater(args[0].unbox!(int));
    }

    private void cmdSetWind(MyBox[] args, Output write) {
        admin.setWindSpeed(args[0].unbox!(float));
    }

    private void cmdSetPause(MyBox[] args, Output write) {
        admin.setPaused(args[0].unbox!(bool));
    }

    private void cmdSlowDown(MyBox[] args, Output write) {
        admin.setSlowDown(args[0].unbox!(float));
    }

    void command(char[] a_cmd) {
        cmd.execute(a_cmd);
    }
}
