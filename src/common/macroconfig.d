module common.macroconfig;

import utils.configfile;
import utils.log;
import utils.misc;
import utils.array : Appender;

import framework.lua;

debug = DumpStuff;

debug(DumpStuff) {
    import common.config;
}


//process Lua scripts embedded in ConfigNodes
//all nodes with the name "!inline:lua" are assumed to contain Lua scripts
//  as string value. the Lua environment used to execute those scripts makes
//  a emit_text(string) function available. the text passed ot that function is
//  concatenated, and at the end of the execution of the Lua script, the text
//  is parsed as configfile, and the resulting nodes are inlined into the
//  ConfigNode that contained the "!inline:lua" script node. Then, the script
//  node is removed.
//NOTE: if no script nodes are found, Lua isn't initialized (and you only pay
//  the cost for searching the ConfigNode for script nodes).
void process_macros(ConfigNode node) {
    LuaState lua;

    Appender!(char) output;

    void emit_text(char[] s) {
        Trace.formatln("emit '{}'", s);
        output ~= s;
    }

    scope(exit) {
        if (lua)
            lua.destroy();
    }

    void do_init() {
        if (lua)
            return;
        lua = new LuaState();
        lua.setGlobal("emit_text", &emit_text);
    }

    char[] execute_script(char[] script, char[] source) {
        do_init();
        lua.loadScript(source, script);
        char[] res = output.dup;
        output.length = 0;
        return res;
    }

    void do_node(ConfigNode cur) {
        void report(char[] err) {
            registerLog("something")("{}", err);
        }

        ConfigNode[] add, remove;
        foreach (ConfigNode sub; cur) {
            if (sub.name != "!inline:lua") {
                do_node(sub);
                continue;
            }
            remove ~= sub;
            char[] result = execute_script(sub.getCurValue!(char[])(),
                '[' ~ sub.filePosition.toString() ~ ']');
            ConfigNode r = ConfigFile.Parse(result, myformat("[script {}]",
                sub.filePosition), &report);
            add ~= r.subNodesToArray();
        }
        //can't add or remove nodes during iteration, I guess
        foreach (r; remove)
            cur.remove(r);
        foreach (r; add)
            cur.addNode(r);
    }

    do_node(node);

    debug(DumpStuff) {
        if (lua)
            saveConfig(node, "dump2.conf");
    }
}
