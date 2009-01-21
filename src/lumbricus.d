module lumbricus;
import framework.framework;

//also a factory-import
import framework.sdl.framework;
import framework.sdl.soundmixer;
import framework.openal;

import framework.filesystem : MountPath;
import common = common.common;
import toplevel = common.toplevel;

import utils.configfile;
import utils.log;
import utils.output;
import utils.random;
import utils.time;

import std.stdio;
import std.stream : File, FileMode;
import std.string;

//these imports register classes in a factory on module initialization
//so be carefull not to remove them accidentally

import gui.test; //GUI test code
import game.gametask; //the game itself
import game.serialize_register : initGameSerialization;
import game.gui.leveledit; //aw
import game.gui.welcome;
import game.gui.teamedit;
import game.gui.setup_local;
import game.gui.levelpaint;
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

//of course it would be nicer to automatically generate the following thing, but
//OTOH, it isn't really worth the fuzz
const cCommandLineHelp =
`Partial documentation of commandline switches:
    --help
        Output this and exit.
    --language_id=ID
        Set language ID (de, en)
    --driver.xxx=yyy
        Set property xxx of the fwconfig stuff passed to the Framework to yyy,
        e.g. to disable use of OpenGL:
        --driver.open_gl=false
    --exec.=xxx
        Execute "xxx" on the commandline, e.g. this starts task1 and task2:
        --exec.="spawn task1" --exec.="spawn task2"
        (the dot "." turns exec into a list, and a list is expected for exec)
        The "autoexec" list in anything.conf isn't executed if an --exec. is
        given on the commandline.
    --data=xxx
        Mount xxx as extra data directory (with highest priority, i.e. it
        overrides the standard paths).
    --logconsole
        Output all log output on stdio.`;
//Also see parseCmdLine() for how parsing works.

void main(char[][] args) {
    //xxx
    rand_seed(1);

    initGameSerialization();

    ConfigNode cmdargs = parseCmdLine(args[1..$]);
    //cmdargs.writeFile(StdioOutput.output);

    if (cmdargs.getBoolValue("help")) {
        writefln(cCommandLineHelp);
        return;
    }

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
}

//godawful primitive commandline parser
//it only accepts ["--<argname>", "<arg>"] pairs, and puts them into a config
//node... the argname is interpreted as path into the config node, so i.e. using
//"--bla.blo.blu 123" in the argname will create the subnode "bla" under the
//root, which in turn contains a subnode "blo" with the item "blu" which
//contains the value "123"
//also, if <argname> contains a "=", the following string will be interpreted as
//<arg>
//now args without values are also allowed; the value is set to "true" then
ConfigNode parseCmdLine(char[][] args) {
    bool startsArg(char[] s) {
        return s.length >= 3 && s[0..2] == "--";
    }

    ConfigNode res = new ConfigNode();
    while (args.length) {
        auto cur = args[0];
        args = args[1..$];
        if (!startsArg(cur)) {
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
            if (args.length && !startsArg(args[0])) {
                value = args[0];
                args = args[1..$];
            } else {
                //hurrr, assume it's a boolean switch => default to true
                value = "true";
            }
        }

        res.setStringValueByPath(name, value);
    }
    return res;
}
