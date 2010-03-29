module game.input;

import common.common;
import framework.commandline;
import framework.framework;
import game.controller;
import game.core;
import game.events;
import game.sequence;
import game.setup;
import game.temp;
import game.particles;
import game.lua.base;
import game.weapon.weapon;
import utils.configfile;
import utils.log;
import utils.misc;
import utils.random;
import utils.time;

import tango.core.Traits : ParameterTupleOf;

//everything in this class is total crap and needs to be redone
class InputHandler {
    private {
        GameCore engine;

        AccessEntry[] mAccessMapping;
        struct AccessEntry {
            char[] tag;
            Team team;
        }

        CommandBucket mCmds;
        CommandLine mCmd;

        GameController mController;

        //temporary during command execution (sorry)
        char[] mTmp_CurrentAccessTag;

        static LogStruct!("input") log;
    }

    this(GameCore a_engine) {
        engine = a_engine;
        mController = engine.singleton!(GameController)();

        //unneeded?
        engine.addSingleton(this);

        //read the shitty access map, need to have access to the controller
        auto map = engine.gameConfig.management.getSubNode("access_map");
        foreach (ConfigNode sub; map) {
            //sub is "tag_name { "teamid1" "teamid2" ... }"
            foreach (char[] key, char[] value; sub) {
                Team found;
                foreach (Team t; mController.teams) {
                    if (t.id() == value) {
                        found = t;
                        break;
                    }
                }
                //xxx error handling
                assert(!!found, "invalid team id: "~value);
                mAccessMapping ~= AccessEntry(sub.name, found);
            }
        }

        createCmd();

        //sorry, but this is probably better than going through all the usual
        //  binding steps (add as singleton, etc.)
        engine.scripting.scriptExec("_G.getCurrentInputTeam = ...", &ownedTeam);
    }

    private void scriptExecute(MyBox[] args, Output write) {
        char[] cmd = args[0].unbox!(char[]);
        try {
            engine.scripting.scriptExec(cmd);
            write.writefln("OK");
        } catch (ScriptingException e) {
            //xxx write is not the console where the command came from,
            //    but the global output
            engine.error("{}", e.msg);
            write.writefln("{}", e.msg);
        }
    }

    private void crateTest() {
        mController.dropCrate(true);
    }

    //execute a user command
    //because cmd comes straight from the network, there's an access_tag
    //  parameter, which kind of identifies the sender of the command. the
    //  access_tag corresponds to the key in mAccessMapping.
    //the tag "local" is specially interpreted, and means the command comes
    //  from a privileged source. this disables access control checking.
    //be warned: in network game, the engine is replicated, and all nodes
    //  think they are "local", so using this in network games might cause chaos
    //  and desynchronization... it's a hack for local games, anyway
    void executeCommand(char[] access_tag, char[] cmd) {
        //log("exec: '{}': '{}'", access_tag, cmd);
        assert(mTmp_CurrentAccessTag == "");
        mTmp_CurrentAccessTag = access_tag;
        scope(exit) mTmp_CurrentAccessTag = "";
        mCmd.execute(cmd);
    }

    //test if the given team can be accessed with the given access tag
    //right now used for ClientControl.getOwnedTeams()
    bool checkTeamAccess(char[] access_tag, Team t) {
        if (access_tag == "local")
            return true;
        foreach (ref entry; mAccessMapping) {
            if (entry.tag == access_tag && entry.team is t)
                return true;
        }
        return false;
    }

    //internal clusterfuck follows

    //automatically add an item to the command line parser
    //compile time magic is used to infer the parameters, and the delegate
    //is called when the command is invoked (maybe this is overcomplicated)
    private void addCmd(T)(char[] name, T del) {
        alias ParameterTupleOf!(T) Params;

        //proxify the function in a commandline call
        //the wrapper is just to get a delegate, that is valid even after this
        //function has returned
        //in D2.0, this Wrapper stuff will be unnecessary
        struct Wrapper {
            T callee;
            char[] name;
            void cmd(MyBox[] params, Output o) {
                Params p;
                //(yes, p[i] will have a different static type in each iteration)
                foreach (int i, x; Params) {
                    p[i] = params[i].unbox!(x)();
                }
                callee(p);
            }
        }

        Wrapper* pwrap = new Wrapper;
        pwrap.callee = del;
        pwrap.name = name;

        //build command line argument list according to delegate arguments
        char[][] cmdargs;
        foreach (int i, x; Params) {
            char[]* pt = typeid(x) in gCommandLineParserTypes;
            if (!pt) {
                assert(false, "no command line parser for " ~ x.stringof);
            }
            cmdargs ~= myformat("{}:param_{}", *pt, i);
        }

        mCmds.register(Command(name, &pwrap.cmd, "-", cmdargs));
    }

    //similar to addCmd()
    //expected is a delegate like void foo(TeamMember w, X); where
    //X can be further parameters (can be empty)
    private void addWormCmd(T)(char[] name, T del) {
        //remove first parameter, because that's the worm
        alias ParameterTupleOf!(T)[1..$] Params;

        struct Wrapper {
            InputHandler owner;
            T callee;
            void moo(Params p) {
                bool ok;
                owner.checkWormCommand(
                    (TeamMember w) {
                        ok = true;
                        //may error here, if del has a wrong type
                        callee(w, p);
                    }
                );
                if (!ok)
                    log("denied: {}", owner.mTmp_CurrentAccessTag);
            }
        }

        Wrapper* pwrap = new Wrapper;
        pwrap.owner = this;
        pwrap.callee = del;

        addCmd(name, &pwrap.moo);
    }

    //return null on failure
    private static WeaponClass findWeapon(GameCore engine, char[] name) {
        return engine.resources.get!(WeaponClass)(name, true);
    }

    private void createCmd() {
        mCmd = new CommandLine(globals.defaultOut);
        mCmds = new CommandBucket();

        //usual server "admin" command
        //xxx: not access checked, although it could
        addCmd("crate_test", &crateTest);
        mCmds.registerCommand("exec", &scriptExecute, "execute script",
            ["text...:command"]);

        //worm control commands; work like above, but the worm-selection code
        //is factored out

        //remember that delegate literals must only access their params
        //if they access members of this class, runtime errors will result

        addWormCmd("next_member", (TeamMember w) {
            w.team.doChooseWorm();
        });
        addWormCmd("jump", (TeamMember w, bool alt) {
            w.control.jump(alt ? JumpMode.straightUp : JumpMode.normal);
        });
        addWormCmd("move", (TeamMember w, int x, int y) {
            w.control.doMove(Vector2i(x, y));
        });
        addWormCmd("weapon", (TeamMember w, char[] weapon) {
            WeaponClass wc;
            if (weapon != "-")
                wc = findWeapon(w.engine, weapon);
            w.control.selectWeapon(wc);
        });
        addWormCmd("set_timer", (TeamMember w, int ms) {
            w.control.doSetTimer(timeMsecs(ms));
        });
        addWormCmd("set_target", (TeamMember w, int x, int y) {
            w.control.doSetPoint(Vector2f(x, y));
        });
        addWormCmd("select_fire_refire", (TeamMember w, char[] m, bool down) {
            WeaponClass wc = findWeapon(w.engine, m);
            w.control.selectFireRefire(wc, down);
        });
        addWormCmd("selectandfire", (TeamMember w, char[] m, bool down) {
            if (down) {
                WeaponClass wc;
                if (m != "-")
                    wc = findWeapon(w.engine, m);
                w.control.selectWeapon(wc);
                //doFireDown will save the keypress and wait if not ready
                w.control.doFireDown(true);
            } else {
                //key was released (like fire behavior)
                w.control.doFireUp();
            }
        });

        //also a worm cmd, but specially handled
        addCmd("weapon_fire", &executeWeaponFire);
        addCmd("remove_control", &removeControl);

        mCmds.bind(mCmd);
    }

    //during command execution, returns the Team that sent the command
    //xxx mostly a hack for scriptExecute(), has no real other use
    Team ownedTeam() {
        //we must intersect both sets of team members (= worms):
        // set of active worms (by game controller) and set of worms owned by us
        //xxx: if several worms are active that belong to us, pick the first one
        foreach (Team t; mController.teams()) {
            if (t.active && checkTeamAccess(mTmp_CurrentAccessTag, t)) {
                return t;
            }
        }
        return null;
    }

    //if a worm control command is incoming (like move, shoot, etc.), two things
    //must be done here:
    //  1. find out which worm is controlled by GameControl
    //  2. check if the move is allowed
    private bool checkWormCommand(void delegate(TeamMember w) pass) {
        Team t = ownedTeam();
        if (t) {
            pass(t.current);
            return true;
        }
        return false;
    }

    //Special handling for fire command: while replaying, fire will skip the
    //replay (fast-forward to end)
    //xxx: used to cancel replay mode... can't do this anymore
    //  instead, it's hacked back into gameshell.d somewhere
    private void executeWeaponFire(bool is_down) {
        void fire(TeamMember w) {
            if (is_down) {
                w.control.doFireDown();
            } else {
                w.control.doFireUp();
            }
        }

        if (!checkWormCommand(&fire)) {
            //no worm active
            //spacebar for crate
            mController.instantDropCrate();
        }
    }

    //there's remove_control somewhere in cmdclient.d, and apparently this is
    //  called when a client disconnects; the teams owned by that client
    //  surrender
    private void removeControl() {
        //special handling because teams don't need to be active
        foreach (Team t; mController.teams()) {
            if (checkTeamAccess(mTmp_CurrentAccessTag, t)) {
                t.surrenderTeam();
            }
        }
    }
}
