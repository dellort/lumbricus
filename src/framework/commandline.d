module framework.commandline;

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
            if (isTextArg) {
                arg_string = cmdline;
                cmdline = null;
            } else {
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
            if (arg_string.length == 0 && curarg >= minArgCount) {
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
    private {
        Command[] mCommands;
        CommandBucket[] mSubs;
        CommandBucket[] mParent; //lol, don't ask...
        Entry[] mSorted;   //sorted list of commands, including subs
    }

    //entry for each command
    struct Entry {
        char[] alias_name;
        Command cmd;

        //NOTE: sorted() uses the fact that it's sorted by name to eliminate
        //      double entries
        int opCmp(Entry* other) {
            return str.cmp(alias_name, other.alias_name);
        }
    }

    void register(Command cmd) {
        mCommands ~= cmd;
        invalidate();
    }

    public void registerCommand(Command cmd) {
        register(cmd);
    }

    public void registerCommand(char[] name, CommandHandler handler,
        char[] helpText, char[][] args = null)
    {
        register(Command(name, handler, helpText, args));
    }

    /// Merge the commands from sub with this
    void addSub(CommandBucket sub) {
        removeSub(sub); //just to be safe
        mSubs ~= sub;
        sub.mParent ~= this;
        invalidate();
    }

    void bind(CommandLine cmdline) {
        cmdline.commands.addSub(this);
    }

    void removeSub(CommandBucket sub) {
        if (arraySearch(mSubs, sub) < 0)
            return;
        arrayRemove(mSubs, sub);
        arrayRemove(sub.mParent, this);
        invalidate();
    }

    void kill() {
        while (mParent.length)
            mParent[0].removeSub(this);
    }

    //clear command cache
    void invalidate() {
        mSorted = null;
        foreach (p; mParent)
            p.invalidate();
    }

    Entry[] sorted() {
        if (mSorted.length == 0) {
            //recursively add from all sub-entries etc.
            void doAdd(CommandBucket b) {
                foreach (m; b.mCommands) {
                    mSorted ~= Entry(m.name, m);
                }
                foreach (s; b.mSubs) {
                    doAdd(s);
                }
            }
            doAdd(this);

            //sort the mess and deal with double entries
            for (;;) {
                bool change = false;
                mSorted.sort;
                char[] last_entry;
                int n_entry;
                foreach (inout e; mSorted) {
                    if (e.alias_name == last_entry) {
                        change = true;
                        n_entry++;
                        e.alias_name = format("%s_%d", last_entry, n_entry);
                    } else {
                        last_entry = e.alias_name;
                        n_entry = 1;
                    }
                }
                if (!change)
                    break;
            }
        }
        return mSorted;
    }
}

///stateless part of the commandline, where commands are registered
public class CommandLine {
    private CommandBucket mCommands;
    private char[] mCommandPrefix;
    private char[] mDefaultCommand;
    private CommandLineInstance mDefInstance; //to support execute()

    CommandBucket commands() {
        return mCommands;
    }

    //def_output: output for execute(), normally you use your own
    //CommandLineInstance, which can have its own output
    this(Output def_output) {
        mCommands = new CommandBucket;
        mDefInstance = new CommandLineInstance(this, def_output);
    }

    public void registerCommand(Command cmd) {
        mCommands.register(cmd);
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

    public void execute(char[] cmdline) {
        mDefInstance.execute(cmdline, false);
    }
}

///stateful part of the commandline (i.e. history)
class CommandLineInstance {
    private {
        //this was the only list class available :-(
        alias List!(HistoryNode) HistoryList;

        class HistoryNode {
            char[] stuff;
            mixin ListNodeMixin listnode;
        }

        CommandLine mCmdline;
        CommandBucket mCommands;
        Output mConsole;
        HistoryList mHistory;
        HistoryNode mCurrentHistoryEntry;

        const uint MAX_HISTORY_ENTRIES = 20;
        const uint MAX_AUTO_COMPLETIONS = 10;

        alias CommandBucket.Entry CommandEntry;
    }

    this(CommandLine cmdline, Output output) {
        mConsole = output;
        mCmdline = cmdline;
        mCommands = new CommandBucket;
        mCommands.addSub(mCmdline.mCommands);
        HistoryNode n;
        mHistory = new HistoryList(n.listnode.getListNodeOffset());
        mCommands.registerCommand(Command("help", &cmdHelp,
            "Show all commands.", ["text?:specific help for a command"]));
        mCommands.registerCommand(Command("history", &cmdHistory,
            "Show the history.", null));
    }

    private void cmdHelp(MyBox[] args, Output write) {
        char[] foo = args[0].unboxMaybe!(char[])("");
        if (foo.length == 0) {
            mConsole.writefln("List of commands: ");
            uint count = 0;
            foreach (c; mCommands.sorted) {
                mConsole.writefln("   %s: %s", c.alias_name, c.cmd.helpText);
                count++;
            }
            mConsole.writefln("%d commands.", count);
        } else {
            //"detailed" help about one command
            //xxx: maybe replace the exact comparision by calling the auto
            //completion code
            CommandEntry[] reslist;
            auto exact = find_command_completions(foo, reslist);
            if (!exact.cmd && reslist.length == 1) {
                exact = reslist[0];
            }
            if (exact.cmd) {
                auto c = exact.cmd;
                mConsole.writefln("Command '%s' ('%s'): %s", exact.alias_name,
                    c.name, c.helpText);
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
            } else if (reslist.length) {
                mConsole.writefln("matches:");
                foreach (e; reslist) {
                    mConsole.writefln("   %s", e.alias_name);
                }
                return;
            }
            mConsole.writefln("Command '%s' not found.", foo);
        }
    }

    private void cmdHistory(MyBox[] args, Output write) {
        mConsole.writefln("History:");
        foreach (HistoryNode hist; mHistory) {
            mConsole.writefln("   "~hist.stuff);
        }
    }

    /// Search through the history, dir is either -1 or +1
    /// Returned string must not be modified.
    public char[] selectHistory(char[] cur, int dir) {
        if (dir == -1) {
            HistoryNode next_hist;
            if (mCurrentHistoryEntry) {
                next_hist = mHistory.prev(mCurrentHistoryEntry);
            } else {
                next_hist = mHistory.tail();
            }
            if (next_hist) {
                return select_history_entry(next_hist);
            }
        } else if (dir == +1) {
            if (mCurrentHistoryEntry) {
                HistoryNode next_hist = mHistory.next(mCurrentHistoryEntry);
                return select_history_entry(next_hist);
            }
        }
        return cur;
    }

    private char[] select_history_entry(HistoryNode newentry) {
        char[] newline;

        mCurrentHistoryEntry = newentry;

        if (newentry) {
            newline = newentry.stuff;
        } else {
            newline = null;
        }

        return newline;
    }

    //get the command part of the command line
    private bool parseCommand(char[] line, out char[] command, out char[] args,
        out uint start, out uint end)
    {
        auto plen = mCmdline.mCommandPrefix.length;
        auto len = line.length;
        if (len >= plen && line[0..plen] == mCmdline.mCommandPrefix) {
            line = line[plen..$]; //skip prefix
            line = str.stripl(line); //skip whitespace
            start = len - line.length; //start offset
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
            command = mCmdline.mDefaultCommand;
            args = line;
        }
        return command.length > 0;
    }

    /// Execute any command from outside.
    public void execute(char[] cmdline, bool addHistory = true) {
        char[] cmd, args;
        uint start, end; //not really needed

        if (!parseCommand(cmdline, cmd, args, start, end)) {
            //nothing, but show some reaction...
            mConsole.writefln("-");
        } else {
            if (addHistory) {
                //into the history
                HistoryNode histent = new HistoryNode();
                histent.stuff = cmdline.dup;
                mHistory.insert_tail(histent);

                if (mHistory.count() > MAX_HISTORY_ENTRIES) {
                    mHistory.remove(mHistory.head);
                }

                mCurrentHistoryEntry = null;
            }

            CommandEntry[] throwup;
            auto cccmd = find_command_completions(cmd, throwup);
            auto ccmd = cccmd.cmd;
            //accept unique partial matches
            if (!ccmd && throwup.length == 1) {
                ccmd = throwup[0].cmd;
            }
            if (!ccmd) {
                mConsole.writefln("Unknown command: "~cmd);
            } else {
                ccmd.parseAndInvoke(args, mConsole);
            }
        }
    }

    /// Replace the text between start and end by text
    /// operation: newline = line[0..start] ~ text ~ line[end..$];
    public alias void delegate(int start, int end, char[] text) EditDelegate;

    /// Do tab completion for the given line. The delegate by edit inserts
    /// completed text.
    /// at = cursor position; currently unused
    public void tabCompletion(char[] line, int at, EditDelegate edit) {
        char[] cmd, args;
        uint start, end;
        if (!parseCommand(line, cmd, args, start, end) || start == end)
            return;
        CommandEntry[] res;
        CommandEntry exact = find_command_completions(cmd, res);

        if (res.length == 0) {
            //no hit, too bad, maybe beep?
        } else {
            //get biggest common starting-string of all completions
            char[] common = res[0].alias_name;
            foreach (CommandEntry ccmd; res[1..$]) {
                if (ccmd.alias_name.length < common.length)
                    common = ccmd.alias_name.dup; //dup: because we set length below
                //xxx incorrect utf-8 handling
                foreach (uint index, char c; common) {
                    if (ccmd.alias_name[index] != c) {
                        common.length = index;
                        break;
                    }
                }
            }

            if (common.length > cmd.length) {
                //if there's a common substring longer than the commonrent
                //  command, extend it

                edit(start, end, common);
            } else {
                if (res.length > 1) {
                    //write them to the output screen
                    mConsole.writefln("Tab completions:");
                    bool toomuch = (res.length == MAX_AUTO_COMPLETIONS);
                    if (toomuch) res = res[0..$-1];
                    foreach (CommandEntry ccmd; res) {
                        mConsole.writefln("  %s", ccmd.alias_name);
                    }
                    if (toomuch)
                        mConsole.writefln("...");
                } else {
                    //one hit, since the case wasn't catched above, this means
                    //it's already complete
                    //insert a space after the command, if there isn't yet
                    if (!(end < line.length && line[end] == ' '))
                        edit(end, end, " ");
                }
            }
        }

    }

    //if there's a perfect match (whole string equals), then it is returned,
    //  else return null (for the .cmd field)
    private CommandEntry find_command_completions(char[] cmd,
        inout CommandEntry[] res)
    {
        CommandEntry exact;

        res.length = 0;

        foreach (CommandEntry cur; mCommands.sorted) {
            //xxx: make string comparisions case insensitive
            //xxx: incorrect utf-8 handling?
            if (cur.alias_name.length >= cmd.length
                && cmd == cur.alias_name[0 .. cmd.length])
            {
                res = res ~ cur;
                if (cmd == cur.alias_name) {
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
