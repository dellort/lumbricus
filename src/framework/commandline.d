module framework.commandline;

import framework.event;
import framework.i18n;

import str = utils.string;

import utils.color;
import utils.log;
import utils.misc;
import utils.mybox;
import utils.array;
import utils.output;
import utils.strparser;
import utils.time;

//the coin has decided
alias MyBox function(string args) TypeHandler;

alias void delegate(MyBox[] args, Output write) CommandHandler;
alias string[] delegate() CompletionHandler;

TypeHandler[string] gCommandLineParsers;
string[TypeInfo] gCommandLineParserTypes; //kind of reverse lookup
CompletionHandler[string] gCommandLineCompletionHandlers;

static this() {
    void add(string name, TypeInfo t) {
        gCommandLineParsers[name] = gBoxParsers[t];
        gCommandLineParserTypes[t] = name;
    }
    add("text", typeid(string));
    add("int", typeid(int));
    add("float", typeid(float));
    add("color", typeid(Color));
    add("bool", typeid(bool));
    add("Time", typeid(Time));

    string[] complete_bool() {
        return ["true", "false"];
    }
    gCommandLineCompletionHandlers["bool"] = &complete_bool;
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
    static Command opCall(string name, CommandHandler handler,
        string helpText, string[] args = null, CompletionHandler[] compl = null)
    {
        Command cmd = new Command();
        cmd.name = name;
        cmd.cmdProc = handler;
        cmd.helpText = helpText;
        cmd.param_help.length = args.length;
        cmd.param_defaults.length = args.length;
        cmd.param_types.length = args.length;
        cmd.completions.length = args.length;
        int firstOptional = -1;
        foreach (int index, string arg; args) {
            string help = "no help";

            //<rest> ':' <help>
            auto p = str.find(arg, ':');
            if (p >= 0) {
                help = arg[p+1..$];
                arg = arg[0..p];
            }
            cmd.param_help[index] = help;

            //<rest> = <default>
            string def = "";
            bool have_def = false;
            p = str.find(arg, '=');
            if (p >= 0) {
                def = arg[p+1..$];
                arg = arg[0..p];
                have_def = true;
            }

            //on of ... or ?, or both
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

            CompletionHandler* chandler = arg in gCommandLineCompletionHandlers;
            if (chandler) {
                cmd.completions[index] = *chandler;
            }

            if (index < compl.length && compl[index]) {
                cmd.completions[index] = compl[index];
            }

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

    void setCompletionHandler(int narg, CompletionHandler get_completions) {
        completions[narg] = get_completions;
    }

private:
    string name;
    CommandHandler cmdProc;
    string helpText;

    TypeHandler[] param_types;
    MyBox[] param_defaults;
    string[] param_help;
    size_t minArgCount;
    //pass rest of the commandline as string for the last parameter
    bool textArgument;

    //for each param; null item if not available
    CompletionHandler[] completions;

    public struct CmdItem {
        //parsed string (i.e. quotes and escapes removed)
        string s;
        //start and end in the raw string (without surrounding white space)
        size_t start, end;
    }
    public static CmdItem[] parseLine(string cmdline) {
        CmdItem[] res;
        size_t orglen = cmdline.length;

        for (;;) {
            //leading whitespace
            cmdline = str.stripl(cmdline);

            if (!cmdline.length)
                break;

            assert(orglen >= cmdline.length);
            size_t start = orglen - cmdline.length;

            //find end of the argument
            //it end with string end or whitespace, but there can be quotes
            //in the middle of it, which again can contain whitespace...
            bool in_quote;
            bool done;
            string arg_string;

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

            size_t end = orglen - cmdline.length;
            res ~= CmdItem(arg_string, start, end);
        }

        return res;
    }

    //parse the commandline and fix it up to respect the text argument
    //it just does that, no further error handling or checking etc.
    public CmdItem[] parseLine2(string cmdline) {
        CmdItem[] items = parseLine(cmdline);
        if (textArgument) {
            assert(param_types.length > 0);
            // this fixes an out of bounds access below when doing "spawn "<tab>
            // in the command line (it's a regression since this commit, didn't
            // pursue why)
            if (items.length < param_types.length)
                return items;
            size_t start = param_types.length - 1;
            sizediff_t end = items.length - 1;
            if (end >= start) {
                CmdItem nitem;
                nitem.start = items[start].start;
                //hack: if it's the first element, don't kill the whitespace
                //preceeding it
                if (start == 0)
                    nitem.start = 0;
                nitem.end = items[end].end;
                //no escaping etc.
                nitem.s = cmdline[nitem.start .. nitem.end];
                items = items[0..start] ~ nitem;
            }
        }
        return items;
    }

    //for per-argument autocompletion
    // cmdline: complete commandline, cursor: cursor position, points into
    // cmdline, argument: argument number, preceeding: text in the current
    // argument, which is preceeding the cursor
    //returns true if output params are valid
    public bool findArgAt(string cmdline, size_t cursor, out size_t argument,
        out string preceeding)
    {
        //only parse up to the cursor => simpler
        assert(cursor <= cmdline.length);
        CmdItem[] items = parseLine2(cmdline[0..cursor]);
        if (items.length == 0) {
            argument = 0;
        } else {
            argument = items.length - 1;
            preceeding = items[argument].s;
        }
        return (argument < param_types.length);
    }

    //parse and invoke commandline, return if parsing was successful
    public bool parseAndInvoke(string cmdline, Output write) {
        CmdItem[] items = parseLine2(cmdline);
        int last_item;
        MyBox[] args;
        args.length = param_types.length;
        for (int curarg = 0; curarg < param_types.length; curarg++) {
            MyBox box;

            if (curarg < items.length) {
                last_item = curarg;
                box = param_types[curarg](items[curarg].s);
            }

            //complain and throw up if not valid
            if (box.empty()) {
                if (curarg < minArgCount) {
                    write.writefln("could not parse argument nr. %s", curarg);
                    return false;
                }
                box = param_defaults[curarg];
            }

            args[curarg] = box;
        }

        if (last_item < cast(int)items.length - 1) {
            write.writefln("Warning: trailing unparsed argument string: '%s'",
                cmdline[items[last_item+1].start .. items[$-1].end]);
        }

        //successfully parsed, so...:
        if (cmdProc) {
            try {
                cmdProc(args, write);
            } catch (CustomException e) {
                write.writefln("error when executing command: %s", e);
                traceException(gLog, e,
                    myformat("executing '%s %s'", name, cmdline));
            }
        }

        return true;
    }
}

//idea:
//bind a bunch of commands to... something
class CommandBucket {
    private {
        Command[] mCommands;
        CommandBucket[] mSubs;
        Translator mHelpTrans;
    }

    //hack to get more sub-commands
    //common/toplevel.d uses this to delegate commands to the current active
    //  window
    CommandBucket delegate() onGetSubCommands;

    //entry for each command
    struct Entry {
        string alias_name;
        Command cmd;
        private Translator mTrans;

        //NOTE: sorted() uses the fact that it's sorted by name to eliminate
        //      double entries
        int opCmp(Entry* other) {
            return str.cmp(alias_name, other.alias_name);
        }

        string toString() {
            return alias_name ~ " -> " ~ cmd.name;
        }

        //(possibly translated) help text for this command
        string helpText() {
            if (mTrans && mTrans.hasId(cmd.name)) {
                return mTrans(cmd.name);
            } else {
                return cmd.helpText;
            }
        }

        //(possibly translated) help text for parameter idx
        string paramHelp(int idx) {
            assert(idx < cmd.param_types.length);
            string id = myformat("%s_arg%s", cmd.name, idx);
            if (mTrans && mTrans.hasId(id)) {
                return mTrans(id);
            } else {
                return cmd.param_help[idx];
            }
        }

        void showShortHelp(Output write) {
            write.writefln("   %s: %s", alias_name, helpText());
        }

        void showHelp(Output write) {
            write.writefln("Command '%s' ('%s'): %s", alias_name,
                cmd.name, helpText());
            for (int n = 0; n < cmd.param_types.length; n++) {
                //reverse lookup type
                foreach (key, value; gCommandLineParsers) {
                    if (value is cmd.param_types[n]) {
                        write.writef("    %s ", key);
                    }
                }
                if (n >= cmd.minArgCount) {
                    write.writef("[opt] ");
                }
                write.writefln("%s", paramHelp(n));
            }
            if (cmd.textArgument) {
                write.writefln("    [text-agument]");
            }
            write.writefln("%s arguments.", cmd.param_types.length);
        }
    }

    void register(Command cmd) {
        mCommands ~= cmd;
    }

    public void registerCommand(Command cmd) {
        register(cmd);
    }

    public void registerCommand(string name, CommandHandler handler,
        string helpText, string[] args = null, CompletionHandler[] compl = null)
    {
        register(Command(name, handler, helpText, args, compl));
    }

    /// Merge the commands from sub with this
    void addSub(CommandBucket sub) {
        removeSub(sub); //just to be safe
        mSubs ~= sub;
    }

    void bind(CommandLine cmdline) {
        cmdline.commands.addSub(this);
    }

    void removeSub(CommandBucket sub) {
        arrayRemove(mSubs, sub, true);
    }

    Translator helpTranslator() {
        return mHelpTrans;
    }
    void helpTranslator(Translator tr) {
        mHelpTrans = tr;
    }

    //iterate over all added commands with foreach
    int opApply(scope int delegate(ref Entry e) dg) {
        foreach (cmd; mCommands) {
            auto e = Entry(cmd.name, cmd, mHelpTrans);
            if (auto i = dg(e))
                return i;
        }
        foreach (s; mSubs) {
            if (auto i = s.opApply(dg))
                return i;
        }
        if (onGetSubCommands) {
            CommandBucket sub = onGetSubCommands();
            if (sub) {
                if (auto i = sub.opApply(dg))
                    return i;
            }
        }
        return 0;
    }

    //for quickly converting old to new help format; prints to stdout
    //can also be used to change format of locale (in case "someone"
    //  doesn't like it)
    debug void convertHelpToLocales() {
        foreach (e; this) {
            Trace.formatln("%s = \"%s\"", e.cmd.name, e.helpText());
            for (int n = 0; n < e.cmd.param_types.length; n++) {
                Trace.formatln("%s_arg%s = \"%s\"", e.cmd.name, n,
                    e.paramHelp(n));
            }
        }
    }
}

///stateless part of the commandline, where commands are registered
public class CommandLine {
    private {
        CommandBucket mCommands;
        string mCommandPrefix;
        string mDefaultCommand;
        CommandLineInstance mDefInstance; //to support execute()
    }

    void delegate(CommandLine sender, string line) onFallbackExecute;

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

    public void registerCommand(string name, CommandHandler handler,
        string helpText, string[] args = null, CompletionHandler[] compl = null)
    {
        registerCommand(Command(name, handler, helpText, args, compl));
    }

    /// Set a prefix which is required before each command (disable with ""),
    /// and a default_command, which is invoked when the prefix isn't given.
    public void setPrefix(string prefix, string default_command) {
        mCommandPrefix = prefix;
        mDefaultCommand = default_command;
    }

    public bool execute(string cmdline, bool silentOnError = false) {
        return mDefInstance.execute(cmdline, false, silentOnError);
    }
}

///stateful part of the commandline (i.e. history)
class CommandLineInstance {
    private {
        CommandLine mCmdline;
        CommandBucket mCommands;
        Output mConsole;
        string[] mHistory;
        sizediff_t mCurrentHistoryEntry = 0;

        enum uint MAX_HISTORY_ENTRIES = 20;
        enum uint MAX_AUTO_COMPLETIONS = 10;

        alias CommandBucket.Entry CommandEntry;
    }

    private string[] complete_command_list() {
        string[] res;
        foreach (CommandEntry e; mCommands) {
            res ~= e.alias_name;
        }
        return res;
    }

    this(CommandLine cmdline, Output output) {
        mConsole = output;
        mCmdline = cmdline;
        mCommands = new CommandBucket;
        mCommands.helpTranslator = localeRoot.bindNamespace(
            "console_commands.generic");
        mCommands.addSub(mCmdline.mCommands);
        mCommands.registerCommand(Command("help", &cmdHelp, "", ["text?"],
            [&complete_command_list]));
        mCommands.registerCommand(Command("history", &cmdHistory, "", null));
    }

    private void cmdHelp(MyBox[] args, Output write) {
        string foo = args[0].unboxMaybe!(string)("");
        if (foo.length == 0) {
            mConsole.writefln("List of commands: ");
            uint count = 0;
            foreach (c; mCommands) {
                c.showShortHelp(mConsole);
                count++;
            }
            mConsole.writefln("%s commands.", count);
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
                exact.showHelp(mConsole);
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
        foreach (string hist; mHistory) {
            mConsole.writefln("   "~hist);
        }
    }

    /// Search through the history, dir is either -1 or +1
    /// Returns entry, the "cur" param is the current commandline
    /// Returned string must not be modified.
    /* Rules about history editing:
       - going to an entry, modifying it, and hitting enter just appends a
         new entry to the history
       - modifying an entry and, without hitting enter, going to another entry,
         changes the entry in the history and doesn't create a new entry
    */
    public string selectHistory(string cur, int dir) {
        setHistory(cur);

        if (dir == -1) {
            if (mCurrentHistoryEntry - 1 >= 0)
                mCurrentHistoryEntry -= 1;
        } else if (dir == +1) {
            if (mCurrentHistoryEntry + 1 < mHistory.length)
                mCurrentHistoryEntry += 1;
        }

        if (mCurrentHistoryEntry < mHistory.length) {
            return mHistory[mCurrentHistoryEntry];
        } else {
            return cur;
        }
    }

    private void setHistory(string line) {
        if (line.length == 0)
            return;
        line = line.idup;
        if (!mHistory.length || mCurrentHistoryEntry >= mHistory.length) {
            mHistory ~= line;
            mCurrentHistoryEntry = mHistory.length - 1;
        }
        //save back old entry (might be a nop in most cases)
        mHistory[mCurrentHistoryEntry] = line;
    }

    //get the command part of the command line
    //start-end: position of command literal, excluding whitespace or prefix
    //argstart: start-index of the arguments (line.length if none)
    private bool parseCommand(string line, out string command, out size_t start,
        out size_t end, out size_t argstart)
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
                argstart = end + 1;
            } else {
                command = line;
                end = start + line.length;
                argstart = len;
            }
        } else {
            command = mCmdline.mDefaultCommand;
            argstart = 0;
        }
        return command.length > 0;
    }

    /// Execute any command from outside.
    public bool execute(string cmdline, bool addHistory = true,
        bool silentOnError = false)
    {
        string cmd, args;
        size_t start, end, argstart;

        if (!parseCommand(cmdline, cmd, start, end, argstart)) {
            //nothing, but show some reaction...
            mConsole.writefln("-");
            //command failed to parse -> report as eaten,
            //will fail on other instances as well
            return true;
        } else {
            if (addHistory) {
                if (mCurrentHistoryEntry != mHistory.length - 1) {
                    //modified older entry, append to end
                    if (cmdline.length)
                        mHistory ~= cmdline;
                } else {
                    //as usual
                    setHistory(cmdline);
                }
                if (mHistory.length > MAX_HISTORY_ENTRIES) {
                    mHistory = mHistory[1..$];
                }
                mCurrentHistoryEntry = mHistory.length;
            }

            auto ccmd = findCommand(cmd);
            if (!ccmd.cmd) {
                if (mCmdline.onFallbackExecute) {
                    mCmdline.onFallbackExecute(mCmdline, cmdline);
                    return true;
                }
                if (!silentOnError)
                    mConsole.writefln("Unknown command: "~cmd);
                return false;
            } else {
                if (!ccmd.cmd.parseAndInvoke(cmdline[argstart..$], mConsole)) {
                    ccmd.showHelp(mConsole);
                }
                return true;
            }
        }
    }

    //find a command, even if cmd only partially matches (but is unique)
    CommandEntry findCommand(string cmd) {
        CommandEntry[] throwup;
        auto ccmd = find_command_completions(cmd, throwup);
        //accept unique partial matches
        if (!ccmd.cmd && throwup.length == 1) {
            ccmd = throwup[0];
        }
        return ccmd;
    }

    private static string common_prefix(string s1, string s2) {
        size_t slen = min(s1.length, s2.length);
        for (size_t n = 0; n < slen; n++) {
            if (s1[n] != s2[n]) {
                slen = n;
                break;
            }
        }
        assert(s1[0..slen] == s2[0..slen]);
        return s1[0..slen];
    }

    /// Replace the text between start and end by text
    /// operation: newline = line[0..start] ~ text ~ line[end..$];
    public alias void delegate(size_t start, size_t end, cstring text) EditDelegate;

    /// Do tab completion for the given line. The delegate by edit inserts
    /// completed text.
    /// at = cursor position; currently unused
    public void tabCompletion(string line, size_t at, scope EditDelegate edit) {
        void do_edit(size_t start, size_t end, string text) {
            line = line[0..start] ~ text ~ line[end..$];
            if (edit)
                edit(start, end, text);
        }

        string cmd;
        size_t start, end, argstart;
        if (!parseCommand(line, cmd, start, end, argstart))
            return;

        //find out, what or where to complete
        size_t arg_e; //position where to insert completion
        string argstr; //(uncompleted) thing which then user wants to complete
        string[] all_completions; //list of possible completions

        //NOTE: start==end => "default" command (no prefix)
        if (at <= end && start != end) {
            argstr = line[start .. end];
            arg_e = end;
            all_completions = complete_command_list();
        } else {
            //have to have a command
            Command ccmd = findCommand(cmd).cmd;
            if (!ccmd) {
                //no hit - is in arguments, but command isn't recognized
                return;
            }
            auto args = line[argstart..$];
            size_t arg;
            if (!ccmd.findArgAt(args, at - argstart, arg, argstr)) {
                //no hit - no idea what's going on
                return;
            }
            arg_e = at;
            CompletionHandler h = ccmd.completions[arg];
            if (!h) {
                //no completion provided
                return;
            }
            all_completions = h();
        }

        //filter completions (remove unuseful ones)
        string[] completions;
        foreach (c; all_completions) {
            if (c.length >= argstr.length && c[0..argstr.length] == argstr)
                completions ~= c;
        }

        if (completions.length == 0) {
            //no hit, too bad, maybe beep?
        } else {
            //get biggest common starting-string of all completions
            string common = completions[0];
            foreach (string item; completions[1..$]) {
                common = common_prefix(common, item);
            }
            //mConsole.writefln(" ..: '%s' '%s' %s", common, cmd, res);
            //mConsole.writefln("s=%s e=%s", start, end);

            if (common.length > argstr.length) {
                //if there's a common substring longer than the commandline,
                //  extend it
                size_t diff = common.length - argstr.length;

                do_edit(arg_e, arg_e, common[$-diff..$]);
                arg_e += diff;
            } else {
                if (completions.length > 1) {
                    //write them to the output screen
                    mConsole.writefln("Tab completions:");
                    bool toomuch = (completions.length == MAX_AUTO_COMPLETIONS);
                    if (toomuch) completions = completions[0..$-1];
                    foreach (string item; completions) {
                        //draw a "|" between the completed and the missing part
                        mConsole.writefln("  %s|%s", item[0..common.length],
                            item[common.length..$]);
                    }
                    if (toomuch)
                        mConsole.writefln("...");
                } else {
                    //was already complete... hm
                }
            }

            if (completions.length == 1) {
                //one hit = > it's complete now (or should be)
                //insert a space after the command, if there isn't yet
                if (!(arg_e > 0 && line[arg_e-1] == ' '))
                    edit(arg_e, arg_e, " ");
            }
        }
    }

    //if there's a perfect match (whole string equals), then it is returned,
    //  else return null (for the .cmd field)
    private CommandEntry find_command_completions(string cmd,
        ref CommandEntry[] res)
    {
        CommandEntry exact;

        res.length = 0;

        foreach (CommandEntry cur; mCommands) {
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
