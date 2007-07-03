module framework.commandline;

import framework.console;
import framework.framework;
import framework.keysyms;

import str = std.string;
import utf = std.utf;

import utils.mylist;
import utils.mybox;
import utils.misc;
import utils.output;

alias MyBox function(char[][] args, inout int argIdx) TypeHandler;
alias void delegate(CommandLine) CommandHandler;
alias void delegate(MyBox[] args, Output write) NewCommandHandler;

TypeHandler[char[]] gCommandLineParsers;

//store stuff about a command
public class Command {
    //use opCall()
    private this() {
    }

    static Command opCall(char[] name, CommandHandler handler, char[] helpText)
    {
        Command cmd = new Command();
        cmd.name = name;
        cmd.cmdProc = handler;
        cmd.helpText = helpText;
        //cmd.param_types = [gCommandLineParsers["text"]];
        //combination of both => no arguments yield an empty string
        cmd.minArgCount = 1;
        cmd.textArgument = 0;
        return cmd;
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
    static Command opCall(char[] name, NewCommandHandler handler,
        char[] helpText, char[][] args)
    {
        assert(false, "implement me");
        return null;
    }
private:
    char[] name;
    CommandHandler cmdProc;
    NewCommandHandler cmdProc2;
    char[] helpText;

    TypeHandler[] param_types;
    MyBox[] param_defaults;
    char[][] param_help;
    int minArgCount;
    //-1 or param nr. since when all all the rest of the text should be passed
    //to the argument parser (before that, separate by whitespace)
    int textArgument = -1;

    //whatever...
    void parseAndInvoke(char[] cmdline, Output write) {
    }
}

//idea:
//bind a bunch of commands to... something
class CommandBucket {
    void registerCommand(Command);

    //remove all commands from CommandLine instance again
    abstract public void kill();
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
    //used for parseCommand()
    private uint mCommandStart, mCommandEnd;

    private const uint MAX_HISTORY_ENTRIES = 20;
    private const uint MAX_AUTO_COMPLETIONS = 10;

    this(Console cons) {
        mConsole = cons;
        HistoryNode n;
        mHistory = new HistoryList(n.listnode.getListNodeOffset());
        registerCommand("help", &cmdHelp, "Show all commands.");
        registerCommand("history", &cmdHistory, "Show the history.");
    }

    public Console console() {
        return mConsole;
    }

    private void cmdHelp(CommandLine cmd) {
        mConsole.print("List of commands: ");
        uint count = 0;
        foreach (Command c; mCommands) {
            mConsole.writefln("   %s: %s", c.name, c.helpText);
            count++;
        }
        mConsole.print(str.format("%d commands.", count));
    }

    private void cmdHistory(CommandLine cmd) {
        mConsole.print("History:");
        foreach (HistoryNode hist; mHistory) {
            mConsole.print("   "~hist.stuff);
        }
    }

    public int registerCommand(char[] name,
        void delegate(CommandLine cmdLine) cmdProc, char[] helpText)
    {
        mCommands ~= Command(name, cmdProc, helpText);

        return 0; //xxx what was the id for?
    }

    public bool keyDown(KeyInfo infos) {
        return false;
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
    private char[] parseCommand() {
        //currently just find the first space...
        mCommandStart = 0;
        mCommandEnd = mCurline.length;
        foreach (uint index, char c; mCurline) {
            if (c == ' ') {
                mCommandEnd = index;
                break;
            }
        }
        return mCurline[mCommandStart..mCommandEnd];
    }

    //to be called from command implementations...
    public char[][] parseArgs() {
        return str.split(mCurline[mCommandEnd .. $]);
    }

    public char[] getArgString() {
        return str.strip(mCurline[mCommandEnd .. $]);
    }

    private void do_execute(bool addHistory = true) {
        auto cmd = parseCommand();

        if (cmd.length == 0) {
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
                ccmd.cmdProc(this);
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
        char[] cmd = parseCommand();
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

                mCurline = mCurline[0..mCommandStart] ~ common
                    ~ mCurline[mCommandEnd..$];
                mCursor = mCommandStart + common.length; //end of the command
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
