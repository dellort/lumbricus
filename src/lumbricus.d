module lumbricus;
import framework.framework;

//also a factory-import
import framework.sdl.framework;

import framework.filesystem : MountPath;
import common = common.common;
import toplevel = common.toplevel;

import utils.configfile;
import utils.log;
import utils.output;
import utils.time;

import std.random : rand_seed;
import std.stdio;
import std.stream : File, FileMode;
import std.string;

//these imports register classes in a factory on module initialization
//so be carefull not to remove them accidentally

import gui.test; //GUI test code
import game.gametask; //the game itself
import game.gui.preview; //level preview window
import game.gui.leveledit; //aw
import game.wtris; //lol
import game.bomberworm; //?
import irc.ircclient; //roflmao
//net tests
import net.enet_test;
//import net.test;

const char[] APP_ID = "lumbricus";

int main(char[][] args)
{
    //xxx
    rand_seed(1, 1);

    ConfigNode cmdargs = parseCmdLine(args[1..$]);
    //cmdargs.writeFile(StdioOutput.output);

    auto fw = new Framework(args[0], APP_ID, cmdargs);
    fw.setCaption("Lumbricus");

    //init filesystem
    fw.fs.mount(MountPath.data, "locale/", "/locale/", false, 2);
    fw.fs.tryMount(MountPath.data, "data2/", "/", false, 2);
    fw.fs.mount(MountPath.data, "data/", "/", false, 3);
    fw.fs.mount(MountPath.user, "/", "/", true, 0);

    gLogEverything.destination = new StreamOutput(new File("logall.txt",
        FileMode.OutNew));

    new common.Common(fw, cmdargs);
    //installs callbacks to framework, which get called in the mainloop
    new toplevel.TopLevel();

    fw.run();

    fw.deinitialize();

    writefln("Bye!");

    return 0;
}

//godawful primitive commandline parser
//it only accepts ["--<argname>", "<arg>"] pairs, and puts them into a config
//node... the argname is interpreted as path into the config node, so i.e. using
//"--bla.blo.blu 123" in the argname will create the subnode "bla" under the
//root, which in turn contains a subnode "blo" with the item "blu" which
//contains the value "123"
//also, if <argname> contains a "=", the following string will be interpreted as
//<arg>
ConfigNode parseCmdLine(char[][] args) {
    ConfigNode res = new ConfigNode();
    while (args.length) {
        auto cur = args[0];
        args = args[1..$];
        if (cur.length < 3 || cur[0..2] != "--") {
            writefln("command line argument: --argname expected");
            break;
        }
        cur = cur[2..$];

        auto has_arg = find(cur, '=');
        auto name = has_arg >= 0 ? cur[0..has_arg] : cur;
        auto val_start = rfind(name, '.');
        auto valname = name[val_start+1..$];
        auto pathname = name[0..(val_start >= 0 ? val_start : 0)];
        //get value
        char[] value;
        if (has_arg >= 0) {
            value = cur[has_arg+1..$];
        } else {
            if (!args.length) {
                writefln("command line argument: value expected");
                break;
            }
            value = args[0];
            args = args[1..$];
        }

        ConfigNode node = res.getPath(pathname, true);
        node.setStringValue(valname, value);
    }
    return res;
}
