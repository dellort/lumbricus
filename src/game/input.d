module game.input;

import utils.array;
import utils.configfile;
import utils.misc;
import utils.strparser;

import str = utils.string;

//a list of input commands for a specific component
class InputGroup {
    private {
        //list of commands and their actions
        Command[] mCommands;

        struct Command {
            //identifies this entry in the key bindings map
            //it is assumed it contains no spaces (see execCommand())
            char[] name;
            bool delegate(char[] params) callback;
        }
    }

    //in case multiple InputGroup accept the same key, higher priority means
    //  it's tested before other InputGroups
    //xxx doesn't get updated while added to InputHandlers
    int priority = 0;

    //if set, it checks if a client is allowed
    //if null, it's as if it was set to a function that always returns true
    bool delegate(char[] client_id) onCheckAccess;

    void add(char[] name, bool delegate(char[]) cb) {
        argcheck(name.length > 0);
        argcheck(!!cb);
        if (findCommand(name))
            throwError("command already added: '{}'", name);
        mCommands ~= Command(name, cb);
    }

    void add(char[] name, bool delegate() cb) {
        struct Closure {
            bool delegate() cb;
            bool call(char[] params) { return cb(); }
        }
        auto c = new Closure;
        c.cb = cb;
        add(name, &c.call);
    }

    //aww shit I couldn't resist
    //this will automatically parse the parameter according to the passed cb
    void addT(T...)(char[] name, bool delegate(T) cb) {
        struct Closure {
            bool delegate(T) cb;
            bool call(char[] params) {
                return cb(parseParams!(T)(params).expand);
            }
        }
        auto c = new Closure;
        c.cb = cb;
        add(name, &c.call);
    }

    //void remove(char[] name) {
    //}

    bool checkAccess(char[] client_id) {
        if (!onCheckAccess)
            return true;
        return onCheckAccess(client_id);
    }

    private Command* findCommand(char[] name) {
        foreach (ref cmd; mCommands) {
            if (cmd.name == name)
                return &cmd;
        }
        return null;
    }

    private Command* do_check_cmd(char[] client_id, char[] cmd) {
        if (!checkAccess(client_id))
            return null;

        auto cmd_name = str.split2(cmd, ' ')[0];
        return findCommand(cmd_name);
    }

    bool checkCommand(char[] client_id, char[] cmd) {
        return !!do_check_cmd(client_id, cmd);
    }

    bool execCommand(char[] client_id, char[] cmd) {
        Command* pcmd = do_check_cmd(client_id, cmd);

        if (!pcmd)
            return false;

        auto params = str.split2_b(cmd, ' ')[1];
        return pcmd.callback(params);
    }
}

//singleton that dispatches user input
class InputHandler {
    private {
        InputGroup[] mGroups;
    }

    //determines which network clients are allowed to control which teams
    //each array item is a pair of strings:
    // [client_id, team_id]
    //it means that that client is allowed to control that team
    char[][2][] accessMap;

    void loadAccessMap(ConfigNode node) {
        foreach (ConfigNode sub; node) {
            //sub is "tag_name { "teamid1" "teamid2" ... }"
            foreach (char[] key, char[] value; sub) {
                accessMap ~= [sub.name, value];
            }
        }
    }

    bool checkAccess(char[] client_id, char[] team_id) {
        foreach (a; accessMap) {
            if (a[0] == client_id && a[1] == team_id)
                return true;
        }
        return false;
    }

    //add if not already added
    //being added means whether that group can receive input from here or not
    void enableGroup(InputGroup g) {
        if (arraySearch(mGroups, g) < 0) {
            mGroups ~= g;
            stableSort(mGroups,
                (InputGroup g1, InputGroup g2) {
                    return g1.priority > g2.priority;
                }
            );
        }
    }

    //remove if it's added
    void disableGroup(InputGroup g) {
        arrayRemove(mGroups, g, true);
    }

    void setEnableGroup(InputGroup g, bool enable) {
        if (enable) {
            enableGroup(g);
        } else {
            disableGroup(g);
        }
    }

    //a client with client_id checks if the keybinding in cmd could be executed
    //  if it were sent to execCommand()
    bool checkCommand(char[] client_id, char[] cmd) {
        foreach (g; mGroups) {
            if (g.checkCommand(client_id, cmd))
                return true;
        }
        return false;
    }

    //include a command; if the command has parameters, the parameters are
    //  considered to start after the first space character
    bool execCommand(char[] client_id, char[] cmd) {
        foreach (g; mGroups) {
            if (g.execCommand(client_id, cmd))
                return true;

            //xxx not sure: if several InputGroups accept the same command,
            //  prefer the first registration; if it returns false (didn't
            //  consume the input event), try the next one => continue loop
        }

        return false;
    }
}

//convenience function for parameter parsing
//may throw ConversionException
Tuple!(T) parseParamsChecked(T...)(char[] s) {
    Tuple!(T) ret;
    foreach (uint idx, x; ret.fields) {
        static if (is(typeof(x) == char[])) {
            if (idx + 1 == T.length) {
                //last type is a string => include everything, including whitespace
                ret.fields[idx] = s;
                s = "";
                break;
            }
        }
        auto n = str.split2_b(s, ' ');
        s = n[1];
        ret.fields[idx] = fromStr!(typeof(x))(n[0]);
    }
    if (s.length > 0)
        throw new ConversionException("unparseable stuff at end of string");
    return ret;
}

//don't-care-if-error version of parseParams()
Tuple!(T) parseParams(T...)(char[] s) {
    try {
        return parseParamsChecked!(T)(s);
    } catch (ConversionException e) {
        return (Tuple!(T)).init;
    }
}

