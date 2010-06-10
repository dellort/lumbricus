module common.init;

version = LogExceptions;  //set to write exceptions into logfile, too

import framework.config;
import framework.filesystem;
import framework.globalsettings;
import framework.i18n;

import utils.color;
import utils.configfile;
import utils.log;
import utils.misc;
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

private LogStruct!("init") gLogInit;

//catched in main function
private class ExitApp : Exception {
    this() { super(""); }
}

//why not use the C function? probably Tango misbehaves then
//works like exit(0), but lets D module dtors etc. run
//think about nasty stuff like flushing files
void exit() {
    throw new ExitApp();
}

//handle exception logging (windows users haet stdout/stderr) and ExitApp
//use it like:  int main(char[][] args) { return wrapMain(args, &realmain); }
int wrapMain(char[][] args, void function(char[][]) realmain) {
    try {
        realmain(args);
    } catch (ExitApp e) {
    } catch (Exception e) {
        version(LogExceptions) {
            //catch all exceptions, write them to logfile/console and exit
            if (gLogFileSink) {
                //logfile output
                e.writeOut((char[] s) {
                    gLogFileSink(s);
                });
            }
            //console output
            e.writeOut((char[] s) {
                Trace.format("{}", s);
            });
            return 1;
        } else {
            //leave it to the D runtime
            throw e;
        }
    }
    //"proof" that application exited gracefully
    debug Stdout.formatln("Bye!");
    return 0;
}

private void readLogConf() {
    ConfigNode conf = loadConfig("logconfig.conf", true, true);
    if (!conf)
        return;
    foreach (ConfigNode sub; conf.getSubNode("logs")) {
        Log log = registerLog(sub.name);
        if (sub.getCurValue!(bool)())
            log.minPriority = LogPriority.Trace;
    }
}

//xxx some minor complication because I wanted to force file- and
//  console-logging to use the same loglevel... change it if you find it stupid

private {
    SettingVar!(bool) gLogToFile;
    SettingVar!(bool) gLogToConsole;

    LogBackend gLogBackendFile;
    char[] gLogFileTmp;
}

//write bytes into the logfile (null if no logfile open)
//at initialization time, may be temporarily set to logToFileTmp
//if logfile writing is disabled, this is null
void delegate(char[]) gLogFileSink;

static this() {
    gLogBackendFile = new LogBackend("logfile/console", LogPriority.Trace,
        null);

    gLogToFile = typeof(gLogToFile).Add("log.to_file", false);
    gLogToConsole = typeof(gLogToConsole).Add("log.to_console", true);
    gLogToFile.setting.onChange ~= toDelegate(&changeLogOpt);
    gLogToConsole.setting.onChange ~= toDelegate(&changeLogOpt);
    changeLogOpt(null);
}

private void changeLogOpt(Setting s) {
    //shut up logging if logToConsoleAndFile() wouldn't want it
    //this is to reduce overhead (but probably isn't worth it)
    gLogBackendFile.enabled = gLogToFile.get() || gLogToConsole.get();
}

private void logToFileTmp(char[] s) {
    gLogFileTmp ~= s;
}

private void logToConsoleAndFile(LogEntry e) {
    void sink(char[] s) {
        if (gLogFileSink && gLogToFile.get())
            gLogFileSink(s);
        //Trace uses stderr
        if (gLogToConsole.get())
            Trace.write(s);
    }
    e.fmt(&sink);
}

///args = arguments to main(), minus the first argument
///this does GUI unrelated initializations, and the caller (lumbricus.d) does
///GUI initialization after this, because you don't want to pull in all of the
/// GUI for server.d
void init(char[][] args) {
    gLogFileSink = toDelegate(&logToFileTmp); //buffer log until file is opened
    gLogBackendFile.sink = toDelegate(&logToConsoleAndFile);

    cmdlineCheckHelp(args);

    //init filesystem
    auto fs = new FileSystem(APP_ID);
    initFSMounts();

    //xxx it would be nice if the settings conf could simply contain a path to
    //  the game data; would be much simpler than a user conf
    //also, it would be very helpful if you could pass a data path on command
    //  line (downloading some source code, compiling it, and then having
    //  trouble with the game not finding its data path unless it's "properly"
    //  installed is a common issue in general; a command line parameter for
    //  the data path would solve it easily)
    //loading settings shouldn't need any mounted data paths right now; it's
    //  only later that change handlers accessing the FS are installed (such as
    //  locales or GUI themes)
    loadSettings();
    cmdlineLoadSettings(args);

    cmdlineTerminate(args);

    if (gLogToFile.get()) {
        //open logfile in user dir
        //xxx why should it be in the user dir? nobody will look for logiles
        //    _there_; rather they'd expect it in the working dir or so?
        char[] logpath = "/logall.txt";
        gLogInit.minor("opening logfile: {}", logpath);
        const File.Style WriteCreateShared =
            {File.Access.Write, File.Open.Create, File.Share.Read};
        try {
            auto logf = gFS.open(logpath, WriteCreateShared);
            //Closure just for converting write(ubyte[]) to sink(char[])...
            struct Closure {
                stream.PipeOut writer;
                void sink(char[] s) {
                    writer.write(cast(ubyte[])s);
                }
            }
            auto c = new Closure;
            c.writer = (new ThreadedWriter(logf)).pipeOut();
            //write buffered log
            c.sink(gLogFileTmp);
            gLogFileSink = &c.sink;
        } catch (IOException e) {
            gLogInit.error("Failed to open logfile: {}", e.msg);
            gLogFileSink = null;
        }
        gLogFileTmp = null;
    } else {
        gLogFileSink = null;
        gLogFileTmp = null;
    }

    //needs at least the user FS
    readLogConf();

    //-- other initializations, that need the full FS

    //this could be delayed until code interaction with the user really needs it
    relistAllSettings();

    //this will cause i18n.d to re-init the translations, even if the current
    //  language is the same
    initI18N();

    loadColors(loadConfig("colors"));
}

//load settings from cmd line
//make sure everything in args has been used
//use exit() on errors or help requests
void cmdlineLoadSettings(ref char[][] args) {
    foreach (s; gSettings) {
        char[] value;
        if (getarg(args, s.name, value)) {
            if (value == "help") {
                relistAllSettings(); //load/scan files to init all s.choices
                Stdout.formatln("{}", settingValueHelp(s.name));
                exit();
            }
            s.set!(char[])(value);
        }
    }
}

//looks if help is requested; if yes, print and exit()
void cmdlineCheckHelp(ref char[][] args) {
    if (!getarg(args, "help"))
        return;

    void line(char[] s) { Stdout(s).newline; }

    line("Commandline options:");
    line("  --help");
    foreach (s; gSettings) {
        line("  --" ~ s.name~ "=VALUE");
    }
    line("Some options can list possible choices by passing help as value.");
    line("Most settings passed to the command line will be saved "
        "permanently in the");
    line("settings file.");

    exit();
}

//make sure no args are left over; otherwise print error and exit()
void cmdlineTerminate(ref char[][] args) {
    if (args.length) {
        Stdout.formatln("Unknown command line arguments: {}", args);
        Stdout.formatln("Try --help instead.");
        exit();
    }
    args = null;
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
    gLogInit.minor("found attachment, format='{}', size={} bytes", att.fmt, sz);
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
        gLogInit.minor("using attachment instead of mounting data path");
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

    if (mountConfUser) {
        gLogInit.minor("processing user defined mount.conf");
        readMountConf(mountConfUser);
    }
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
    assert(nargs == 0 || nargs == 1);

    void error(char[] fmt, ...) {
        Stdout.formatln("{}", myformat_fx(fmt, _arguments, _argptr));
        exit();
    }

    foreach (int i, a; args) {
        if (!str.eatStart(a, "--"))
            continue;
        if (!str.eatStart(a, name))
            continue;
        if (a.length && a[0] != '=')
            continue;
        if (nargs == 0) {
            if (a.length)
                error("option {} doesn't take an argument ('{}')", name, a);
        } else {
            if (!str.eatStart(a, "="))
                error("argument expected for option {}", name);
            getargs[0] = a;
        }
        marray.arrayRemoveN(args, i);
        return true;
    }
    return false;
}
