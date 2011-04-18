module gui.window;

import common.task;
import framework.commandline;
import framework.config;
import framework.drawing;
import framework.event;
import framework.keybindings;
import gui.boxcontainer;
import gui.button;
import gui.container;
import gui.global;
import gui.label;
import gui.styles;
import gui.tablecontainer;
import gui.widget;
import utils.array;
import utils.configfile;
import utils.math;
import utils.misc;
import utils.rect2;
import utils.vector2;

import str = utils.string;

//initialized and added to GUI by toplevel.d
WindowFrame gWindowFrame;

enum WindowZOrder {
    Normal = 0,
    High = 10, //always on top
    Popup = 19,
    Murks = 20,
}

//only static properties
struct WindowProperties {
    string windowTitle = "<huhu, you forgot to set a title!>";
    bool canResize = true;   //disallow user to resize the window
    bool canMove = true;    //disallow the user to move the window (by kb/mouse)
    Color background = Color.Invalid; //of the client part of the window
    WindowZOrder zorder; //static zorder
}

//return the window w is under, or null if none is found
WindowWidget findWindowFor(Widget widget) {
    while (widget) {
        if (auto wnd = cast(WindowWidget)widget)
            return wnd;
        widget = widget.parent;
    }
    return null;
}

/// A window with proper window decorations and behaviour
class WindowWidget : Widget {
    private {
        Widget mClient; //what's shown inside the window
        Label mTitleBar;

        WindowClient mClientWidget;
        BoxContainer mForClient; //where client is, non-fullscreen mode
        //window frame etc. in non-fullscreen mode
        SimpleContainer mWindowDecoration;

        BoxContainer mTitleContainer; //titlebar + the buttons

        //for the "tooltip" bottom label
        //might need refinement, maybe use a second TitlePart as a way to allow
        //the user to add "OK" and "Cancel" buttons left and right to the label,
        //or something like this
        Label mTooltipLabel;
        bool mShowTooltipLabel;

        Color mBgOverride;

        bool mFullScreen;
        bool mHasDecorations = true;
        Vector2i mFSSavedPos; //saved window position when in fullscreen mode

        //when window is moved around (not for resizing stuff)
        bool mDraging;

        //user-chosen size (ignored on fullscreen)
        //this is for the Window _itself_ (and not the client area)
        Vector2i mUserSize;
        //last recorded real minimum size for the client
        Vector2i mLastMinSize;

        bool mCanResize = true;
        bool mCanMove = true;

        //thingies on the border to resize this window
        class Sizer : Widget {
            int x, y; //directions: -1 left/bottom, 0 fixed, +1 right/top

            bool drag_active;
            Vector2i drag_start;

            override protected void onMouseMove(MouseInfo mouse) {
                if (drag_active && mCanResize) {
                    WindowWidget wnd = this.outer;
                    assert(parent && wnd.parent);

                    //get position within the window's parent
                    auto pos = mouse.pos;
                    wnd.parent.translateCoords(this, pos);

                    //new window rect
                    //there's one problem: there may be borders around the
                    //  window, so you have to fix up the coordinates
                    auto bounds = wnd.containerBounds;
                    auto subbnds = wnd.containedBounds;
                    auto b1 = subbnds.p1 - bounds.p1; //top/left NC border
                    auto b2 = bounds.p2 - subbnds.p2; //bottom/right
                    auto b = b1 + b2; //summed width/height of all borders
                    auto minsize = mLastMinSize + b;
                    int[2] s = [x, y];
                    for (int n = 0; n < 2; n++) {
                        if (s[n] < 0) {
                            auto npos = pos[n] - drag_start[n];
                            //clip so that window doesn't move if it becomes
                            //too small (when sizing on the left/top borders)
                            bounds.p1[n] = min(npos, bounds.p2[n] - minsize[n]);
                        } else if (s[n] > 0) {
                            //no "clipping" required
                            bounds.p2[n] = pos[n] + (size[n] - drag_start[n]);
                        }
                    }
                    mUserSize = bounds.size - b;
                    wnd.needResize();
                    wnd.position = bounds.p1;
                }
            }

            override bool onKeyDown(KeyInfo key) {
                if (!key.isMouseButton)
                    return false;
                drag_active = true;
                drag_start = mousePos;
                return true;
            }

            override void onKeyUp(KeyInfo key) {
                if (key.isMouseButton)
                    drag_active = false;
            }

            this(int a_x, int a_y) {
                focusable = false;
                x = a_x; y = a_y;
                styles.addClass("window-sizer");
                string spc;
                if (x == 0)
                    spc = "ns";
                else if (y == 0)
                    spc = "we";
                else if (x != y)
                    spc = "nesw";
                else
                    spc = "nwse";
                styles.addClass("window-sizer-" ~ spc);
                //sizers fill the whole border on the sides
                WidgetLayout lay;
                lay.expand[0] = (a_x == 0);
                lay.expand[1] = (a_y == 0);
                setLayout(lay);
            }
        }
    }

    ///clock on close button or close shortcut
    ///if null, remove the window from the GUI
    void delegate(WindowWidget sender) onRequestClose;

    ///invoked when focus was taken
    void delegate(WindowWidget sender) onFocusLost;

    ///in _any_ case the window is removed from the WindowFrame
    void delegate(WindowWidget sender) onClose;

    ///always call acceptSize() after resize
    bool alwaysAcceptSize = true;

    //for popups
    bool closeOnDefocus = false;

    //if the window is active, the commands are available on the global cmdline
    //for use with common/toplevel.d
    CommandBucket commands;

    this() {
        focusable = true;

        //add decorations etc.
        auto all = new TableContainer(3, 3);
        //xxx ideally would subclass/messify TableContainer or so, but meh.
        mWindowDecoration = new SimpleContainer();
        mWindowDecoration.styles.addClass("window-decoration");
        mWindowDecoration.add(all);

        styles.addClass("w-window");

        void sizer(int x, int y) {
            all.add(new Sizer(x, y), x+1, y+1);
        }

        //all combinations of -1/0/+1, except (0, 0)
        sizer(-1, -1);
        sizer(-1,  0);
        sizer(-1, +1);
        sizer( 0, -1);
        sizer( 0, +1);
        sizer(+1, -1);
        sizer(+1,  0);
        sizer(+1, +1);

        mForClient = new BoxContainer(false, false, 5);

        mTitleContainer = new BoxContainer(true);
        mTitleContainer.styles.addClass("window-title-bar");
        mTitleContainer.setLayout(WidgetLayout.Expand(true));
        mForClient.add(mTitleContainer);

        all.add(mForClient, 1, 1);

        mClientWidget = new WindowClient();

        mTitleBar = new Label();
        mTitleBar.shrink = true;
        mTitleBar.styles.addClass("window-title");

        mTooltipLabel = new Label();
        mTooltipLabel.styles.addClass("tooltip-label");
        WidgetLayout lay;
        lay.expand[] = [true, false];
        lay.pad = 2;
        lay.padA.y = 2; //additional space on top
        mTooltipLabel.setLayout(lay);
        mTooltipLabel.shrink = true;
        mTooltipLabel.centerX = true;

        WindowProperties p;
        properties = p; //to be consistent

        recreateGui();
    }

    //when that button in the titlebar is pressed
    //currently only showed if fullScreen is false, hmmm
    private void onToggleFullScreen(Button sender) {
        fullScreen = !fullScreen;
    }

    private void recreateGui() {
        mClientWidget.remove();
        mClientWidget.readdClient();

        if (mFullScreen || !mHasDecorations) {
            clear();
            addChild(mClientWidget);
        } else {
            mForClient.add(mClientWidget);

            if (mWindowDecoration.parent !is this) {
                clear();
                addChild(mWindowDecoration);
            }
        }

        mClientWidget.styles.setState("full-screen", mFullScreen);
    }

    void position(Vector2i pos) {
        containerPosition = pos;
    }
    Vector2i position() {
        return containerPosition;
    }

    ///set initial size
    void initSize(Vector2i s) {
        mUserSize = s;
        needResize();
    }

    ///usersize to current minsize (in case usersize is smaller)
    void acceptSize(bool ignore_if_fullscreen = true) {
        if (ignore_if_fullscreen && mFullScreen)
            return;
        mUserSize = mUserSize.max(mLastMinSize);
        //actually not needed, make spotting errors easier
        //or maybe it's actually needed
        needResize();
    }

    override Vector2i layoutSizeRequest() {
        mLastMinSize = super.layoutSizeRequest();
        //mUserSize is the window size as requested by the user
        //but don't make it smaller than the GUI code wants it
        return mLastMinSize.max(mUserSize);
    }

    override protected void layoutSizeAllocation() {
        super.layoutSizeAllocation();
        if (alwaysAcceptSize)
            acceptSize(true);
    }

    bool fullScreen() {
        return mFullScreen;
    }
    void fullScreen(bool set) {
        if (mFullScreen == set)
            return;

        mFullScreen = set;

        if (set) {
            mFSSavedPos = position;
        }

        recreateGui();

        needRelayout();

        if (parent)
            parent.needRelayout();

        if (!set) {
            position = mFSSavedPos;
        }
    }

    ///you can switch off all window decorations (title, buttons, resizers, any
    ///drawing done by this Window widget) by setting this to false
    bool hasDecorations() {
        return mHasDecorations;
    }
    void hasDecorations(bool set) {
        if (mHasDecorations == set)
            return;

        mHasDecorations = set;
        recreateGui();
    }

    ///set if the tooltip label on the bottom is visible
    bool showTooltipLabel() {
        return mShowTooltipLabel;
    }
    void showTooltipLabel(bool set) {
        if (mShowTooltipLabel == set)
            return;

        mShowTooltipLabel = set;
        recreateGui();
    }

    /// client Widget shown in the window
    /// in fullscreen mode, the Widget's .doesCover method is queried to see if
    /// the background should be cleared (use with care etc.)
    Widget client() {
        return mClient;
    }
    void client(Widget w) {
        if (w is mClient)
            return;
        mClient = w;
        recreateGui();
    }

    WindowProperties properties() {
        WindowProperties res;
        res.windowTitle = mTitleBar.text;
        res.background = mBgOverride;
        res.canResize = mCanResize;
        res.zorder = cast(WindowZOrder)zorder;
        return res;
    }
    void properties(WindowProperties props) {
        mTitleBar.textMarkup = props.windowTitle;
        mBgOverride = props.background;
        mCanResize = props.canResize;
        mCanMove = props.canMove;
        zorder = props.zorder;
    }

    ///the titlebar... do with it what you want, the WindowWidget only uses this
    ///for the .text property
    Label titleBar() {
        return mTitleBar;
    }

    void activate() {
        claimFocus();
    }

    override void simulate() {
        super.simulate();
        pollFocus();
    }

    override bool doesDelegateFocusToChildren() {
        return true;
    }

    private void pollFocus() {
        mWindowDecoration.styles.setState("active", subFocused);

        if (!subFocused) {
            if (closeOnDefocus)
                remove();
            if (onFocusLost)
                onFocusLost(this);
        }
    }

    override bool greedyFocus() {
        return true;
    }

    //tab shouldn't leave window
    override bool allowLeaveFocusByTab() {
        return false;
    }

    void doAction(string s) {
        switch (s) {
            case "toggle_fs": {
                fullScreen = !fullScreen;
                break;
            }
            case "close": {
                if (onRequestClose) {
                    onRequestClose(this);
                } else {
                    remove();
                }
                break;
            }
            case "toggle_ontop": {
                zorder = !zorder;
                break;
            }
            default:
                //globals.defaultOut.writefln("window action '{}'??", s);
        }
    }

    override bool handleChildInput(InputEvent event) {
        //dirty hack to focus windows if you click into them
        if (event.isKeyEvent && event.keyEvent.isMouseButton())
            activate();
        //dragging/catching key shortcuts
        if (mDraging
            || (event.isKeyEvent && findBind(event.keyEvent) != ""))
        {
            deliverDirectEvent(event, false);
            //mask events from children
            return true;
        }
        return super.handleChildInput(event);
    }

    //treat all events as handled (?)
    override bool onKeyDown(KeyInfo key) {
        string bind = findBind(key);

        if (bind.length) {
            doAction(bind);
            return true;
        }

        //if a mouse click wasn't handled, start draging the window around
        //xxx mostly inactive (filtered out by allowInputForChild())
        if (key.code == Keycode.MOUSE_LEFT) {
            mDraging = true;
            return true;
        }
        //always handle clicks (don't click through)
        if (key.isMouseButton()) {
            return true;
        }

        return false;
    }

    override void onKeyUp(KeyInfo key) {
        if (key.isMouseButton && mDraging) {
            //stop draging by any further mouse-up event
            mDraging = false;
        }
    }

    protected void onMouseMove(MouseInfo mouse) {
        if (mDraging) {
            if (mCanMove && !mFullScreen) {
                position = position + mouse.rel;
            }
        } else {
            super.onMouseMove(mouse);
        }
    }

    override void onChildMouseEnterLeave(Widget child, bool mouseIsInside) {
        assert(!!child);
        if (mouseIsInside && child.tooltip.length) {
            mTooltipLabel.text = child.tooltip;
        } else {
            mTooltipLabel.text = ""; //show some default message?
        }
    }

    override void onDrawBackground(Canvas c, Rect2i area) {
        //on full screen, leave it to WindowClient
        if (mFullScreen)
            return;
        super.onDrawBackground(c, area);
    }

    override void onDrawFocus(Canvas c) {
        //nothing, but see pollFocus()
    }

    override bool doesCover() {
        return mHasDecorations && mFullScreen && !mShowTooltipLabel;
    }

    protected Color fsClearColor() {
        return styles.get!(Color)("window-fullscreen-color");
    }

    class WindowClient : BoxContainer {
        this() {
            super(false);
            doClipping = true;
        }
        void readdClient() {
            clear();
            if (mClient) {
                mClient.remove();
                add(mClient);
            }
            if (mShowTooltipLabel) {
                mTooltipLabel.remove();
                add(mTooltipLabel);
            }
        }
        //draw the background override
        //on fullscreen, this is always called; if there's no background
        //  override, use fsClearColor() (it's simpler this way)
        override void onDrawBackground(Canvas c, Rect2i area) {
            if (!mBgOverride.valid && !mFullScreen)
                return;
            if (mClient && mClient.doesCover && !mShowTooltipLabel)
                return;
            Color back = mBgOverride.valid ? mBgOverride : fsClearColor();
            c.drawFilledRect(area, back);
        }
    }

    //called by WindowFrame only
    package void wasRemoved() {
        if (onClose)
            onClose(this);
    }

    bool wasClosed() {
        return !parent;
    }

    string toString() {
        return "["~super.toString~" '"~mTitleBar.text~"']";
    }
}

/// Special container for Windows; i.e can deal with "fullscreen" windows
/// efficiently (won't draw other windows then)
class WindowFrame : Container {
    private {
        WindowWidget[] mWindows;  //all windows
        ConfigNode mConfig;
        KeyBindings mKeysWindow, mKeysWM;

        //previous window switcher dialog, or null
        WindowWidget mSwitchWindow;
    }

    this() {
        setVirtualFrame(false); //wtf

        checkCover = true;

        styles.addClass("mainframe");

        mConfig = loadConfig("window.conf");

        mKeysWindow = new KeyBindings();
        mKeysWindow.loadFrom(mConfig.getSubNode("window_bindings"));
        mKeysWM = new KeyBindings();
        mKeysWM.loadFrom(mConfig.getSubNode("wm_bindings"));
    }

    override bool doesDelegateFocusToChildren() {
        return true;
    }

    private static class ButtonAction {
        WindowWidget mWindow;
        string mAction;
        static void Set(Button button, WindowWidget a_window, string a_action) {
            auto a = new ButtonAction;
            a.mWindow = a_window;
            a.mAction = a_action;
            button.onClick = &a.onButton;
        }
        private void onButton(Button sender) {
            mWindow.doAction(mAction);
        }
    }

    private void addDefaultDecorations(WindowWidget wnd) {
        void adddec(Widget w) {
            wnd.mTitleContainer.add(w);
        }
        void button(string action, string markup) {
            auto b = new Button;
            b.textMarkup = markup;
            b.styles.addClass("window-button");
            b.setLayout(WidgetLayout.Expand(false));
            b.allowFocus = false;
            ButtonAction.Set(b, wnd, action);
            adddec(b);
        }

        adddec(wnd.mTitleBar);

        button("toggle_ontop", r"\imgres(scroll_up)");
        button("toggle_fs", r"\imgres(window_maximize)");
        button("close", r"\imgres(window_close)");
    }

    void addWindow(WindowWidget wnd) {
        wnd.remove();
        wnd.bindings = mKeysWindow;
        mWindows ~= wnd;
        addChild(wnd);
    }

    void addWindowCentered(WindowWidget wnd) {
        wnd.remove();
        wnd.bindings = mKeysWindow;
        addDefaultDecorations(wnd);
        mWindows ~= wnd;
        addChild(wnd);
        //size is only there after it has been added
        Rect2i nrc;
        nrc += this.size/2 - wnd.size/2;
        wnd.position = nrc.p1;
    }

    void addWidget(Widget w) {
        w.remove();
        addChild(w);
    }

    override protected void removeChild(Widget child) {
        //could be a "real" window; if not, then wtf?
        auto wnd = cast(WindowWidget)child;
        if (wnd) {
            arrayRemove(mWindows, wnd);
        }
        super.removeChild(child);
        if (wnd)
            wnd.wasRemoved();
    }

    WindowWidget activeWindow() {
        WindowWidget best;
        foreach (w; mWindows) {
            if (!best || w.maxFocusAge() > best.maxFocusAge())
                best = w;
        }
        return best;
    }

    protected override Vector2i layoutSizeRequest() {
        //wtf should I do here? better stay consistent
        return Vector2i(0);
    }

    protected override void layoutSizeAllocation() {
        foreach (Widget c; children) {
            auto w = cast(WindowWidget)c;
            if (w) {
                Rect2i alloc;
                if (w.fullScreen) {
                    alloc = widgetBounds();
                } else {
                    auto s = w.layoutCachedContainerSizeRequest();
                    auto p = w.containerBounds.p1;
                    alloc = Rect2i(p, p + s);
                }
                w.layoutContainerAllocate(alloc);
            } else {
                c.layoutContainerAllocate(widgetBounds());
            }
        }
    }

    override bool handleChildInput(InputEvent event) {
        if (event.isKeyEvent && mKeysWM.findBinding(event.keyEvent)) {
            deliverDirectEvent(event, false);
            return true;
        }
        return super.handleChildInput(event);
    }

    override bool onKeyDown(KeyInfo info) {
        auto bnd = mKeysWM.findBinding(info);
        if (info.isDown && !info.isRepeated && bnd == "select_window") {
            onSelectWindow();
            return true;
        }
        return false;
    }

    private void onSelectWindow() {
        if (mSwitchWindow) {
            mSwitchWindow.remove();
            mSwitchWindow = null;
        }
        auto owner = new WindowWidget();
        auto b = new VBoxContainer();
        struct Closure {
            WindowFrame this_;
            WindowWidget owner;
            WindowWidget w;
            void onClick() {
                this_.mSwitchWindow = null;
                owner.remove();
                w.activate();
            }
        }
        foreach (WindowWidget w; mWindows) {
            auto cl = new Closure;
            *cl = Closure(this, owner, w);
            auto btn = new Button();
            btn.textMarkup = w.properties.windowTitle;
            btn.onClick2 = &cl.onClick;
            b.add(btn);
        }
        auto props = owner.properties;
        props.windowTitle = "select window";
        owner.properties = props;
        owner.client = b;
        addWindowCentered(owner);
        mSwitchWindow = owner;
    }

    //emulate what was in wm.d

    WindowWidget createWindow(Widget client, string title,
        Vector2i initSize = Vector2i(0, 0))
    {
        auto w = new WindowWidget();
        w.initSize = initSize;
        w.client = client;
        auto props = w.properties;
        props.windowTitle = title;
        w.properties = props;
        addWindowCentered(w);
        return w;
    }

    WindowWidget createWindowFullscreen(Widget client, string title) {
        auto w = createWindow(client, title);
        w.fullScreen = true;
        return w;
    }

    //don't use this function (only for dropdownlist compatibility)
    WindowWidget createPopup(Widget client, Widget attach, Vector2i initSize) {
        assert(client && attach);

        auto w = new WindowWidget();
        w.hasDecorations = false;
        w.closeOnDefocus = true;
        w.client = client;
        addWindow(w);

        Widget relative = attach;
        Vector2i tmp;
        if (!w.translateCoords(relative, tmp)) {
            relative = this;
        }

        w.initSize(initSize);

        //nrc is in coordinates of the widget "relative"
        Rect2i nrc = Rect2i(Vector2i(0), w.size);


        nrc += placeRelative(nrc, relative.containedBounds,
            Vector2i(0, 1), 0, 0);

        //translate from "relative" widget coordinates to the ones used by the
        //window, and actually position it
        bool r = this.translateCoords(relative, nrc);
        if (!r) {
            //whatever, fail gracefully
            w.remove();
        }

        //clip size to screen
        nrc.fitInside(this.widgetBounds);
        w.initSize(nrc.size);

        w.position = nrc.p1;

        w.claimFocus();

        return w;
    }
}
