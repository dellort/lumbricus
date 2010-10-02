module game.input;

import utils.array;
import utils.configfile;
import utils.misc;
import utils.strparser;

import str = utils.string;

//return (cmd-name, cmd-args)
str.Split2Result parseCommand(char[] cmd) {
    return str.split2_b(cmd, ' ');
}

class Input {
    //client_id: identifier for sender (e.g. in network case)
    //args: command arguments (without name)
    alias bool delegate(char[] client_id, char[] args) Endpoint;

    //client_id: see Endpoint
    //name: command name (without arguments)
    //xxx: don't know if I'll keep this (it made the code simpler for now)
    //  another possibility is to kill class Input and replace it by a delegate
    abstract Endpoint findCommand(char[] client_id, char[] name);

    //-- helpers ("frontend" stuff for the user)

    //a client with client_id checks if the keybinding in cmd could be executed
    //  if it were sent to execCommand()
    final bool checkCommand(char[] client_id, char[] cmd) {
        auto pcmd = parseCommand(cmd);
        return !!findCommand(client_id, pcmd[0]);
    }

    //execute a command; if the command has parameters, the parameters are
    //  considered to start after the first space character
    final bool execCommand(char[] client_id, char[] cmd) {
        auto pcmd = parseCommand(cmd);
        auto endp = findCommand(client_id, pcmd[0]);
        if (!endp)
            return false;
        return endp(client_id, pcmd[1]);
    }
}

//redirect input to a specific other Input instance based on client_id
class InputProxy : Input {
    Input delegate(char[]) onDispatch;

    this(Input delegate(char[]) a_onDispatch) {
        onDispatch = a_onDispatch;
    }

    Input getDispatcher(char[] client_id) {
        return onDispatch ? onDispatch(client_id) : null;
    }

    override Endpoint findCommand(char[] client_id, char[] name) {
        if (auto inp = getDispatcher(client_id))
            return inp.findCommand(client_id, name);
        return null;
    }
}

//a list of input commands or sub-Inputs for a specific component
class InputGroup : Input {
    private {
        //list of commands and their actions
        Command[] mCommands;

        //each entry is either a command, or a sub-input
        struct Command {
            //if non-null, this is a sub-input
            Input sub;
            //otherwise, a normal command entry
            //identifies this entry in the key bindings map
            //it is assumed it contains no spaces (see execCommand())
            char[] name;
            bool delegate(char[] client_id, char[] params) callback;
        }
    }

    //this can be freely set by the code which provides the input handler
    //  callbacks; if false, all input is rejected
    bool enabled = true;

    //cb: takes client_id and the command's parameters
    //(as frontend function the least common case; only needed for cheats, urgh)
    void add(char[] name, bool delegate(char[], char[]) cb) {
        argcheck(name.length > 0);
        argcheck(!!cb);
        foreach (ref c; mCommands) {
            if (c.name == name)
                throwError("command already added: '{}'", name);
        }
        mCommands ~= Command(null, name, cb);
    }

    //add an input command - cb will be called if the input is executed
    //"name" is a symbolic identifier defined in the keybindings (such as
    //  wormbinds.conf)
    //cb: takes the command's parameters, and returns whether the command has
    //  been accepted (if not, other InputGroups that may contain the same
    //  command will be tried)
    void add(char[] name, bool delegate(char[]) cb) {
        struct Closure {
            bool delegate(char[]) cb;
            bool call(char[] client_id, char[] params) { return cb(params); }
        }
        auto c = new Closure;
        c.cb = cb;
        add(name, &c.call);
    }

    //like other add()s, but with no parameters for cb
    void add(char[] name, bool delegate() cb) {
        struct Closure {
            bool delegate() cb;
            bool call(char[] client_id, char[] params) { return cb(); }
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
            bool call(char[] client_id, char[] params) {
                return cb(parseParams!(T)(params).expand);
            }
        }
        auto c = new Closure;
        c.cb = cb;
        add(name, &c.call);
    }

    void addSub(Input sub) {
        argcheck(sub);
        mCommands ~= Command(sub, null, null);
    }

    //void remove(char[] name) {
    //}
    //void removeSub(Input sub) {
    //}

    private bool checkAccess(char[] client_id) {
        return enabled;
    }

    override Endpoint findCommand(char[] client_id, char[] name) {
        if (!checkAccess(client_id))
            return null;

        foreach (ref cmd; mCommands) {
            if (cmd.sub) {
                auto x = cmd.sub.findCommand(client_id, name);
                if (!!x)
                    return x;
            } else if (cmd.name == name) {
                return cmd.callback;
            }
        }

        return null;
    }
}

//convenience function for parameter parsing
//returns true on success or false on failure
//doesn't change "result" if it fails
bool parseParamsMaybe(T...)(char[] s, ref Tuple!(T) result) {
    try {
        Tuple!(T) ret;
        foreach (uint idx, x; ret.fields) {
            static if (is(typeof(x) == char[])) {
                if (idx + 1 == T.length) {
                    //last type is a string => include everything, including
                    //  whitespace
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
        result = ret;
        return true;
    } catch (ConversionException e) {
        return false;
    }
}

//don't-care-if-error version of parseParams()
Tuple!(T) parseParams(T...)(char[] s) {
    Tuple!(T) res;
    parseParamsMaybe!(T)(s, res);
    return res;
}


//convenience code for handling dir keys (key state for LEFT/RIGHT and UP/DOWN)
//doesn't really belong in this module
//xxx: maybe come up with an idea so that the caller doesn't need to handle
//  this; maybe directly in processBindings()

import utils.vector2;

struct MoveStateXY {
    Vector2i keyState_lu;  //left/up
    Vector2i keyState_rd;  //right/down

    Vector2i direction() {
        return keyState_rd - keyState_lu;
    }

    bool handleKeys(char[] key, bool down) {
        int v = down ? 1 : 0;
        switch (key) {
            case "left":
                keyState_lu.x = v;
                break;
            case "right":
                keyState_rd.x = v;
                break;
            case "up":
                keyState_lu.y = v;
                break;
            case "down":
                keyState_rd.y = v;
                break;
            default:
                //--xxx reset on invalid key; is this kosher?
                //--keyState_rd = Vector2i(0);
                //--keyState_lu = Vector2i(0);
                return false;
        }
        return true;
    }

    bool handleCommand(char[] args) {
        auto p = parseParams!(char[], bool)(args);
        return handleKeys(p.expand);
    }

    void reset() {
        keyState_lu = keyState_rd = Vector2i.init;
    }

    char[] toString() {
        return myformat("lu={} ld={} dir={}", keyState_lu, keyState_rd,
            direction);
    }
}

