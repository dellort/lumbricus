module gui.window;

import framework.config;
import framework.event;
import framework.framework;
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
import utils.misc;
import utils.rect2;
import utils.vector2;

import str = utils.string;

enum WindowZOrder {
    Normal = 0,
    High = 10, //always on top
    Popup = 19,
    Murks = 20,
}

//only static properties
struct WindowProperties {
    char[] windowTitle = "<huhu, you forgot to set a title!>";
    bool canResize = true;   //disallow user to resize the window
    bool canMove = true;    //disallow the user to move the window (by kb/mouse)
    Color background = Color.Invalid; //of the client part of the window
    WindowZOrder zorder; //static zorder
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
        TitlePart[] mTitleParts; //kept sorted by .sort

        //for the "tooltip" bottom label
        //might need refinement, maybe use a second TitlePart as a way to allow
        //the user to add "OK" and "Cancel" buttons left and right to the label,
        //or something like this
        Label mTooltipLabel;
        bool mShowTooltipLabel;

        Color mBgOverride;

        //"window manager"; supported to be null
        WindowFrame mManager;

        bool mFullScreen;
        bool mHasDecorations = true;
        Vector2i mFSSavedPos; //saved window position when in fullscreen mode

        //when window is moved around (not for resizing stuff)
        bool mDraging;

        //user-chosen size (ignored on fullscreen)
        //this is for the Window _itself_ (and not the client area)
        Vector2i mUserSize = {150, 150};
        //last recorded real minimum size for the client
        Vector2i mLastMinSize;

        //size of the window border and the resize boxes
        const cCornerSize = 5;

        bool mCanResize = true;
        bool mCanMove = true;

        struct TitlePart {
            char[] name;
            int priority;
            Widget widget;

            //for sorting
            int opCmp(TitlePart* other) {
                int diff = priority - other.priority;
                if (diff == 0)
                    diff = str.cmp(name, other.name);
                return diff;
            }
        }

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

            override protected void onKeyEvent(KeyInfo key) {
                if (!key.isPress && key.isMouseButton) {
                    drag_active = key.isDown;
                    drag_start = mousePos;
                }
            }

            Vector2i layoutSizeRequest() {
                return Vector2i(cCornerSize);
            }

            override MouseCursor mouseCursor() {
                MouseCursor res;
                char[] resid;
                if (x == 0)
                    resid = "size_ns";
                else if (y == 0)
                    resid = "size_we";
                else if (x != y)
                    resid = "size_nesw";
                else
                    resid = "size_nwse";
                res.graphic = gGuiResources.get!(Surface)(resid);
                res.graphic_spot = res.graphic.size/2;
                return res;
            }

            this(int a_x, int a_y) {
                focusable = false;
                x = a_x; y = a_y;
                //sizers fill the whole border on the sides
                WidgetLayout lay;
                lay.expand[0] = (a_x == 0);
                lay.expand[1] = (a_y == 0);
                setLayout(lay);
            }
        }
    }

    ///catches a window-keybinding
    void delegate(WindowWidget sender, char[] action) onKeyBinding;

    ///invoked when focus was taken
    void delegate(WindowWidget sender) onFocusLost;

    ///in _any_ case the window is removed from the WindowFrame
    void delegate(WindowWidget sender) onClose;

    ///always call acceptSize() after resize
    bool alwaysAcceptSize = true;

    ///expensive way to highlight the whole window (i.e. for window selection)
    bool highlight;

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

    WindowFrame manager() {
        return mManager;
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

    /// add a button or anything to the titlebar
    /// name = unique name; if a part with that name already exists, return
    /// false and do nothing
    /// priority = sorted from left to right by priority
    /// w = the widget; must be non-null, the window code can add/remove this
    /// widget anytime (i.e. switching fullscreen mode), also, its .layout will
    /// be used (best choice is WidgetLayout.Noexpand())
    bool addTitlePart(char[] name, int priority, Widget w) {
        assert(w !is null);

        if (findTitlePart(name) >= 0)
            return false;

        mTitleParts ~= TitlePart(name, priority, w);
        recreateTitle();

        return true;
    }

    bool removeTitlePart(char[] name) {
        int index = findTitlePart(name);
        if (index < 0)
            return false;

        mTitleParts = mTitleParts[0..index] ~ mTitleParts[index+1..$];
        recreateTitle();

        return true;
    }

    private int findTitlePart(char[] name) {
        foreach (int index, b; mTitleParts) {
            if (b.name == name)
                return index;
        }
        return -1;
    }

    private void recreateTitle() {
        mTitleContainer.clear();
        mTitleParts.sort;
        foreach (p; mTitleParts) {
            mTitleContainer.add(p.widget);
        }
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

        if (!subFocused && onFocusLost)
            onFocusLost(this);
    }

    override bool greedyFocus() {
        return true;
    }

    //tab shouldn't leave window
    override bool allowLeaveFocusByTab() {
        return false;
    }

    void doAction(char[] s) {
        if (onKeyBinding)
            onKeyBinding(this, s);
    }

    override bool handleChildInput(InputEvent event) {
        //dirty hack to focus windows if you click into them
        if (event.isKeyEvent && event.keyEvent.isMouseButton())
            activate();
        //dragging/catching key shortcuts
        if (mDraging
            || (event.isKeyEvent && findBind(event.keyEvent) != ""))
        {
            deliverDirectEvent(event);
            //mask events from children
            return true;
        }
        return super.handleChildInput(event);
    }

    //treat all events as handled (?)
    override void onKeyEvent(KeyInfo key) {
        char[] bind = findBind(key);

        if (bind.length) {
            if (key.isDown())
                doAction(bind);
            return;
        }

        if (mDraging) {
            //stop draging by any further mouse-up event
            if (key.isMouseButton && !key.isPress && !key.isDown) {
                mDraging = false;
            }
            return;
        }

        //if a mouse click wasn't handled, start draging the window around
        //xxx mostly inactive (filtered out by allowInputForChild())
        if (key.code == Keycode.MOUSE_LEFT && !key.isPress && key.isDown) {
            mDraging = true;
        }
    }

    protected void onMouseMove(MouseInfo mouse) {
        if (mDraging) {
            if (mCanMove && !mFullScreen && mManager) {
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

    override void onDrawChildren(Canvas c) {
        super.onDrawChildren(c);

        //only for the shitty window-manager thing
        if (highlight) {
            c.drawFilledRect(Vector2i(0), size, Color(0.7,0.7,0.7,0.7));
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

    char[] toString() {
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
        bool mWindowSelecting;
        ModifierSet mSelectMods; //to determine if the modifiers were released

        //factories for parts; indexed by their names (but why?)
        DefPart[char[]] mPartFactory;

        class DefPart {
            char[] name;
            bool by_default;
            int priority;

            //fabricate whatever and add it to the window
            abstract void addTo(WindowWidget w);

            this(char[] name, ConfigNode node) {
                this.name = name;
                by_default = node.getBoolValue("create_by_default", false);
                priority = node.getIntValue("priority");
            }
        }

        class TitlePart : DefPart {
            this(char[] name, ConfigNode node) { super(name, node); }
            void addTo(WindowWidget w) {
                //isn't it funney?
                w.addTitlePart(name, priority, w.titleBar);
            }
        }

        class ButtonPart : DefPart {
            Texture img;
            char[] action;
            this(char[] name, ConfigNode node) {
                super(name, node);
                img = gGuiResources.get!(Surface)(node["image"]);
                action = node.getStringValue("action");
            }

            class Holder {
                WindowWidget w;
                void onButton(Button sender) {
                    w.doAction(action);
                }
            }

            void addTo(WindowWidget w) {
                auto b = new Button();
                b.allowFocus = false;
                b.image = img;
                b.styles.addClass("window-button");
                b.setLayout(WidgetLayout.Noexpand());
                auto h = new Holder; //could use std.bind too, I guess
                h.w = w;
                b.onClick = &h.onButton;
                w.addTitlePart(name, priority, b);
            }
        }
    }

    ///callback for "alt+tab"-style window selection (i.e. MS Windoes, IceWM)
    ///sel_end==true means the modifiers (i.e. alt) were finally released
    void delegate(bool sel_end) onSelectWindow;

    this() {
        setVirtualFrame(false); //wtf

        checkCover = true;

        mConfig = loadConfig("window");

        mKeysWindow = new KeyBindings();
        mKeysWindow.loadFrom(mConfig.getSubNode("window_bindings"));
        mKeysWM = new KeyBindings();
        mKeysWM.loadFrom(mConfig.getSubNode("wm_bindings"));

        foreach (ConfigNode node; mConfig.getSubNode("titleparts")) {
            auto name = node.name;
            auto type = node.getStringValue("type");
            //oh noes, double-factory pattern again... but a switch is fine too
            DefPart part;
            switch (type) {
                case "caption":
                    part = new TitlePart(name, node);
                    break;
                case "img_button":
                    part = new ButtonPart(name, node);
                    break;
                default:
                    //???
                    assert(false, "add error handling");
            }
            mPartFactory[name] = part;
        }
    }

    override bool doesDelegateFocusToChildren() {
        return true;
    }

    void addDefaultDecorations(WindowWidget wnd) {
        foreach (DefPart p; mPartFactory) {
            if (p.by_default)
                p.addTo(wnd);
        }
    }

    void addDecoration(WindowWidget wnd, char[] name) {
        mPartFactory[name].addTo(wnd);
    }

    void addWindow(WindowWidget wnd) {
        wnd.remove();
        wnd.mManager = this;
        wnd.bindings = mKeysWindow;
        mWindows ~= wnd;
        addChild(wnd);
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
            wnd.mManager = null;
        }
        super.removeChild(child);
        if (wnd)
            wnd.wasRemoved();
    }

    WindowWidget focusWindow() {
        foreach (w; mWindows) {
            if (w.subFocused())
                return w;
        }
        return null;
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

    private bool wsIsSet() {
        assert(mWindowSelecting);
        return gFramework.getModifierSetState(mSelectMods);
    }

    override bool handleChildInput(InputEvent event) {
        if (mWindowSelecting
            || (event.isKeyEvent && mKeysWM.findBinding(event.keyEvent)))
        {
            deliverDirectEvent(event);
            return true;
        }
        return super.handleChildInput(event);
    }

    protected override void onKeyEvent(KeyInfo info) {
        if (mWindowSelecting) {
            if (!wsIsSet()) {
                //modifiers were released => end of selection
                mWindowSelecting = false;
                if (onSelectWindow)
                    onSelectWindow(true);
            }
        }
        auto bnd = mKeysWM.findBinding(info);
        if (bnd.length == 0)
            return;
        if (info.isDown()) {
            if (bnd == "select_window") {
                mSelectMods = info.mods;
                mWindowSelecting = true;
                assert(wsIsSet()); //doesn't work if it doesn't hold true
                if (onSelectWindow)
                    onSelectWindow(false);
            }
        }
    }
}
