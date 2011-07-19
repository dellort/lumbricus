//connects GUI, Task-stuff and the framework; also contains general stuff
module common.toplevel;

import common.globalconsole;
import common.gui_init;
import common.lua;
import common.task;
import framework.commandline;
import framework.config;
import framework.drawing;
import framework.event;
import framework.filesystem;
import framework.font;
import framework.globalsettings;
import framework.i18n;
import framework.imgwrite;
import framework.lua;
import framework.keybindings;
import framework.keysyms;
import framework.main;
import gui.fps;
import gui.console;
import gui.propedit;
import gui.widget;
import gui.window;
import utils.configfile;
import utils.factory;
import utils.log;
import utils.misc;
import utils.mybox;
import utils.output;
import utils.stream;
import utils.time;

import stats = common.stats;

//import all restypes because of the factories (more for debugging...)
import common.allres;

//ZOrders!
//only for the stuff managed by TopLevel
//note that Widget.zorder can take any value
enum GUIZOrder : int {
    Gui,
    Something, //hack for the fade-"overlay"
    Console,
    FPS,
}

TopLevel gTopLevel;

//this contains the mainframe
//reason why this is an object: you want to get a delegate to most functions
class TopLevel {
private:
    KeyBindings keybindings;

    SystemConsole mGuiConsole;

    //privileged Lua state
    LuaState mLua;

    int mOldFixedFramerate;

    public this() {
        assert(!gTopLevel, "singleton");
        gTopLevel = this;

        auto mainFrame = gGui.mainFrame;

        GuiFps fps = new GuiFps();
        fps.zorder = GUIZOrder.FPS;
        mainFrame.add(fps);

        //"old" console
        mGuiConsole = new SystemConsole();
        mGuiConsole.zorder = GUIZOrder.Console;
        WidgetLayout clay;
        clay.fill[1] = 1.0f/2;
        clay.alignment[1] = 0;
        clay.border = Vector2i(4);
        mainFrame.add(mGuiConsole, clay);

        initConsole();
        initLua();

        gWindowFrame = new WindowFrame();
        mainFrame.add(gWindowFrame);

        //"new" console
        .initConsole(mainFrame, GUIZOrder.Console);

        gFramework.onUpdate = &onUpdate;
        gFramework.onFrame = &onFrame;
        gFramework.onInput = &onInput;
        gFramework.onVideoInit = &onVideoInit;
        gFramework.onFocusChange = &onFocusChange;

        //do it yourself... (initial event)
        onVideoInit();

        keybindings = new KeyBindings();
        keybindings.loadFrom(loadConfig("binds.conf").getSubNode("binds"));

        loadScript(mLua, "init.lua");

        ConfigNode autoexec = loadConfig("autoexec.conf");
        foreach (string name, string value; autoexec) {
            mGuiConsole.cmdline.execute(value);
        }
    }

    static ~this() {
        if (gTopLevel)
            delete gTopLevel.mLua;
    }

    private void initConsole() {
        auto cmds = gCommands;

        mGuiConsole.cmdline.commands.addSub(cmds);
        cmds.helpTranslator = localeRoot.bindNamespace(
            "console_commands.global");

        cmds.registerCommand("quit", &killShortcut, "");
        cmds.registerCommand("toggle", &showConsole, "");
        cmds.registerCommand("video", &cmdVideo, "",
            ["int", "int", "int?=0", "bool?"]);
        cmds.registerCommand("fullscreen", &cmdFS, "", ["text?"]);
        cmds.registerCommand("screenshot", &cmdScreenshot,
            "", ["text?"]);
        cmds.registerCommand("screenshotwnd", &cmdScreenshotWnd,
            "", ["text?"]);

        cmds.registerCommand("spawn", &cmdSpawn, "",
            ["text", "text?..."], [&complete_spawn]);
        cmds.registerCommand("help_spawn", &cmdSpawnHelp, "");

        cmds.registerCommand("release_caches", &cmdReleaseCaches,
            "", ["bool?=true"]);

        cmds.registerCommand("fw_settings", &cmdFwSettings,
            "", null);

        //settings
        cmds.registerCommand("settings_set", &cmdSetSet, "",
            ["text", "text..."]);
        cmds.registerCommand("settings_help", &cmdSetHelp, "",
            ["text"]);
        cmds.registerCommand("settings_list", &cmdSetList, "", []);
        //used for key shortcuts
        cmds.registerCommand("settings_cycle", &cmdSetCycle, "",
            ["text"]);

        //bridge to Lua
        cmds.registerCommand("execlua", &cmdLua, "", ["text..."]);
    }

    //add a Lua command - del should be a delegate or a function ptr
    private void addL(T)(string name, T del) {
        //may change; maybe put all commands into a special table, and do the
        //  same stuff as cmdLine does (providing help, auto completion, etc.)
        mLua.setGlobal(name, del);
    }

    private void initLua() {
        //remember, the state is privileged
        mLua = new LuaState(LuaLib.all);
        loadScript(mLua, "lua/utils.lua");
        loadScript(mLua, "lua/time.lua");
        loadScript(mLua, "lua/timer.lua");
        setLogger(mLua, registerLog("global_lua"));

        auto reg = new LuaRegistry();
        reg.method!(IKillable, "kill");
        //xxx taken from game/lua/base.d, should factor that
        reg.func!(Time.fromString)("timeParse");
        mLua.register(reg);

        //bridge to cmdLine
        addL("exec", function(string cmd) {
            executeGlobalCommand(cmd);
        });

        addL("spawn", function(string cmd) {
            return spawnTask(cmd);
        });
        addL("spawnargs", function(string cmd, string args) {
            return spawnTask(cmd, args);
        });

        addL("dofile", function(string fn) {
            loadScript(gTopLevel.mLua, fn);
        });
    }

    private void cmdLua(MyBox[] args, Output write) {
        string cmd = args[0].unbox!(string);
        mLua.scriptExec("ConsoleUtils.exec(...)", cmd, &write.writeString);
    }

    private void cmdFwSettings(MyBox[] args, Output write) {
        createPropertyEditWindow("Framework settings");
    }

    private void cmdSetSet(MyBox[] args, Output write) {
        string name = args[0].unbox!(string);
        string value = args[1].unbox!(string);
        setSetting(name, value);
    }

    private void cmdSetHelp(MyBox[] args, Output write) {
        string name = args[0].unbox!(string);
        write.writefln("%s", settingValueHelp(name));
    }

    private void cmdSetList(MyBox[] args, Output write) {
        foreach (s; gSettings) {
            write.writefln("%s = %s", s.name, s.value);
        }
    }

    private void cmdSetCycle(MyBox[] args, Output write) {
        string name = args[0].unbox!(string);
        settingCycle(name, +1);
    }

    private void cmdReleaseCaches(MyBox[] args, Output write) {
        int released = gFramework.releaseCaches(args[0].unbox!(bool));
        write.writefln("released %s memory consuming house shoes", released);
    }

    private void cmdSpawn(MyBox[] args, Output write) {
        string name = args[0].unbox!(string)();
        string spawnArgs = args[1].unboxMaybe!(string)();
        spawnTask(name, spawnArgs);
    }

    private string[] complete_spawn() {
        return taskList();
    }

    private void cmdSpawnHelp(MyBox[] args, Output write) {
        write.writefln("registered tasks: %s", taskList());
    }

    private void onVideoInit() {
        //globals.log("Changed video: %s", gFramework.screenSize);
        gGui.size = gFramework.screenSize;
        saveVideoConfig();
    }

    private void cmdVideo(MyBox[] args, Output write) {
        int a = args[0].unbox!(int);
        int b = args[1].unbox!(int);
        int c = args[2].unbox!(int);
        bool fs = gFramework.fullScreen();
        if (!args[3].empty)
            fs = args[3].unbox!(bool);
        try {
            gFramework.setVideoMode(Vector2i(a, b), c, fs);
        } catch (CustomException e) {
            //failed to set video mode, try again in windowed mode
            gFramework.setVideoMode(Vector2i(a, b), c, false);
        }
    }

    private void cmdFS(MyBox[] args, Output write) {
        bool desktop = args[0].unboxMaybe!(string) == "desktop";
        try {
            if (desktop) {
                //go fullscreen in desktop mode
                gFramework.setVideoMode(gFramework.desktopResolution, -1, true);
            } else {
                //toggle fullscreen
                setVideoFromConf(true);
            }
        } catch (CustomException e) {
            //fullscreen switch failed
            write.writefln("error: %s", e);
        }
    }

    enum cScreenshotDir = "/screenshots/";

    private void cmdScreenshot(MyBox[] args, Output write) {
        string filename = args[0].unboxMaybe!(string);
        saveScreenshot(filename, false);
        write.writefln("Screenshot saved as '%s'", filename);
    }

    private void cmdScreenshotWnd(MyBox[] args, Output write) {
        string filename = args[0].unboxMaybe!(string);
        saveScreenshot(filename, true);
        write.writefln("Screenshot saved as '%s'", filename);
    }

    //save a screenshot to a png image
    //  activeWindow: only save area of active window, with decorations
    //    (screen contents of window area, also saves overlapping stuff)
    //throws exception on error (catched by the command line handler)
    private void saveScreenshot(ref string filename,
        bool activeWindow = false)
    {
        //get active window, and its title
        WindowWidget topWnd = gWindowFrame.activeWindow();
        string wndTitle;
        if (topWnd)
            wndTitle = topWnd.properties.windowTitle;
        else
            activeWindow = false;

        if (filename.length > 0) {
            //filename given, prepend screenshot directory
            filename = cScreenshotDir ~ filename;
        } else {
            //no filename, generate one
            int i;
            filename = gFS.getUniqueFilename(cScreenshotDir,
                activeWindow?"window-"~wndTitle~"%s":"screen%s", ".png", i);
        }

        auto surf = gFramework.screenshot();
        scope(exit) surf.free();
        auto ssFile = gFS.open(filename, File.WriteCreate);
        scope(exit) ssFile.close();
        if (activeWindow) {
            //copy out area of active window
            Rect2i r = topWnd.containedBounds;
            auto subsurf = surf.subrect(r);
            scope(exit) subsurf.free();
            saveImage(subsurf, ssFile, ".png");
        } else
            saveImage(surf, ssFile, ".png");
    }

    private void showConsole(MyBox[], Output) {
        mGuiConsole.toggle();
    }
    public bool consoleVisible() {
        return mGuiConsole.consoleVisible();
    }

    private void killShortcut(MyBox[], Output) {
        gFramework.terminate();
    }

    private void onUpdate() {
        stats.startTimer("tasks");
        runTasks();
        stats.stopTimer("tasks");

        stats.startTimer("gui_frame");
        gGui.frame();
        stats.stopTimer("gui_frame");

        updateTimers(mLua, timeCurrentTime());
    }

    private void onFrame(Canvas c) {
        stats.startTimer("gui_draw");
        gGui.draw(c);
        stats.stopTimer("gui_draw");
    }

    private void onInput(InputEvent event) {
        foreach (c; gCatchInput) {
            if (c(event))
                return;
        }

        //execute global shortcuts
        if (event.isKeyEvent) {
            string bind = keybindings.findBinding(event.keyEvent);
            if (bind.length > 0) {
                if (event.keyEvent.isDown)
                    mGuiConsole.cmdline.execute(bind);
                return;
            }
        }

        //deliver event to the GUI
        gGui.putInput(event);
    }

    //app input focus changed
    private void onFocusChange(bool focused) {
        //when the app goes out of focus, limit framerate to 10fps to
        //limit cpu consumption. old fps limit is restored when focused again
        if (focused) {
            gFramework.fixedFramerate = mOldFixedFramerate;
        } else {
            mOldFixedFramerate = gFramework.fixedFramerate;
            gFramework.fixedFramerate = 10;
        }
        //xxx pause game?
    }
}
