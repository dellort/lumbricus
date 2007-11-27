///manages windows: manages a list of Windows per Task, provides drawing of
///windows, possibly provides sth. to select windows (but not yet; but if you
///want to add a taskbar or so, do it here)
///also kills all Windows of a task if a task dies
///uses gui.window to actually draw them (but that's hidden from the user)
module gui.wm;

import common.common;
import common.task;
import framework.commandline;
import gui.container;
import gui.gui;
import gui.widget;
import gui.window;
import utils.array;
import utils.misc;
import utils.rect2;
import utils.vector2;

public import gui.window : WindowProperties, WindowZOrder;

///the WindowManager singleton, usually created by common/toplevel.d
///(here because it fits and also to avoid circular dependencies etc.)
WindowManager gWindowManager;

//per Task private infos for this module
private class PerTask {
private:
    Task mTask;
    WindowManager mWM;
    Window[] mWindows;

    this(WindowManager wm, Task t) {
        mTask = t;
        mWM = wm;
    }
}

/// used _only_ for initial placement of a window
struct WindowInitialPlacement {
    enum Placement {
        autoplace,
        fullscreen,
        centered,
        manual,
    }
    Placement place;
    Vector2i manualPos;  //only used if place == manual
    Vector2i defaultSize; //only used if place != fullscreen
}

class Window {
    private {
        PerTask mTask;
        WindowManager mManager;
        WindowWidget mWindow;
        Widget mClient;
        WindowInitialPlacement mInitialPlacement;
        WindowProperties mProps;
        bool mCreated; //if it already was placed
    }

    this(WindowManager manager, Task owner) {
        mManager = manager;
        mTask = manager.getTask(owner);
        mWindow = new WindowWidget();
    }

    /// visibility means if the window is created (but if true, it actually
    /// still can be invisible, i.e. if another window covers it completely
    void visible(bool set) {
        //only create if not yet visible
        if (set == !!visible)
            return;

        if (set) {
            //refuse if task dead because no Windows for dead task should exist
            if (!mTask.mTask.alive) {
                //xxx: better error handling *g*
                assert(false);
            }

            auto doplace = !mCreated; //(afraid of sideffects => copy)
            mCreated = true;
            mManager.mFrame.addWindow(mWindow);
            mManager.onWindowCreate(this);

            if (doplace) {
                //do placement...
                mWindow.windowBounds = Rect2i(Vector2i(0),
                    mInitialPlacement.defaultSize);
                alias WindowInitialPlacement.Placement Place;
                switch (mInitialPlacement.place) {
                    case Place.autoplace:
                        //implement if you want this
                        //but to just center it is ok, too
                    case Place.centered:
                        mWindow.position = mManager.mFrame.size/2
                            - mWindow.size/2;
                        break;
                    case Place.manual:
                        mWindow.position = mInitialPlacement.manualPos;
                        break;
                    case Place.fullscreen:
                        mWindow.fullScreen = true;
                        break;
                }
            }
        } else {
            mManager.mFrame.removeWindow(mWindow);
            mManager.onWindowDestroy(this);
        }
    }

    bool visible() {
        return !!mWindow.manager;
    }

    void destroy() {
        //huh it can be so simple
        visible = false;
    }

    void initialPlacement(WindowInitialPlacement wip) {
        mInitialPlacement = wip;
    }
    WindowInitialPlacement initialPlacement() {
        return mInitialPlacement;
    }

    /// the client is the user's GUI shown inside the window
    Widget client() {
        return mClient;
    }
    void client(Widget c) {
        mClient = c;
        mWindow.client = c;
    }

    WindowProperties properties() {
        return mWindow.properties;
    }
    void properties(WindowProperties props) {
        mWindow.properties = props;
    }

    /// take over the current possibly-forced size of the window as user choice
    /// (usefull when: the client is larger than the user-chosen size, and then
    ///  you want to avoid automatic resizing if the client gets smaller again)
    void acceptSize() {
        mWindow.acceptSize();
    }
}

class WindowManager {
    private {
        PerTask[Task] mTaskList;
        GuiMain mGuiMain;
        WindowFrame mFrame;
        CommandBucket mCmds;
    }

    //WindowManager is supposed to take over control completely
    //this also means WindowManager is a singleton (?)
    this(GuiMain gui) {
        mGuiMain = gui;
        mFrame = new WindowFrame;
        gui.mainFrame.add(mFrame);

        mCmds = new CommandBucket();
        registerCommands();
        mCmds.bind(globals.cmdLine);
    }

    ///create a Window (convenience function)
    /// task = an alive task which should own the window
    /// client = contents of the Window's client area
    /// title = title shown in the Window's decoration
    /// initSize = initial prefered size (real size is the maximum of the client
    ///    Widget's requested size and this)
    /// show = show initially (Window.visible)
    Window createWindow(Task task, Widget client, char[] title,
        Vector2i initSize = Vector2i(0, 0), bool show = true)
    {
        auto w = new Window(this, task);
        w.client = client;
        WindowInitialPlacement ip;
        ip.defaultSize = initSize;
        w.initialPlacement = ip;
        WindowProperties props;
        props.windowTitle = title;
        w.properties = props;
        w.visible = show;
        return w;
    }

    ///similar to createWindow, but start in fullscreen mode
    ///default size is set to current screen's size
    Window createWindowFullscreen(Task task, Widget client, char[] title,
        bool show = true)
    {
        auto w = createWindow(task, client, title, mFrame.size, false);
        auto ip = w.initialPlacement;
        ip.place = WindowInitialPlacement.Placement.fullscreen;
        w.initialPlacement = ip;
        w.visible = show;
        return w;
    }

    //possibly (but not always) returns null if task is dead
    private PerTask getTask(Task task) {
        auto pptask = task in mTaskList;
        if (pptask)
            return *pptask;
        if (!task.alive)
            return null;
        PerTask res = new PerTask(this, task);
        mTaskList[task] = res;
        task.registerOnDeath(&onTaskDeath);
        return res;
    }

    private void onTaskDeath(Task t) {
        assert(!t.alive);
        //remove the task from internal list and also kill all its owned windows
        PerTask pt = getTask(t);
        if (pt) {
            while (pt.mWindows.length > 0) {
                pt.mWindows[0].destroy();
            }
        }
        mTaskList.remove(t);
    }

    //called from Window only
    //NOTE: this is about the visibility of windows; i.e. they can be destroyed
    //  and then be "created" again
    private void onWindowCreate(Window w) {
        w.mTask.mWindows ~= w;
    }
    private void onWindowDestroy(Window w) {
        arrayRemove(w.mTask.mWindows, w);
    }

    private void registerCommands() {
        mCmds.register(Command("windows", &cmdWindows, "list all active windows"
            " by task"));
    }

    private void cmdWindows(MyBox[] args, Output write) {
        foreach (pt; mTaskList.values) {
            write.writefln("%d (%s):", pt.mTask.taskID, pt.mTask);
            foreach (Window w; pt.mWindows) {
                write.writefln("    window, client = '%s'", w.client);
                write.writefln("        title: ", w.properties.windowTitle);
                write.writefln("        pos: ", w.mWindow.windowBounds);
                write.writefln("        fullscreen: ", w.mWindow.fullScreen);
                write.writefln("        focused: ", w.mWindow.focused);
            }
        }
    }
}
