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

import str = std.string;

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

    ///if this isn't set, closing the window will terminate the task
    ///if it is set, and it returns...
    ///  false: nothing happens
    ///  true: this.visible = false;
    bool delegate(Window sender) onClose;

    this(WindowManager manager, Task owner) {
        mManager = manager;
        mTask = manager.getTask(owner);
        mWindow = new WindowWidget();

        mManager.mFrame.addDefaultDecorations(mWindow);
        mWindow.onKeyBinding = &onWindowAction;
    }

    private void onWindowAction(WindowWidget sender, char[] action) {
        assert(sender is mWindow);
        switch (action) {
            case "toggle_fs": {
                mWindow.fullScreen = !mWindow.fullScreen;
                break;
            }
            case "close": {
                if (onClose) {
                    if (onClose(this))
                        visible = false;
                } else {
                    mTask.mTask.terminate();
                }
                break;
            }
            default:
                globals.defaultOut.writefln("window action '%s'??", action);
        }
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
            mWindow.remove();
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

    Task task() {
        return mTask.mTask;
    }
}

class WindowManager {
    private {
        PerTask[Task] mTaskList;
        GuiMain mGuiMain;
        WindowFrame mFrame;
        CommandBucket mCmds;
        WindowSwitcher mSwitcher; //null or current instance
        Window mCurHighlight;
    }

    //WindowManager is supposed to take over control completely
    //this also means WindowManager is a singleton (?)
    this(GuiMain gui) {
        mGuiMain = gui;
        mFrame = new WindowFrame;
        gui.mainFrame.add(mFrame);

        mFrame.onSelectWindow = &onSelectWindow;

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

    private Window windowFromWidget(WindowWidget w) {
        foreach (pt; mTaskList) {
            foreach (window; pt.mWindows) {
                if (window.mWindow is w)
                    return window;
            }
        }
        return null;
    }

    Window activeWindow() {
        return windowFromWidget(mFrame.focusWindow());
    }
    void activeWindow(Window w) {
        if (w && w.visible && w.mWindow)
            w.mWindow.activate();
    }

    void highlightWindow(Window w) {
        if (mCurHighlight) {
            mCurHighlight.mWindow.highlight = false;
            mCurHighlight = null;
        }
        if (w && w.visible) {
            w.mWindow.highlight = true;
            mCurHighlight = w;
        }
    }

    //get all windows managed by this; is slow
    struct TaskListEntry { //xxx: maybe just make PerTask public and use it here
        Task task;
        Window[] windows;
    }
    TaskListEntry[] getWindowList() {
        TaskListEntry[] res;
        foreach (pt; mTaskList) {
            res ~= TaskListEntry(pt.mTask, pt.mWindows.dup);
        }
        return res;
    }

    private void onSelectWindow(bool sel_end) {
        if (!sel_end && !mSwitcher) {
            mSwitcher = new WindowSwitcher(this);
            mSwitcher.setLayout(WidgetLayout.Noexpand());
            mSwitcher.zorder = WindowZOrder.Murks;
            mFrame.addWidget(mSwitcher);
            mSwitcher.selection = activeWindow();
        } else if (sel_end && mSwitcher) {
            Window winner = mSwitcher.selection;
            mSwitcher.remove();
            mSwitcher = null;
            highlightWindow(null);
            if (winner)
                activeWindow = winner;
        } else if (!sel_end && mSwitcher) {
            mSwitcher.switchNext();
        }
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

import framework.framework;
import gui.label;
import gui.tablecontainer;

class WindowSwitcher : Container {
private:
    struct Entry {
        Label entry_w, entry_t; //to highlight them
        Window window;
    }
    Entry[] mEntries;
    int mCurrent = -1;
    WindowManager mWm;

    public this(WindowManager wm) {
        this.mWm = wm;
        drawBox = true;
        WindowManager.TaskListEntry[] wnds = wm.getWindowList();
        int window_lines, task_lines;
        auto table = new TableContainer(2, 2, Vector2i(3, 3));
        auto caption = new Label();
        caption.text = "Window list";
        caption.drawBorder = false;
        table.add(caption, 0, 0, 2, 1);
        foreach (w; wnds) {
            if (!w.windows.length)
                continue;
            int y = table.height;
            table.setSize(table.width, y + w.windows.length + 1);
            auto sp1 = new Spacer();
            sp1.minSize = Vector2i(0, 2);
            sp1.color = Color(0);
            table.add(sp1, 0, y, 2, 1);
            auto tasktitle = new Label();
            tasktitle.text = str.format("%s (%s)", w.task, w.task.taskID);
            tasktitle.drawBorder = false;
            tasktitle.font = gFramework.getFont("big_transparent");
            table.add(tasktitle, 0, y+1, 1, w.windows.length);
            foreach (int index, window; w.windows) {
                auto wndtitle = new Label();
                wndtitle.text = window.properties.windowTitle;
                wndtitle.font = gFramework.getFont("normal_transparent");
                wndtitle.drawBorder = false;
                table.add(wndtitle, 1, y+1+index);
                mEntries ~= Entry(wndtitle, tasktitle, window);
            }
        }

        table.setLayout(WidgetLayout.Border(Vector2i(3, 5)));
        addChild(table);
    }

    void switch_to(int index) {
        void dosel(Label l, bool state) {
            l.background = state ? Color(0.7,0.7,0.7) : Color(0,0,0,0);
        }

        if (index < 0 || index >= mEntries.length)
            return;
        //deselect old one
        if (mCurrent >= 0) {
            dosel(mEntries[mCurrent].entry_w, false);
            dosel(mEntries[mCurrent].entry_t, false);
        }
        mCurrent = index;
        dosel(mEntries[mCurrent].entry_w, true);
        dosel(mEntries[mCurrent].entry_t, true);
        mWm.highlightWindow(mEntries[mCurrent].window);
    }

    public void switchNext() {
        switch_to(mCurrent + 1 == mEntries.length ? 0 : mCurrent + 1);
    }

    public Window selection() {
        return mCurrent < 0 ? null : mEntries[mCurrent].window;
    }
    public void selection(Window w) {
        foreach (int index, e; mEntries) {
            if (e.window is w) {
                switch_to(index);
                return;
            }
        }
        //try a default
        switch_to(0);
    }
}
