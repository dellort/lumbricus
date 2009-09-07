module common.macroconfig;

import utils.configfile;
import utils.log;
import utils.misc;
import utils.array : Appender;

import mdc = minid.compiler;
import md = minid.api;

debug = DumpStuff;

debug(DumpStuff) {
    import common.config;
}

//why the fucking hell can't I add delegates to MiniD?
//if a D function called by MiniD wants additional context, I have to add it as
//  upval - but I can't add pointers, only D objects. so, I have to allocate a
//  D object, just to be able to add functions with context? and the function
//  can't even be a method of that object, I still have to do inconvenient
//  boiler plate code to access my context?
//seriously, what the flying fuck?
private Appender!(char) output;
private uint emit_text(md.MDThread* thread, uint idontknowwhatthisis) {
    char[] s = md.getString(thread, 1);
    //s is in MiniD heap, and can explode into your face - must make a copy
    output ~= s;
    //return what?
    return 0;
}

//process MiniD scripts embedded in ConfigNodes
//all nodes with the name "!inline:minid" are assumed to contain MiniD scripts
//  as string value. the MiniD environment used to execute those scripts makes
//  a emit_text(string) method available. the text passed ot that function is
//  concatenated, and at the end of the execution of the MiniD script, the text
//  is parsed as configfile, and the resulting nodes are inlined into the
//  ConfigNode that contained the "!inline:minid" script node. Then, the script
//  node is removed.
//NOTE: if no script nodes are found, MiniD isn't initialized (and you only pay
//  the cost for searching the ConfigNode for script nodes).
void process_macros(ConfigNode node) {
    md.MDVM md_vm;
    md.MDThread* md_thread;

    scope(exit) {
        if (md_thread)
            md.closeVM(&md_vm);
    }

    void init_md() {
        if (md_thread)
            return;
        md_thread = md.openVM(&md_vm);
        md.loadStdlibs(md_thread);
        //make emit_text available to script
        md.newFunction(md_thread, &emit_text, "emit_text");
        md.newGlobal(md_thread, "emit_text");
    }

    char[] execute_script(char[] script, char[] source) {
        init_md();
        auto slot = md.loadString(md_thread, script, false, source);
        md.pushNull(md_thread); //"this" parameter (according to docs)
        md.rawCall(md_thread, slot, 0);
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
            if (sub.name != "!inline:minid") {
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

    debug(DumpStuff)
        if (md_thread)
            saveConfig(node, "dump2.conf");
}
