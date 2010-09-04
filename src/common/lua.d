module common.lua;

import framework.filesystem;
import framework.lua;
import utils.misc;

//didn't want to put this in framework.lua (too many weird dependencies)
void loadScript(LuaState state, char[] filename, char[] environment = null) {
    auto st = gFS.open(filename);
    scope(exit) st.close();
    //xxx: IOExceptions and all that?
    auto data = st.readAll();
    scope(exit) delete data;
    state.loadScript(filename, cast(char[])data, environment);
}

alias LuaInterpreter ScriptInterpreter;

//lua commandline interpreter wrapper, independent from GUI
class LuaInterpreter {
    private {
        LuaState mLua;
        void delegate(char[]) mSink;
    }

    //a_sink = output of Lua and the wrapper, will include '\n's
    this(void delegate(char[]) a_sink, LuaState a_state = null,
        bool suppressVersionMessage = false)
    {
        mSink = a_sink;
        mLua = a_state;

        if (!mLua) {
            mLua = new LuaState();
            loadScript(mLua, "lua/utils.lua");
        }

        //this might be a bit dangerous/unwanted
        //problem: if the console goes away (e.g. closed), the output will go
        //  to nowhere
        //but we need it for this console
        //alternatively, maybe one could create a sub-environment or whatever,
        //  that just shadows the default output function, or so
        //idea: temporarily set an output handler while a command is executed
        //  (asynchronous output from timers and event handlers would go into
        //  a global default handler)
        //xxx disabled for now (changed ConsoleUtils.exec to use log functions)
        //mLua.setPrintOutput(mSink);

        if (!suppressVersionMessage) {
            myformat_cb(mSink, "Scripting console using: {}\n",
                mLua.cLanguageAndVersion);
        }
    }

    final void exec(char[] code) {
        //print literal command to console
        myformat_cb(mSink, "> {}\n", code);
        runLuaCode(code);
    }

    protected void runLuaCode(char[] code) {
        mLua.scriptExec("ConsoleUtils.exec(...)", code, mSink);
    }

    struct CompletionResult {
        int match_start, match_end;
        char[][] matches;
        bool more;
    }

    //cursor1..cursor2: indices into line for cursor position + selection
    //parameters are similar to TabCompletionDelegate in GuiConsole
    CompletionResult autocomplete(char[] line, int cursor1, int cursor2) {
        try {
            return mLua.scriptExecR!(CompletionResult)
                ("return ConsoleUtils.autocomplete(...)", line, cursor1, cursor2);
        } catch (LuaException e) {
            myformat_cb(mSink, "error in autocompletion code: {}\n", e);
            return CompletionResult.init;
        }
    }

    private static char[] common_prefix(char[] s1, char[] s2) {
        uint slen = min(s1.length, s2.length);
        for (int n = 0; n < slen; n++) {
            if (s1[n] != s2[n]) {
                slen = n;
                break;
            }
        }
        assert(s1[0..slen] == s2[0..slen]);
        return s1[0..slen];
    }

    //what this function does and its parameters see GuiConsole.setTabCompletion
    void tabcomplete(char[] line, int cursor1, int cursor2,
        void delegate(int, int, char[]) edit)
    {
        auto res = autocomplete(line, cursor1 + 1, cursor2 + 1);
        if (res.matches.length == 0)
            return;
        res.match_start -= 1;
        res.match_end -= 1;
        if (!(sliceValid(line, res.match_start, res.match_end)
            && str.isValid(line[0..res.match_start])
            && str.isValid(line[0..res.match_end])))
        {
            //Lua script returned something stupid
            //no need to crash hard
            myformat_cb(mSink, "bogus completion: {} {}\n", res.match_start,
                res.match_end);
            return;
        }
        uint len = res.match_end - res.match_start;
        if (res.matches.length == 1) {
            //insert the completion and be done with it
            auto c = res.matches[0];
            auto slen = min(len, c.length);
            edit(res.match_end, res.match_end, c[slen..$]);
            return;
        }
        //find prefix and complete up to it
        auto prefix = res.matches[0];
        foreach (c; res.matches) {
            prefix = common_prefix(prefix, c);
        }
        if (prefix.length > len) {
            edit(res.match_end, res.match_end, prefix[len..$]);
        }
        //
        mSink("Completions:\n");
        res.matches.sort;
        foreach (c; res.matches) {
            auto xlen = prefix.length;
            myformat_cb(mSink, "    {}|{}\n", c[0..xlen], c[xlen..$]);
        }
        if (res.more) {
            mSink("    ...\n");
        }
    }
}
