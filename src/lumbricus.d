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
//broken import game.gui.leveledit; //aw
import game.wtris; //lol
import game.bomberworm; //?
import irc.ircclient; //roflmao
//debugging
import common.resview;
//net tests
import net.enet_test;
//import net.test;

//import test;

const char[] APP_ID = "lumbricus";

/++
Documentation of commandline switches:
    --driver.xxx=yyy
        Set property xxx of the fwconfig stuff passed to the Framework to yyy,
        i.e. to disable use of OpenGL:
        --driver.open_gl=false
    --exec.=xxx
        Execute "xxx" on the commandline, i.e. this starts task1 and task2:
        --exec.="spawn task1" --exec.="spawn task2"
        (the dot "." turns exec into a list, and a list is expected for exec)
        The "autoexec" list in anything.conf isn't executed if an --exec. is
        given on the commandline.
    --data=xxx
        Mount xxx as extra data directory (with highest priority, i.e. it
        overrides the standard paths).
Also see parseCmdLine() for how parsing works.
++/
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

    //commandline switch: --data=some/dir/to/data
    char[] extradata = cmdargs["data"];
    if (extradata.length) {
        fw.fs.mount(MountPath.absolute, extradata, "/", false, -1);
    }

    gLogEverything.destination = new StreamOutput(new File("logall.txt",
        FileMode.OutNew));

    new common.Common(cmdargs);
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

        res.setStringValueByPath(name, value);
    }
    return res;
}
