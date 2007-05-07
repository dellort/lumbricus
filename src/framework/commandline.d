module framework.commandline;

import framework.console;
import framework.framework;
import framework.keysyms;

import str = std.string;

import utils.mylist;

//store stuff about a command
private class Command {
    dchar[] name;
    void delegate(CommandLine, uint) cmdProc;
    dchar[] helpText;
    uint id;
}

//this was the only list class available :-)
private alias List!(HistoryNode) HistoryList;

private class HistoryNode {
    dchar[] stuff;
    mixin ListNodeMixin listnode;
}

public class CommandLine {
    private uint mUniqueID; //counter for registerCommand IDs
    private Console mConsole;
    private dchar[] mCurline;
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
        registerCommand("help"d, &cmdHelp, "Show all commands."d);
        registerCommand("history"d, &cmdHistory, "Show the history."d);
    }

    private void cmdHelp(CommandLine cmd, uint id) {
        mConsole.print("List of commands: "c);
        uint count = 0;
        foreach (Command c; mCommands) {
            mConsole.print(c.name ~ ": " ~ c.helpText);
            count++;
        }
        mConsole.print(str.format("%d commands.", count));
    }

    private void cmdHistory(CommandLine cmd, uint id) {
        mConsole.print("History:"d);
        foreach (HistoryNode hist; mHistory) {
            mConsole.print("   "~hist.stuff);
        }
    }

    public int registerCommand(dchar[] name,
        void delegate(CommandLine cmdLine, uint cmdId) cmdProc,
        dchar[] helpText)
    {
        auto cmd = new Command();
        cmd.name = name;
        cmd.cmdProc = cmdProc;
        cmd.helpText = helpText;
        cmd.id = ++mUniqueID;

        mCommands ~= cmd;

        return cmd.id;
    }

    public int registerCommand(char[] name,
        void delegate(CommandLine cmdLine, uint cmdId) cmdProc,
        char[] helpText)
    {
        return registerCommand(str.toUTF32(name), cmdProc,
            str.toUTF32(helpText));
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
                mCursor++;
            updateCursor();
            return true;
        } else if (infos.code == Keycode.LEFT) {
            if (mCursor > 0)
                mCursor--;
            updateCursor();
            return true;
        } else if (infos.code == Keycode.BACKSPACE) {
            if (mCursor > 0) {
                mCurline = mCurline[0 .. mCursor-1] ~ mCurline[mCursor .. $];
                mCursor--;
                updateCmdline();
            }
            return true;
        } else if (infos.code == Keycode.DELETE) {
            if (mCursor < mCurline.length) {
                mCurline = mCurline[0 .. mCursor] ~ mCurline[mCursor+1 .. $];
                updateCmdline();
            }
            return true;
        } else if (infos.code == Keycode.HOME) {
            mCursor = 0;
            updateCursor();
        } else if (infos.code == Keycode.END) {
            mCursor = mCurline.length;
            updateCursor();
        } else if (infos.code == Keycode.TAB) {
            do_tab_completion();
        } else if (infos.code == Keycode.RETURN) {
            do_execute();
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
        } else if (infos.code == Keycode.DOWN) {
            if (mCurrentHistoryEntry) {
                HistoryNode next_hist = mHistory.next(mCurrentHistoryEntry);
                select_history_entry(next_hist);
            }
        } else if (infos.code == Keycode.PAGEUP) {
            mConsole.scrollBack(1);
            return true;
        } else if (infos.code == Keycode.PAGEDOWN) {
            mConsole.scrollBack(-1);
            return true;
        } else if (infos.isPrintable()) {
            //printable char
            mCurline = mCurline[0 .. mCursor] ~ infos.unicode
                ~ mCurline[mCursor .. $];
            mCursor++;
            updateCmdline();
            return true;
        }
        return false;
    }

    private void select_history_entry(HistoryNode newentry) {
        dchar[] newline;

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
    private dchar[] parseCommand() {
        //currently just find the first space...
        mCommandStart = 0;
        mCommandEnd = mCurline.length;
        foreach (uint index, dchar c; mCurline) {
            if (c == ' ') {
                mCommandEnd = index;
                break;
            }
        }
        return mCurline[mCommandStart..mCommandEnd];
    }

    private void do_execute() {
        auto cmd = parseCommand();

        if (cmd.length == 0) {
            //nothing, but show some reaction...
            mConsole.print("-"c);
        } else {
            //into the history
            HistoryNode histent = new HistoryNode();
            histent.stuff = mCurline.dup;
            mHistory.insert_tail(histent);
            mHistoryCount++;

            if (mHistoryCount > MAX_HISTORY_ENTRIES) {
                mHistory.remove(mHistory.head);
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
                ccmd.cmdProc(this, ccmd.id);
            }
        }

        mCurline = null;
        mCursor = 0;
        updateCmdline();
    }

    private void do_tab_completion() {
        dchar[] cmd = parseCommand();
        Command[] res;
        Command exact = find_command_completions(cmd, res);

        if (res.length == 0) {
            //no hit, too bad, maybe beep?
        } else {
            //get biggest common starting-string of all completions
            dchar[] common = res[0].name;
            foreach (Command ccmd; res[1..$]) {
                if (ccmd.name.length < common.length)
                    common = ccmd.name.dup; //dup: because we set length below
                foreach (uint index, dchar c; common) {
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
                    mConsole.print("Tab completions:"d);
                    bool toomuch = (res.length == MAX_AUTO_COMPLETIONS);
                    if (toomuch) res = res[0..$-1];
                    foreach (Command ccmd; res) {
                        mConsole.print(ccmd.name);
                    }
                    if (toomuch)
                        mConsole.print("..."c);
                } else {
                    //one hit, since the case wasn't catched above, this means
                    //it's already complete?
                    mConsole.print("?"c);
                }
            }
        }

    }

    //if there's a perfect match (whole string equals), then it is returned,
    //  else return null
    private Command find_command_completions(dchar[] cmd, inout Command[] res) {
        Command exact;

        res.length = 0;

        foreach (Command cur; mCommands) {
            //xxx: make string comparisions case insensitive
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
