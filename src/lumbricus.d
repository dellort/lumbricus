module lumbricus;
import framework.framework;

//also a factory-import
import framework.sdl.framework;
import framework.sdl.soundmixer;
import framework.openal;
import framework.sdl.fontft;

//--> FMOD is not perfectly GPL compatible, so you may need to comment
//    this line in some scenarios (this is all it needs to disable FMOD)
import framework.fmod;
//<--

import framework.imgwrite;

import framework.filesystem;
import common = common.common;
import common.config;
import toplevel = common.toplevel;

import utils.configfile;
import utils.log;
import utils.output;
import utils.random;
import utils.time;

//hacky hack
import tracer = utils.mytrace;

import tango.io.Stdout;
import stdx.stream : File, FileMode;
import str = stdx.string;

//these imports register classes in a factory on module initialization
//so be carefull not to remove them accidentally

import gui.test; //GUI test code
import game.gametask; //the game itself
import game.serialize_register : initGameSerialization;
version(DigitalMars) {
    //I can only assume that this caused problems with ldc
    import game.gui.leveledit; //aw
}
import game.gui.welcome;
import game.gui.teamedit;
import game.gui.setup_local;
import game.gui.levelpaint;
import game.wtris; //lol
import game.bomberworm; //?
//debugging
import common.resview;
//net tests
//--compiling this module with LDC results in a segfault
version(DigitalMars) {
    import net.enet_test;
}
//import net.test;
import net.testgame;
import net.cmdserver;
import net.cmdclient;

//import test;

//Currently, this is just used in FileSystem to determine data/user paths
const char[] APP_ID = "lumbricus";

//of course it would be nicer to automatically generate the following thing, but
//OTOH, it isn't really worth the fuzz
const cCommandLineHelp =
`Partial documentation of commandline switches:
    --help
        Output this and exit.
    --language_id=ID
        Set language ID (de, en)
    --fw.xxx=yyy
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
    //buffer log, until FileSystem is initialized
    auto logtmp = new StringOutput();
    gLogEverything.destination = logtmp;

    //xxx
    //rand_seed(1);

    initGameSerialization();

    ConfigNode cmdargs = parseCmdLine(args[1..$]);
    //cmdargs.writeFile(StdioOutput.output);

    if (cmdargs.getBoolValue("help")) {
        Stdout.formatln(cCommandLineHelp);
        return;
    }

    //init filesystem
    auto fs = new FileSystem(args[0], APP_ID);
    initFSMounts();

    //open logfile in user dir
    auto logf = gFS.open("/logall.txt", FileMode.In | FileMode.OutNew);
    auto logstr = new StreamOutput(logf);
    //write buffered log
    logstr.writeString(logtmp.text);
    gLogEverything.destination = logstr;

    //commandline switch: --data=some/dir/to/data
    char[] extradata = cmdargs["data"];
    if (extradata.length) {
        fs.mount(MountPath.absolute, extradata, "/", false, -1);
    }

    auto fwconf = gConf.loadConfig("framework");
    fwconf.mixinNode(cmdargs.getSubNode("fw"), true);
    auto fw = new Framework(fwconf);
    fw.setCaption("Lumbricus");

    new common.Common(cmdargs);
    //installs callbacks to framework, which get called in the mainloop
    new toplevel.TopLevel();

    fw.run();

    toplevel.gTopLevel.deinitialize();
    fw.deinitialize();

    Stdout.formatln("Bye!");
}

//temp-mount user and data dir, read mount.conf and setup mounts from there
//xxx probably move somewhere else (needs common/config.d, so no filesystem.d ?)
void initFSMounts() {
    //temporary mounts to read mount.conf
    gFS.reset();
    gFS.mount(MountPath.data, "/", "/", false, 0);
    auto mountConf = gConf.loadConfig("mount");

    gFS.reset();
    //user's mount.conf will not override, but add to internal paths
    gFS.mount(MountPath.user, "/", "/", false, 0);
    ConfigNode mountConfUser;
    if (gFS.exists("mount.conf"))
        mountConfUser = gConf.loadConfig("mount");
    //clear temp mounts
    gFS.reset();

    void readMountConf(ConfigNode mconfig) {
        foreach (ConfigNode node; mountConf) {
            char[] physPath = node["path"];
            char[] mp = node["mountpoint"];
            MountPath type = cast(MountPath)node.selectValueFrom("type",
                ["data", "user", "absolute"], 2);
            int prio = node.getValue!(int)("priority", 0);
            bool writable = node.getValue!(bool)("writable", false);
            bool optional = node.getValue!(bool)("optional", false);
            if (optional) {
                gFS.tryMount(type, physPath, mp, writable, prio);
            } else {
                gFS.mount(type, physPath, mp, writable, prio);
            }
        }
    }
    readMountConf(mountConf);
    if (mountConfUser)
        readMountConf(mountConfUser);
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
            Stdout.formatln("command line argument: --argname expected");
            break;
        }
        cur = cur[2..$];

        auto has_arg = str.find(cur, '=');
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
