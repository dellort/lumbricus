module common.loadsave;

///Generic task loading and saving
///also contains functions to list savegames and extract information

import common.common;
import common.task;
import framework.framework;
import framework.commandline;
import gui.wm;

import utils.archive;
import utils.factory;
import utils.configfile;
import utils.mybox;
import utils.misc;
import utils.log;

import str = stdx.string;
import stdx.stream;

const cSavegamePath = "/savegames/";
const cSavegameExt = ".tar";
const cSavegameDefName = "Save";

LoadSaveHandler gLoadSave;

struct SavegameData {
    char[] path;
    ConfigNode info;

    ///get infos from a savegame file (full filename)
    static SavegameData opCall(char[] fn) {
        SavegameData ret;
        ret.path = fn;
        scope st = gFS.open(fn, FileMode.In);
        scope reader = new TarArchive(st, true);
        auto z = reader.openReadStream("info.conf", false);
        ret.info = z.readConfigFile();
        z.close();
        reader.close();
        return ret;
    }

    ///load this savegame and create a new task
    bool load() {
        return gLoadSave.loadFromData(*this);
    }

    //xxx debug code
    char[] toString() {
        return info["taskid"] ~ ": " ~ info["name"];
    }
}

///Get a list of all available savegames
///Only valid savegames will be returned
//Note: Slooow, each file is opened, and the info file is extracted
SavegameData[] listAvailableSavegames() {
    SavegameData[] list;
    gFS.listdir(cSavegamePath, "*", false,
        (char[] filename) {
            if (endsWith(filename, cSavegameExt)) {
                try {
                    auto s = SavegameData(cSavegamePath ~ filename);
                    list ~= s;
                } catch (Exception e) {
                    //don't crash
                    registerLog("common.loadsave")("Savegame '{}' is invalid: {}",
                        filename, e.msg);
                }
            }
            return true;
        }
    );
    return list;
}

///Create a new, empty savegame file, write infos and call saveFunc to
///store the task state
///saveFunc must not close the archive
SavegameData createSavegame(char[] taskId, char[] name, char[] description,
    void delegate(TarArchive arch) saveFunc)
{
    SavegameData ret;
    //use default name if none given
    if (name.length == 0)
        name = cSavegameDefName;
    //construct a unique filename
    int i;
    ret.path = gFS.getUniqueFilename(cSavegamePath,
        taskId ~ "_" ~ name ~ "{0:d3}", cSavegameExt, i);
    if (i > 1)
        name ~= " (" ~ str.toString(i) ~ ")";
    //open the savegame file for writing
    scope st = gFS.open(ret.path, FileMode.OutNew);
    scope writer = new TarArchive(st, false);
    //set information
    ret.info = new ConfigNode();
    ret.info["taskid"] = taskId;
    ret.info["name"] = name;
    ret.info["description"] = description;
    //xxx how?
    ret.info.setValue("timestamp", 0);
    //write info file
    auto z = writer.openWriteStream("info.conf");
    z.writeConfigFile(ret.info);
    z.close();
    //actually save the task
    saveFunc(writer);
    writer.close();
    return ret;
}

///Base class for tasks which can be saved
abstract class StatefulTask : Task {
    this(TaskManager tm) {
        super(tm);
    }

    ///store current state into archive
    abstract void saveState(TarArchive arch);

    ///Call this to save the current task
    void saveState(char[] name, char[] description = "") {
        gLoadSave.saveTask(this, name, description);
    }

    ///Return a unique id for this task (for save files, shown localized in gui)
    abstract char[] saveId();
}

class SaveException : Exception {
    this(char[] msg) {
        super(msg);
    }
}

///This singleton class manages savegame files and handles task saving/loading
class LoadSaveHandler {
    private TaskManager mManager;

    this(TaskManager mgr) {
        assert(!gLoadSave, "singleton");
        gLoadSave = this;

        mManager = mgr;
        initCommands();
    }

    private char[][] listSavegames() {
        SavegameData[] slist = listAvailableSavegames();
        char[][] ret;
        foreach (ref s; slist) {
            ret ~= s.toString();
        }
        return ret;
    }

    private void initCommands() {
        globals.cmdLine.registerCommand(Command("savetest", &cmdSaveTest,
            "save and reload"));
        globals.cmdLine.registerCommand(Command("save", &cmdSave, "save game",
            ["text?...:name of the savegame (/savegames/<name>.conf)"]));

        Command load = Command("load", &cmdLoad, "load game",
            ["text?...:name of the savegame, if none given, list all available"]);
        load.setCompletionHandler(0, &listSavegames);
        globals.cmdLine.registerCommand(load);
    }

    //load a save file by its name (inside the info.conf)
    private bool doLoad(char[] name) {
        SavegameData[] slist = listAvailableSavegames();
        char[][] ret;
        foreach (ref s; slist) {
            if (s.toString() == name) {
                return loadFromData(s);
            }
        }
        return false;
    }

    //xxx
    private void cmdSaveTest(MyBox[] args, Output write) {
        try {
            registerLog("common.loadsave")("Saving...");
            auto data = saveCurrentTask("test_temp");
            registerLog("common.loadsave")("Loading...");
            data.load();
            registerLog("common.loadsave")("Done.");
        } catch (SaveException e) {
            write.writefln(e.msg);
        }
    }

    //load savegame into a new task
    private void cmdLoad(MyBox[] args, Output write) {
        char[] name = args[0].unboxMaybe!(char[]);
        if (name == "") {
            //list all savegames
            write.writefln("Savegames:");
            foreach (s; listSavegames()) {
                write.writefln("  {}", s);
            }
            write.writefln("done.");
        } else {
            write.writefln("Loading: {}", name);
            bool success = doLoad(name);
            if (!success)
                write.writefln("loading failed!");
        }
    }

    //save the current top-level task
    private void cmdSave(MyBox[] args, Output write) {
        char[] name = args[0].unboxMaybe!(char[]);
        write.writefln("Saving...");
        try {
            auto data = saveCurrentTask(name);
            write.writefln("saved game as '{}'.",data.info["name"]);
        } catch (SaveException e) {
            write.writefln("Error saving: {}", e.msg);
        }
    }

    ///Load data into a new task (like Savegamedata.load())
    bool loadFromData(ref SavegameData data) {
        Stream st;
        try {
            st = gFS.open(data.path, FileMode.In);
        } catch (Exception e) {
            return false;
        }
        scope(exit) st.close();
        scope reader = new TarArchive(st, true);
        StatefulFactory.instantiate(data.info["taskid"], mManager,
            reader);
        reader.close();
        return true;
    }

    ///Save the passed task
    SavegameData saveTask(StatefulTask task, char[] name,
        char[] description = "")
    {
        assert(!!task);
        return createSavegame(task.saveId, name, description, &task.saveState);
    }

    SavegameData saveCurrentTask(char[] name, char[] description = "") {
        auto topWnd = gWindowManager.activeWindow();
        if (!topWnd) {
            throw new SaveException("Unknown active window");
        }
        auto curTask = cast(StatefulTask)(topWnd.task);
        if (!curTask) {
            throw new SaveException("Active task is not saveable");
        }
        return saveTask(curTask, name);
    }
}

//All tasks that should be saved have to register here
alias StaticFactory!("STasks", StatefulTask, TaskManager,
    TarArchive) StatefulFactory;
