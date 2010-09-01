//connects GUI, Task-stuff and the framework; also contains general stuff
module common.toplevel;

import common.common;
import common.task;
import framework.commandline;
import framework.font;
import framework.globalsettings;
import framework.i18n;
import framework.imgwrite;
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
import utils.perf;
import utils.stream;
import utils.time;

//import all restypes because of the factories (more for debugging...)
import common.allres;

//bloaty "stuff" to help with debugging (questionable)
//this module registers itself via static this
debug import common.debugstuff;

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
class TopLevel {
private:
    KeyBindings keybindings;

    GUI mGui;
    SystemConsole mGuiConsole;

    bool mKeyNameIt = false;

    int mOldFixedFramerate;

    PerfTimer mTaskTime, mGuiDrawTime, mGuiFrameTime;

    public this() {
        assert(!gTopLevel, "singleton");
        gTopLevel = this;

        mTaskTime = globals.newTimer("tasks");
        mGuiDrawTime = globals.newTimer("gui_draw");
        mGuiFrameTime = globals.newTimer("gui_frame");

        mGui = new GUI();

        GuiFps fps = new GuiFps();
        fps.zorder = GUIZOrder.FPS;
        mGui.mainFrame.add(fps);

        mGuiConsole = new SystemConsole();
        mGuiConsole.zorder = GUIZOrder.Console;
        WidgetLayout clay;
        clay.fill[1] = 1.0f/2;
        clay.alignment[1] = 0;
        clay.border = Vector2i(4);
        mGui.mainFrame.add(mGuiConsole, clay);

        initConsole();

        gWindowFrame = new WindowFrame();
        mGui.mainFrame.add(gWindowFrame);

        gFramework.onUpdate = &onUpdate;
        gFramework.onFrame = &onFrame;
        gFramework.onInput = &onInput;
        gFramework.onVideoInit = &onVideoInit;
        gFramework.onFocusChange = &onFocusChange;

        //do it yourself... (initial event)
        onVideoInit();

        keybindings = new KeyBindings();
        keybindings.loadFrom(loadConfig("binds").getSubNode("binds"));

        ConfigNode autoexec = loadConfig("autoexec");
        foreach (char[] name, char[] value; autoexec) {
            mGuiConsole.cmdline.execute(value);
        }
    }

    private void initConsole() {
        globals.real_cmdLine = mGuiConsole.cmdline;

        mGuiConsole.cmdline.commands.addSub(globals.cmdLine);
        globals.cmdLine.helpTranslator = localeRoot.bindNamespace(
            "console_commands.global");

        globals.cmdLine.registerCommand("quit", &killShortcut, "");
        globals.cmdLine.registerCommand("toggle", &showConsole, "");
        globals.cmdLine.registerCommand("nameit", &cmdNameit, "");
        globals.cmdLine.registerCommand("video", &cmdVideo, "",
            ["int", "int", "int?=0", "bool?"]);
        globals.cmdLine.registerCommand("fullscreen", &cmdFS, "", ["text?"]);
        globals.cmdLine.registerCommand("screenshot", &cmdScreenshot,
            "", ["text?"]);
        globals.cmdLine.registerCommand("screenshotwnd", &cmdScreenshotWnd,
            "", ["text?"]);

        globals.cmdLine.registerCommand("spawn", &cmdSpawn, "",
            ["text", "text?..."], [&complete_spawn]);
        globals.cmdLine.registerCommand("help_spawn", &cmdSpawnHelp, "");

        globals.cmdLine.registerCommand("res_load", &cmdResLoad, "", ["text"]);
        globals.cmdLine.registerCommand("res_unload", &cmdResUnload, "", []);

        globals.cmdLine.registerCommand("release_caches", &cmdReleaseCaches,
            "", ["bool?=true"]);

        globals.cmdLine.registerCommand("fw_settings", &cmdFwSettings,
            "", null);

        //settings
        globals.cmdLine.registerCommand("settings_set", &cmdSetSet, "",
            ["text", "text..."]);
        globals.cmdLine.registerCommand("settings_help", &cmdSetHelp, "",
            ["text"]);
        globals.cmdLine.registerCommand("settings_list", &cmdSetList, "", []);
        //used for key shortcuts
        globals.cmdLine.registerCommand("settings_cycle", &cmdSetCycle, "",
            ["text"]);
    }

    private void cmdFwSettings(MyBox[] args, Output write) {
        createPropertyEditWindow("Framework settings");
    }

    private void cmdSetSet(MyBox[] args, Output write) {
        char[] name = args[0].unbox!(char[]);
        char[] value = args[1].unbox!(char[]);
        setSetting(name, value);
    }

    private void cmdSetHelp(MyBox[] args, Output write) {
        char[] name = args[0].unbox!(char[]);
        write.writefln("{}", settingValueHelp(name));
    }

    private void cmdSetList(MyBox[] args, Output write) {
        foreach (s; gSettings) {
            write.writefln("{} = {}", s.name, s.value);
        }
    }

    private void cmdSetCycle(MyBox[] args, Output write) {
        char[] name = args[0].unbox!(char[]);
        settingCycle(name, +1);
    }

    private void cmdReleaseCaches(MyBox[] args, Output write) {
        int released = gFramework.releaseCaches(args[0].unbox!(bool));
        write.writefln("released {} memory consuming house shoes", released);
    }

    private void cmdResUnload(MyBox[] args, Output write) {
        gResources.unloadAll();
    }

    private void cmdResLoad(MyBox[] args, Output write) {
        char[] s = args[0].unbox!(char[])();
        try {
            gResources.loadResources(s);
        } catch (CustomException e) {
            write.writefln("failed: {}", e);
        }
    }

    private void cmdSpawn(MyBox[] args, Output write) {
        char[] name = args[0].unbox!(char[])();
        char[] spawnArgs = args[1].unboxMaybe!(char[])();
        if (!spawnTask(name, spawnArgs)) {
            write.writefln("not found ({})", name);
        }
    }

    private char[][] complete_spawn() {
        return taskList();
    }

    private void cmdSpawnHelp(MyBox[] args, Output write) {
        write.writefln("registered task classes: {}", taskList());
    }

    private void onVideoInit() {
        globals.log("Changed video: {}", gFramework.screenSize);
        mGui.size = gFramework.screenSize;
        globals.saveVideoConfig();
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
        bool desktop = args[0].unboxMaybe!(char[]) == "desktop";
        try {
            if (desktop) {
                //go fullscreen in desktop mode
                gFramework.setVideoMode(gFramework.desktopResolution, -1, true);
            } else {
                //toggle fullscreen
                globals.setVideoFromConf(true);
            }
        } catch (CustomException e) {
            //fullscreen switch failed
            write.writefln("error: {}", e);
        }
    }

    const cScreenshotDir = "/screenshots/";

    private void cmdScreenshot(MyBox[] args, Output write) {
        char[] filename = args[0].unboxMaybe!(char[]);
        saveScreenshot(filename, false);
        write.writefln("Screenshot saved as '{}'", filename);
    }

    private void cmdScreenshotWnd(MyBox[] args, Output write) {
        char[] filename = args[0].unboxMaybe!(char[]);
        saveScreenshot(filename, true);
        write.writefln("Screenshot saved as '{}'", filename);
    }

    //save a screenshot to a png image
    //  activeWindow: only save area of active window, with decorations
    //    (screen contents of window area, also saves overlapping stuff)
    private void saveScreenshot(ref char[] filename,
        bool activeWindow = false)
    {
        //get active window, and its title
        WindowWidget topWnd = gWindowFrame.activeWindow();
        char[] wndTitle;
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
                activeWindow?"window-"~wndTitle~"{}":"screen{}", ".png", i);
        }

        scope surf = gFramework.screenshot();
        scope ssFile = gFS.open(filename, File.WriteCreate);
        scope(exit) ssFile.close();  //no close on delete? strange...
        if (activeWindow) {
            //copy out area of active window
            Rect2i r = topWnd.containedBounds;
            scope subsurf = surf.subrect(r);
            saveImage(subsurf, ssFile, "png");
        } else
            saveImage(surf, ssFile, "png");
    }

    private void cmdNameit(MyBox[] args, Output write) {
        mKeyNameIt = true;
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
        mTaskTime.start();
        runTasks();
        mTaskTime.stop();

        mGuiFrameTime.start();
        mGui.frame();
        mGuiFrameTime.stop();
    }

    private void onFrame(Canvas c) {
        mGuiDrawTime.start();
        mGui.draw(c);
        mGuiDrawTime.stop();
    }

    private void onInput(InputEvent event) {
        //for debugging
        //but something similar will be needed for a proper keybindings editor
        if (mKeyNameIt && event.isKeyEvent) {
            if (!event.keyEvent.isDown)
                return;

            BindKey key = BindKey.FromKeyInfo(event.keyEvent);

            mGuiConsole.output.writefln("Key: '{}' '{}', code={} mods={}",
                key.unparse(), globals.translateKeyshortcut(key),
                key.code, key.mods);

            //modifiers are also keys, ignore them
            if (!event.keyEvent.isModifierKey()) {
                mKeyNameIt = false;
            }

            return;
        }

        //execute global shortcuts
        if (event.isKeyEvent) {
            char[] bind = keybindings.findBinding(event.keyEvent);
            if (bind.length > 0) {
                if (event.keyEvent.isDown)
                    mGuiConsole.cmdline.execute(bind);
                return;
            }
        }

        //deliver event to the GUI
        mGui.putInput(event);
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
