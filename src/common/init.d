module common.init;

import framework.config;
import framework.filesystem;
import framework.globalsettings;
import common = common.common;

import utils.configfile;
import utils.log;
import utils.output;
import utils.random;
import utils.time;

import utils.stream : File, ThreadedWriter; //???
import marray = utils.array;
import path = utils.path;
import stream = utils.stream;
import str = utils.string;
import strparser = utils.strparser;

import tango.io.Stdout;

//Currently, this is just used in FileSystem to determine data/user paths
const char[] APP_ID = "lumbricus";

//catched in main function
class ExitApp : Exception {
    this() { super(""); }
}

//why not use the C function? probably Tango misbehaves then
//works like exit(0), but lets D module dtors etc. run
void exit() {
    throw new ExitApp();
}

void print_help() {
    char[][] lines;
    lines ~= "Commandline options:";
    lines ~= "  -help";
    foreach (s; gSettings) {
        lines ~= "  -" ~ s.name~ " VALUE";
    }
    lines ~= "Some options can list possible choices by passing help as value.";
    lines ~= "Most settings passed to the command line will be saved "
        "permanently in the";
    lines ~= "settings file.";
    foreach (l; lines) Stdout(l).newline;
}

///args = arguments to main()
void init(char[][] args) {
    args = args[1..$];

    //command line help, xD.
    if (getarg(args, "help")) {
        print_help();
        exit();
    }

    //buffer log, until FileSystem is initialized
    auto logtmp = new StringOutput();
    gLogEverything.destination = logtmp;

    //init filesystem
    auto fs = new FileSystem(APP_ID);
    initFSMounts();

    //open logfile in user dir
    const File.Style WriteCreateShared =
        {File.Access.Write, File.Open.Create, File.Share.Read};
    auto logf = gFS.open("/logall.txt", WriteCreateShared);
    auto logstr = new PipeOutput((new ThreadedWriter(logf)).pipeOut());
    //write buffered log
    logstr.writeString(logtmp.text);
    gLogEverything.destination = logstr;

    relistAllSettings();
    loadSettings();

    //settings from cmd line
    foreach (s; gSettings) {
        char[] value;
        if (getarg(args, s.name, value)) {
            if (value == "help") {
                Stdout.formatln("possible values for setting '{}':", s.name);
                if (s.type == SettingType.Choice) {
                    foreach (c; s.choices) {
                        Stdout.formatln("   {}", c);
                    }
                } else if (s.type == SettingType.String) {
                    Stdout.formatln("   <any string>");
                } else if (s.type == SettingType.Percent) {
                    Stdout.formatln("   <number between 0 and 100>");
                } else {
                    Stdout.formatln("   <unknown>");
                }
                exit();
            }
            s.set!(char[])(value);
        }
    }

    if (args.length) {
        Stdout.formatln("Unknown command line arguments: {}", args);
        Stdout.formatln("Try -help instead.");
        exit();
    }

    common.globals.do_init();
}

struct ExeAttachment {
    char[] fmt;
    stream.Stream data;
}

//return 0 or 1 attachments
//0 signals failure, while 1 is for the attachment appended by create-fat-exe.sh
private ExeAttachment* readFatExe() {
    stream.Stream exe = stream.Stream.OpenFile(path.getExePath());
    struct Header {
        uint size;
        char[4] magic;
    }
    ulong s = exe.size;
    if (s < Header.sizeof)
        return null;
    exe.position = s - Header.sizeof;
    Header header;
    exe.readExact(cast(ubyte[])((&header)[0..1]));
    if (header.magic != "LUMB")
        return null;
    //point to the byte after the last attachment byte (which is '>')
    ulong end_offset = s - Header.sizeof;
    ulong sz = header.size;
    //sanity check: attachment can't be bigger than the whole file, minus header
    if (sz > end_offset)
        return null;
    auto att = new ExeAttachment;
    att.fmt = "tar";
    att.data = new stream.SliceStream(exe, end_offset - sz, end_offset);
    //Trace.formatln("attachment: {}-{} = {}/{}", end_offset - sz, end_offset, sz,
      //  att.data.size);
    return att;
}

private void readMountConf(ConfigNode mconfig) {
    foreach (ConfigNode node; mconfig) {
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

//temp-mount user and data dir, read mount.conf and setup mounts from there
//xxx probably move somewhere else (needs common/config.d, so no filesystem.d ?)
void initFSMounts() {
    //user's mount.conf will not override, but add to internal paths
    gFS.mount(MountPath.user, "/", "/", false, 0);
    ConfigNode mountConfUser;
    if (gFS.exists("mount.conf"))
        mountConfUser = loadConfig("mount");
    //clear temp mounts
    gFS.reset();

    ExeAttachment* stuff = readFatExe();
    if (stuff) {
        //using a standalone fs to avoid infinite recursion problem when using
        //  two links (replace linkExternal() by link() below)
        auto fs = new FileSystem();
        fs.mountArchive(MountPath.data, stuff.data, stuff.fmt, "/", 0);
        //create the mounts manually
        //the normal mount.conf would cause it to mount system paths, which we
        //  don't want; we just want to mount paths within the .zip
        gFS.linkExternal(fs, "/data", "/", false);
        gFS.linkExternal(fs, "/data2", "/", false);
        gFS.mount(MountPath.user, "/", "/", true, 0);
        //NOTE: still read the user's mount conf (not sure about this)
    } else {
        //normal code path

        //temporary mounts to read mount.conf
        gFS.mount(MountPath.data, "/", "/", false, 0);
        auto mountConf = loadConfig("mount");
        gFS.reset();

        readMountConf(mountConf);
    }

    if (mountConfUser)
        readMountConf(mountConfUser);
}

//helpers for commandline parsing
//they use exit() in case of parse errors

//find switch "name" and remove it from args (or return false if not found)
bool getarg(ref char[][] args, char[] name) {
    return findarg(args, name, null);
}

//like getarg(), but with a single parameter
bool getarg(ref char[][] args, char[] name, out char[] p) {
    return findarg(args, name, (&p)[0..1]);
}

bool findarg(ref char[][] args, char[] name, char[][] getargs) {
    auto nargs = getargs.length;
    foreach (int i, a; args) {
        if (a.length > 0 && a[0] == '-' && a[1..$] == name) {
            if (i + nargs >= args.length) {
                Stdout.formatln("argument expected for option {}", a);
                exit();
            }
            getargs[] = args[i + 1 .. i + 1 + nargs];
            marray.arrayRemoveN(args, i, 1 + nargs);
            return true;
        }
    }
    return false;
}
