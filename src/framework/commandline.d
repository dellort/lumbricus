module framework.commandline;

import framework.console;
import framework.framework;
import framework.event;

import str = std.string;
import utf = std.utf;

import utils.mylist;
import utils.mybox;
import utils.array;
import utils.output;
import utils.strparser;

public import utils.mybox : MyBox;
public import utils.output : Output;

//the coin has decided
alias MyBox function(char[] args) TypeHandler;

alias void delegate(MyBox[] args, Output write) CommandHandler;

TypeHandler[char[]] gCommandLineParsers;

static this() {
    gCommandLineParsers["text"] = gBoxParsers[typeid(char[])];
    gCommandLineParsers["int"] = gBoxParsers[typeid(int)];
    gCommandLineParsers["float"] = gBoxParsers[typeid(float)];
    gCommandLineParsers["color"] = gBoxParsers[typeid(Color)];
    gCommandLineParsers["bool"] = gBoxParsers[typeid(bool)];
}

//store stuff about a command
public class Command {
    //use opCall()
    private this() {
    }

    //format for args: each string item describes a parameter, with type and
    //help, and additional flags which influence parsing
    // general syntax: <type>[<flags>]['='<default>][':'<help>]
    // <type> is searched in gCommandLineParsers[]
    // if <flags> is "...", this must be the last parameter, and the rest of the
    //   command line is passed to the type parser (cf. textArgument)
    // if <flag> is "?", this and the following params are optional; they will
    //   be passed as empty box
    // (just an idea, if it's ever needed: <flag>=="@" for arrays)
    // <default> can be given for optional arguments; if an optional argument
    //   isn't available, then this will be passed to the handler
    // <help> is the help text for that parameter
    static Command opCall(char[] name, CommandHandler handler,
        char[] helpText, char[][] args = null)
    {
        Command cmd = new Command();
        cmd.name = name;
        cmd.cmdProc = handler;
        cmd.helpText = helpText;
        cmd.param_help.length = args.length;
        cmd.param_defaults.length = args.length;
        cmd.param_types.length = args.length;
        int firstOptional = -1;
        foreach (int index, char[] arg; args) {
            char[] help = "no help";

            //<rest> ':' <help>
            int p = str.find(arg, ':');
            if (p >= 0) {
                help = arg[p+1..$];
                arg = arg[0..p];
            }
            cmd.param_help[index] = help;

            //<rest> = <default>
            char[] def = "";
            bool have_def = false;
            p = str.find(arg, '=');
            if (p >= 0) {
                def = arg[p+1..$];
                arg = arg[0..p];
                have_def = true;
            }

            //on of ... or ? (they're mutual anyway)
            bool isTextArgument;
             if (arg.length > 4 && arg[$-3..$] == "...") {
                isTextArgument = true;
                arg = arg[0..$-3];
             }
            bool isOptional;
            if (arg.length > 1 && arg[$-1] == '?') {
                isOptional = true;
                arg = arg[0..$-1];
            }
            if (isTextArgument) {
                cmd.textArgument = true;
                if (index + 1 != args.length) {
                    //xxx error handling
                    assert(false, "'...' argument must come last");
                }
            }
            if (isOptional && firstOptional < 0) {
                firstOptional = index;
            }

            //arg contains the type now
            TypeHandler* phandler = arg in gCommandLineParsers;
            if (!phandler) {
                //xxx error handling
                assert(false, "type not found");
            }
            cmd.param_types[index] = *phandler;

            if (have_def) {
                auto box = (*phandler)(def);
                if (box.empty()) {
                    //xxx error handling
                    assert(false, "couldn't parse default param");
                }
                cmd.param_defaults[index] = box;
            }
        }
        cmd.minArgCount = firstOptional < 0 ? args.length : firstOptional;
        return cmd;
    }
private:
    char[] name;
    CommandHandler cmdProc;
    char[] helpText;

    TypeHandler[] param_types;
    MyBox[] param_defaults;
    char[][] param_help;
    int minArgCount;
    //pass rest of the commandline as string for the last parameter
    bool textArgument;

    //find any char from anyof in str and return the first one
    private static int findAny(char[] astr, char[] anyof) {
        //if you like, you can implement an efficient one, hahaha
        int first = -1;
        foreach (char c; anyof) {
            int r = str.find(astr, c);
            if (r > first)
                first = r;
        }
        return first;
    }

    //cur left whitespace
    private static char[] trimLeft(char[] s) {
        while (s.length > 1 && str.iswhite(s[0]))
            s = s[1..$];
        return s;
    }

    //whatever...
    public void parseAndInvoke(char[] cmdline, Output write) {
        MyBox[] args;
        args.length = param_types.length;
        for (int curarg = 0; curarg < param_types.length; curarg++) {
            char[] arg_string;
            //cut leading whitespace only if that's not a textArgument
            bool isTextArg = (textArgument && param_types.length == curarg+1);
            if (!isTextArg) {
                cmdline = trimLeft(cmdline);

                //find end of the argument
                //it end with string end or whitespace, but there can be quotes
                //in the middle of it, which again can contain whitespace...
                bool in_quote;
                bool done;

                while (!(done || cmdline.length == 0)) {
                    if (cmdline[0] == '"') {
                        in_quote = !in_quote;
                    } else {
                        bool iswh = !in_quote && str.iswhite(cmdline[0]);
                        if (!iswh) {
                            arg_string ~= cmdline[0];
                        } else {
                            done = true; //NOTE: also strip this whitespace!
                        }
                    }
                    cmdline = cmdline[1..$];
                }
            }

            //complain and throw up if not valid
            MyBox box = param_types[curarg](arg_string);
            if (box.empty()) {
                if (curarg < minArgCount) {
                    write.writefln("could not parse argument nr. %s", curarg);
                    return;
                }
                box = param_defaults[curarg];
            }
            //xxx stupid hack to support default arguments for strings
            if (arg_string.length == 0 && !param_defaults[curarg].empty()) {
                box = param_defaults[curarg];
            }
            args[curarg] = box;
        }
        cmdline = trimLeft(cmdline);
        if (cmdline.length > 0) {
            write.writefln("Warning: trailing unparsed argument string: '%s'",
                cmdline);
        }

        //successfully parsed, so...:
        if (cmdProc) {
            cmdProc(args, write);
        }
    }
}

//idea:
//bind a bunch of commands to... something
class CommandBucket {
    private Command[] mCommands;
    private CommandLine mBoundTo;

    void register(Command cmd) {
        mCommands ~= cmd;
    }

    void registerCommand(T...)(T) {
        return register(Command(T));
    }

    /// Add commands to there.
    void bind(CommandLine cmdline) {
        assert(mBoundTo is null);
        mBoundTo = cmdline;
        mBoundTo.mCommands ~= mCommands;
    }

    //remove all commands from CommandLine instance again
    void kill() {
        if (!mBoundTo)
            return;
        //the really really rough way...
        Command[] ncmds;
        foreach (Command c; mBoundTo.mCommands) {
            bool hit = false;
            foreach (Command c2; mCommands) {
                if (c is c2) {
                    hit = true;
                    break;
                }
            }
            if (!hit)
                ncmds ~= c;
        }
        mBoundTo.mCommands = ncmds;
        mBoundTo = null;
    }
}

//this was the only list class available :-)
private alias List!(HistoryNode) HistoryList;

private class HistoryNode {
    char[] stuff;
    mixin ListNodeMixin listnode;
}

public class CommandLine {
    private uint mUniqueID; //counter for registerCommand IDs
    private Console mConsole;
    private char[] mCurline;
    private uint mCursor;
    private Command[] mCommands; //xxx: maybe replace by list
    private HistoryList mHistory;
    private uint mHistoryCount; //number of entries in the history
    private HistoryNode mCurrentHistoryEntry;
    private char[] mCommandPrefix;
    private char[] mDefaultCommand;

    private const uint MAX_HISTORY_ENTRIES = 20;
    private const uint MAX_AUTO_COMPLETIONS = 10;

    this(Console cons) {
        mConsole = cons;
        HistoryNode n;
        mHistory = new HistoryList(n.listnode.getListNodeOffset());
        registerCommand(Command("help", &cmdHelp, "Show all commands.",
            ["text?:specific help for a command"]));
        registerCommand(Command("history", &cmdHistory, "Show the history.", null));
    }

    public Console console() {
        return mConsole;
    }

    private void cmdHelp(MyBox[] args, Output write) {
        char[] foo = args[0].unboxMaybe!(char[])("");
        if (foo.length == 0) {
            mConsole.print("List of commands: ");
            uint count = 0;
            foreach (Command c; mCommands) {
                mConsole.writefln("   %s: %s", c.name, c.helpText);
                count++;
            }
            mConsole.writefln("%d commands.", count);
        } else {
            //"detailed" help about one command
            //xxx: maybe replace the exact comparision by calling the auto
            //completion code
            foreach (Command c; mCommands) {
                if (c.name == foo) {
                    mConsole.writefln("Command '%s': %s", c.name, c.helpText);
                    for (int n = 0; n < c.param_types.length; n++) {
                        //reverse lookup type
                        foreach (key, value; gCommandLineParsers) {
                            if (value is c.param_types[n]) {
                                mConsole.writef("    %s ", key);
                            }
                        }
                        if (n >= c.minArgCount) {
                            mConsole.writef("[opt] ");
                        }
                        mConsole.writefln("%s", c.param_help[n]);
                    }
                    if (c.textArgument) {
                        mConsole.writefln("    [text-agument]");
                    }
                    mConsole.writefln("%s arguments.", c.param_types.length);
                    return;
                }
            }
            mConsole.writefln("Command '%s' not found.", foo);
        }
    }

    private void cmdHistory(MyBox[] args, Output write) {
        mConsole.print("History:");
        foreach (HistoryNode hist; mHistory) {
            mConsole.print("   "~hist.stuff);
        }
    }

    public void registerCommand(Command cmd) {
        mCommands ~= cmd;
    }

    public void registerCommand(char[] name, CommandHandler handler,
        char[] helpText, char[][] args = null)
    {
        registerCommand(Command(name, handler, helpText, args));
    }

    /// Set a prefix which is required before each command (disable with ""),
    /// and a default_command, which is invoked when the prefix isn't given.
    public void setPrefix(char[] prefix, char[] default_command) {
        mCommandPrefix = prefix;
        mDefaultCommand = default_command;
    }

    private void updateCursor() {
        mConsole.setCursorPos(mCursor);
    }

    private void updateCmdline() {
        mConsole.setCurLine(mCurline.dup);
        updateCursor();
    }

    public bool keyPress(KeyInfo infos) {
        if (infos.code == Keycode.RIGHT) {
            if (mCursor < mCurline.length)
                mCursor = charNext(mCurline, mCursor);
            updateCursor();
            return true;
        } else if (infos.code == Keycode.LEFT) {
            if (mCursor > 0)
                mCursor = charPrev(mCurline, mCursor);
            updateCursor();
            return true;
        } else if (infos.code == Keycode.BACKSPACE) {
            if (mCursor > 0) {
                int del = mCursor - charPrev(mCurline, mCursor);
                mCurline = mCurline[0 .. mCursor-del] ~ mCurline[mCursor .. $];
                mCursor -= del;
                updateCmdline();
            }
            return true;
        } else if (infos.code == Keycode.DELETE) {
            if (mCursor < mCurline.length) {
                int del = utf.stride(mCurline, mCursor);
                mCurline = mCurline[0 .. mCursor] ~ mCurline[mCursor+del .. $];
                updateCmdline();
            }
            return true;
        } else if (infos.code == Keycode.HOME) {
            mCursor = 0;
            updateCursor();
            return true;
        } else if (infos.code == Keycode.END) {
            mCursor = mCurline.length;
            updateCursor();
            return true;
        } else if (infos.code == Keycode.TAB) {
            do_tab_completion();
            return true;
        } else if (infos.code == Keycode.RETURN) {
            do_execute();
            return true;
        } else if (infos.code == Keycode.UP) {
            HistoryNode next_hist;
            if (mCurrentHistoryEntry) {
                next_hist = mHistory.prev(mCurrentHistoryEntry);
            } else {
                next_hist = mHistory.tail();
            }
            if (next_hist) {
                select_history_entry(next_hist);
            }
            return true;
        } else if (infos.code == Keycode.DOWN) {
            if (mCurrentHistoryEntry) {
                HistoryNode next_hist = mHistory.next(mCurrentHistoryEntry);
                select_history_entry(next_hist);
            }
            return true;
        } else if (infos.code == Keycode.PAGEUP) {
            mConsole.scrollBack(1);
            return true;
        } else if (infos.code == Keycode.PAGEDOWN) {
            mConsole.scrollBack(-1);
            return true;
        } else if (infos.isPrintable()) {
            //printable char
            char[] append;
            if (!utf.isValidDchar(infos.unicode)) {
                append = "?";
            } else {
                append = utf.toUTF8([infos.unicode]);
            }
            mCurline = mCurline[0 .. mCursor] ~ append ~ mCurline[mCursor .. $];
            mCursor += utf.stride(mCurline, mCursor);
            updateCmdline();
            return true;
        }
        return false;
    }

    private void select_history_entry(HistoryNode newentry) {
        char[] newline;

        mCurrentHistoryEntry = newentry;

        if (newentry) {
            newline = newentry.stuff;
        } else {
            newline = null;
        }

        mCurline = newline;
        mCursor = mCurline.length;
        updateCmdline();
    }

    //get the command part of the command line
    //sets mCommandStart and mCommandEnd
    private bool parseCommand(out char[] command, out char[] args,
        out uint start, out uint end)
    {
        auto plen = mCommandPrefix.length;
        auto line = mCurline;
        if (line[0..plen] == mCommandPrefix) {
            line = line[plen..$]; //skip prefix
            line = str.stripl(line); //skip whitespace
            start = mCurline.length - line.length; //start offset
            auto first_whitespace = str.find(line, ' ');
            if (first_whitespace >= 0) {
                command = line[0..first_whitespace];
                end = start + first_whitespace;
                args = line[first_whitespace+1..$];
            } else {
                command = line;
                end = start + line.length;
            }
        } else {
            command = mDefaultCommand;
            args = line;
        }
        return command.length > 0;
    }

    private void do_execute(bool addHistory = true) {
        char[] cmd, args;
        uint start, end; //not really needed

        if (!parseCommand(cmd, args, start, end)) {
            //nothing, but show some reaction...
            mConsole.print("-");
        } else {
            if (addHistory) {
                //into the history
                HistoryNode histent = new HistoryNode();
                histent.stuff = mCurline.dup;
                mHistory.insert_tail(histent);
                mHistoryCount++;

                if (mHistoryCount > MAX_HISTORY_ENTRIES) {
                    mHistory.remove(mHistory.head);
                }

                mCurrentHistoryEntry = null;
            }

            Command[] throwup;
            auto ccmd = find_command_completions(cmd, throwup);
            //accept unique partial matches
            if (!ccmd && throwup.length == 1) {
                ccmd = throwup[0];
            }
            if (!ccmd) {
                mConsole.print("Unknown command: "~cmd);
            } else {
                ccmd.parseAndInvoke(args, mConsole);
            }
        }

        mCurline = null;
        mCursor = 0;
        updateCmdline();
    }

    /// Execute any command from outside.
    public void execute(char[] cmd, bool addHistory = true) {
        //xxx hacky
        mCurline = cmd.dup;
        mCursor = mCurline.length;
        updateCmdline();
        do_execute(addHistory);
    }

    private void do_tab_completion() {
        char[] cmd, args;
        uint start, end;
        if (!parseCommand(cmd, args, start, end) || start == end)
            return;
        Command[] res;
        Command exact = find_command_completions(cmd, res);

        if (res.length == 0) {
            //no hit, too bad, maybe beep?
        } else {
            //get biggest common starting-string of all completions
            char[] common = res[0].name;
            foreach (Command ccmd; res[1..$]) {
                if (ccmd.name.length < common.length)
                    common = ccmd.name.dup; //dup: because we set length below
                //xxx incorrect utf-8 handling
                foreach (uint index, char c; common) {
                    if (ccmd.name[index] != c) {
                        common.length = index;
                        break;
                    }
                }
            }

            /*//if there's only one completion, add a space
            if (res.length == 1)
                common ~= ' ';*/

            if (common.length > cmd.length) {
                //if there's a common substring longer than the commonrent
                //  command, extend it

                mCurline = mCurline[0..start] ~ common
                    ~ mCurline[end..$];
                mCursor = start + common.length; //end of the command
                updateCmdline();
            } else {
                if (res.length > 1) {
                    //write them to the output screen
                    mConsole.print("Tab completions:");
                    bool toomuch = (res.length == MAX_AUTO_COMPLETIONS);
                    if (toomuch) res = res[0..$-1];
                    foreach (Command ccmd; res) {
                        mConsole.print(ccmd.name);
                    }
                    if (toomuch)
                        mConsole.print("...");
                } else {
                    //one hit, since the case wasn't catched above, this means
                    //it's already complete?
                    mConsole.print("?");
                }
            }
        }

    }

    //if there's a perfect match (whole string equals), then it is returned,
    //  else return null
    private Command find_command_completions(char[] cmd, inout Command[] res) {
        Command exact;

        res.length = 0;

        foreach (Command cur; mCommands) {
            //xxx: make string comparisions case insensitive
            //xxx: incorrect utf-8 handling?
            if (cur.name.length >= cmd.length
                && cmd == cur.name[0 .. cmd.length])
            {
                res = res ~ cur;
                if (cmd == cur.name) {
                    exact = cur;
                }
            }
            if (res.length >= MAX_AUTO_COMPLETIONS)
                break;
        }

        return exact;
    }
}

debug import std.stdio;

unittest {
    /+
    void handler(MyBox[] args, Output write) {
        foreach(int index, MyBox b; args) {
            debug writefln("%s: %s", index, boxToString(b));
        }
    }
    auto c1 = Command("foo", &handler, "blah", [
        "int:hello",
        "float:bla",
        "text:huh",
        "int?=789:fff",
        "text?=haha:bla2"
        ]);
    c1.parseAndInvoke("5   1.2 \"hal  l ooo\"  ", StdioOutput.output);

    debug writefln("commandline.d unittest: passed.");
    +/
}
