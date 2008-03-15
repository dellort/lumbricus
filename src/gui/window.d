module gui.window;

import common.common;
import common.visual;
import framework.resources;
import framework.restypes.bitmap;
import framework.event;
import framework.framework;
import gui.boxcontainer;
import gui.button;
import gui.container;
import gui.label;
import gui.tablecontainer;
import gui.widget;
import utils.array;
import utils.configfile;
import utils.misc;
import utils.rect2;
import utils.vector2;

import str = std.string;

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
    Color background = Color(1,1,1); //of the client part of the window
    WindowZOrder zorder; //static zorder
}

/// A window with proper window decorations and behaviour
class WindowWidget : Container {
    private {
        Widget mClient; //what's shown inside the window
        Label mTitleBar;

        Widget mClientWidget;//what's really in (!is mClient if mClient is null)
        BoxContainer mForClient; //where client is, non-fullscreen mode
        Widget mWindowDecoration; //window frame etc. in non-fullscreen mode

        BoxContainer mTitleContainer; //titlebar + the buttons
        TitlePart[] mTitleParts; //kept sorted by .sort

        BoxProperties mBackground;

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

            override protected bool onMouseMove(MouseInfo mouse) {
                if (drag_active && mCanResize) {
                    //get position within the window's parent
                    assert(parent && this.outer.parent);
                    auto pos = this.outer.coordsToParent(
                        coordsToParent(mouse.pos));

                    //new window rect
                    auto bounds = this.outer.windowBounds;
                    auto spare = bounds.size - mLastMinSize;
                    int[] s = [x, y];
                    for (int n = 0; n < 2; n++) {
                        if (s[n] < 0) {
                            auto npos = pos[n] - drag_start[n];
                            //clip so that window doesn't move if it becomes
                            //too small (when sizing on the left/top borders)
                            bounds.p1[n] =
                                min(npos, bounds.p2[n] - mLastMinSize[n]);
                        } else if (s[n] > 0) {
                            //no "clipping" required
                            bounds.p2[n] = pos[n] + (size[n] - drag_start[n]);
                        }
                    }
                    this.outer.windowBounds = bounds;
                    return true;
                }
                return false;
            }

            override protected bool onKeyEvent(KeyInfo key) {
                if (!key.isPress && key.isMouseButton) {
                    drag_active = key.isDown;
                    drag_start = mousePos;
                    captureSet(drag_active);
                }
                return key.isMouseButton || super.onKeyEvent(key);
            }

            Vector2i layoutSizeRequest() {
                return Vector2i(cCornerSize);
            }

            this(int a_x, int a_y) {
                x = a_x; y = a_y;
                //sizers fill the whole border on the sides
                WidgetLayout lay;
                lay.expand[0] = (a_x == 0);
                lay.expand[1] = (a_y == 0);
                setLayout(lay);
            }

            /+override protected void onDraw(Canvas c) {
                c.drawFilledRect(Vector2i(0),size,Color(1,0,0));
            }+/
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

    Rect2i windowBounds() {
        return containedBounds;
    }
    void windowBounds(Rect2i b) {
        mUserSize = b.size;
        needResize(true);
        position = b.p1;
    }

    ///usersize to current minsize (in case usersize is smaller)
    void acceptSize(bool ignore_if_fullscreen = true) {
        if (ignore_if_fullscreen && mFullScreen)
            return;
        mUserSize = mUserSize.max(mLastMinSize);
        //actually not needed, make spotting errors easier
        needResize(true);
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

    this() {
        setVirtualFrame(false);

        //add decorations etc.
        auto all = new TableContainer(3, 3);
        mWindowDecoration = all;

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

        auto vbox = new BoxContainer(false, false, 5);

        mTitleContainer = new BoxContainer(true);
        auto tmp = new SimpleContainer();
        tmp.drawBox = true;
        tmp.add(mTitleContainer, WidgetLayout.Border(Vector2i(3, 1)));
        vbox.add(tmp, WidgetLayout.Expand(true));

        mForClient = vbox;

        all.add(vbox, 1, 1);

        recreateGui();

        mTitleBar = new Label();
        mTitleBar.drawBorder = false;
        mTitleBar.font = gFramework.getFont("window_title");

        WindowProperties p;
        properties = p; //to be consistent
    }

    //when that button in the titlebar is pressed
    //currently only showed if fullScreen is false, hmmm
    private void onToggleFullScreen(Button sender) {
        fullScreen = !fullScreen;
    }

    private void recreateGui() {
        if (mClient) {
            mClient.remove(); //just to be safe
        }

        //whatever there was... kill it
        if (mClientWidget) {
            mClientWidget.remove();
            mClientWidget = null;
        }

        if (mFullScreen || !mHasDecorations) {
            clear();
            if (mClient) {
                addChild(mClient);
            }
        } else {
            mClientWidget = mClient;
            if (!mClientWidget) {
                mClientWidget = new Spacer(); //placeholder
            }

            mForClient.add(mClientWidget);

            if (mWindowDecoration.parent !is this) {
                clear();
                addChild(mWindowDecoration);
            }
        }
    }

    void position(Vector2i pos) {
        if (mManager) {
            mManager.setWindowPosition(this, pos);
        }
    }
    Vector2i position() {
        return containedBounds.p1;
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
        res.background = mBackground.back;
        res.canResize = mCanResize;
        res.zorder = cast(WindowZOrder)zorder;
        return res;
    }
    void properties(WindowProperties props) {
        mTitleBar.text = props.windowTitle;
        mBackground.back = props.background;
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
        //will also set it to front
        claimFocus();
    }

    override protected void onFocusChange() {
        super.onFocusChange();
        //a matter of taste
        mBackground.border = focused ? Color(0,0,1) : mBackground.border.init;

        if (!focused && onFocusLost)
            onFocusLost(this);
    }

    override bool greedyFocus() {
        return true;
    }

    void doAction(char[] s) {
        if (onKeyBinding)
            onKeyBinding(this, s);
    }

    //treat all events as handled (?)
    override bool onKeyEvent(KeyInfo key) {
        char[] bind = findBind(key);

        //and if the mouse was clicked _anywhere_, make sure window is on top
        //but don't steal the click-event from the children
        if (key.isMouseButton())
            activate();

        if (bind.length) {
            if (key.isDown())
                doAction(bind);
            return true;
        }

        if (mDraging) {
            //stop draging by any further mouse-up event
            if (key.isMouseButton && !key.isPress && !key.isDown) {
                mDraging = false;
                captureDisable();
            }
            //mask events from children while dragging
            return true;
        }

        //let the children handle key events
        bool handled = super.onKeyEvent(key);

        //if a mouse click wasn't handled, start draging the window around
        if (!handled && key.isMouseButton && !key.isPress && key.isDown) {
            if (captureEnable()) {
                //if capture couldn't be set, maybe another capture is active
                //play around with TestFrame3 in test.d to see if it works
                mDraging = true;
            }
        }

        return true;
    }

    protected bool onMouseMove(MouseInfo mouse) {
        if (mDraging) {
            if (mCanMove && !mFullScreen && mManager) {
                mManager.setWindowPosition(this, containedBounds.p1+mouse.rel);
            }
        } else {
            super.onMouseMove(mouse);
        }
        //always return true => all events as handled
        return true;
    }

    override protected void onDraw(Canvas c) {
        //if fullscreen, the parent clears with this.background
        if (!mFullScreen && mHasDecorations) {
            common.visual.drawBox(c, widgetBounds, mBackground);
        } else {
            //xxx: possibly unnecessary clearing when it really covers the whole
            //  screen; it should use getFramework.clearColor then, maybe
            if (mHasDecorations && (!mClient || !mClient.doesCover))
                c.drawFilledRect(Vector2i(0), size, properties.background);
        }
        super.onDraw(c);

        if (highlight) {
            c.drawFilledRect(Vector2i(0), size, Color(0.7,0.7,0.7,0.7));
        }
    }

    override bool doesCover() {
        return mHasDecorations && mFullScreen;
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
                img = globals.guiResources.get!(Surface)(node["image"]);
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
                b.image = img;
                b.drawBorder = false;
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

        mConfig = gFramework.loadConfig("window");

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
        //code duplication with Container.findLastFocused
        WindowWidget winner;
        foreach (c; children()) {
            auto cur = cast(WindowWidget)c;
            if (cur && (!winner
                || getChildFocusAge(cur) > getChildFocusAge(winner)))
            {
                winner = cur;
            }
        }
        return winner;
    }

    void setWindowPosition(WindowWidget wnd, Vector2i pos) {
        wnd.layoutContainerAllocate(Rect2i(pos, pos + wnd.size));
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
                    auto p = w.containedBounds.p1;
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

    protected override bool onKeyEvent(KeyInfo info) {
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
            return super.onKeyEvent(info);
        if (info.isDown()) {
            if (bnd == "select_window") {
                mSelectMods = info.mods;
                mWindowSelecting = true;
                assert(wsIsSet()); //doesn't work if it doesn't hold true
                if (onSelectWindow)
                    onSelectWindow(false);
            }
        }
        return true;
    }
}
