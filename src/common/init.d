module common.init;

import framework.config;
import framework.filesystem;
import common = common.common;
import settings = common.settings;

import utils.configfile;
import utils.log;
import utils.output;
import utils.random;
import utils.time;

import utils.stream : File, ThreadedWriter; //???

import tango.io.Stdout;

//Currently, this is just used in FileSystem to determine data/user paths
const char[] APP_ID = "lumbricus";

///args = arguments to main()
///help = output for help command
///returns = parsed command line arguments (parseCmdLine())
void init(char[][] args) {
    //buffer log, until FileSystem is initialized
    auto logtmp = new StringOutput();
    gLogEverything.destination = logtmp;

    //init filesystem
    auto fs = new FileSystem(args[0], APP_ID);
    initFSMounts();

    //open logfile in user dir
    const File.Style WriteCreateShared =
        {File.Access.Write, File.Open.Create, File.Share.Read};
    auto logf = gFS.open("/logall.txt", WriteCreateShared);
    auto logstr = new PipeOutput((new ThreadedWriter(logf)).pipeOut());
    //write buffered log
    logstr.writeString(logtmp.text);
    gLogEverything.destination = logstr;

    //yyy
    //commandline switch: --data=some/dir/to/data
    //char[] extradata = cmdargs["data"];
    //if (extradata.length) {
    //    fs.mount(MountPath.absolute, extradata, "/", false, -1);
    //}

    settings.prepareSettings();

    settings.loadSettings();

    //xxx load settings from command line

    common.globals.do_init();
}


//temp-mount user and data dir, read mount.conf and setup mounts from there
//xxx probably move somewhere else (needs common/config.d, so no filesystem.d ?)
void initFSMounts() {
    //temporary mounts to read mount.conf
    gFS.reset();
    gFS.mount(MountPath.data, "/", "/", false, 0);
    auto mountConf = loadConfig("mount");

    gFS.reset();
    //user's mount.conf will not override, but add to internal paths
    gFS.mount(MountPath.user, "/", "/", false, 0);
    ConfigNode mountConfUser;
    if (gFS.exists("mount.conf"))
        mountConfUser = loadConfig("mount");
    //clear temp mounts
    gFS.reset();

    void readMountConf(ConfigNode mconfig) {
        foreach (ConfigNode node; mountConf) {
            char[] physPath = node["path"];
            char[] mp = node["mountpoint"];
            MountPath type;
            switch (node["type"]) {
                case "data": type = MountPath.data; break;
                case "user": type = MountPath.user; break;
                case "absolute":
                default:
                    type = MountPath.absolute;
            }
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
