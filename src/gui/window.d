module gui.window;

import common.common;
import common.visual;
import framework.event;
import framework.framework;
import gui.boxcontainer;
import gui.button;
import gui.container;
import gui.label;
import gui.tablecontainer;
import gui.widget;
import utils.array;
import utils.misc;
import utils.rect2;
import utils.vector2;

//only static properties
struct WindowProperties {
    char[] windowTitle = "<huhu, you forgot to set a title!>";
    bool canResize = true;   //disallow user to resize the window
    Color background = Color(1,1,1); //of the client part of the window
}

/// A window with proper window decorations and behaviour
class WindowWidget : Container {
    private {
        Widget mClient; //what's shown inside the window
        Label mTitleBar;

        char[] mTitle;
        BoxProperties mBackground;

        //"window manager"; supported to be null
        WindowFrame mManager;

        bool mFullScreen;
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
                return super.onKeyEvent(key);
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

    Rect2i windowBounds() {
        return containedBounds;
    }
    void windowBounds(Rect2i b) {
        mUserSize = b.size;
        needResize(true);
        position = b.p1;
    }

    /+ works, but not needed anymore
    //x, y as in Sizer.x/y; by: relative size change
    //return by how many actually moved
    private void resizeOn(int x, int y, Vector2i by) {
        Vector2i minsize = mLastMinSize;
        Rect2i bounds = windowBounds;
        auto spare = bounds.size - minsize; //x,y should be >= 0
        int[] s = [x, y];
        for (int n = 0; n < 2; n++) {
            if (s[n] < 0) {
                //so that spare-add >= 0
                int add = min(by[n], spare[n]); //don't make too small
                bounds.p1[n] = bounds.p1[n] + add;
            } else if (s[n] > 0) {
                int add = max(by[n], -spare[n]);
                bounds.p2[n] = bounds.p2[n] + add;
            }
        }
        windowBounds = bounds;
    }
    +/

    override Vector2i layoutSizeRequest() {
        mLastMinSize = super.layoutSizeRequest();
        //mUserSize is the window size as requested by the user
        //but don't make it smaller than the GUI code wants it
        return mLastMinSize.max(mUserSize);
    }

    override protected void layoutSizeAllocation() {
        super.layoutSizeAllocation();
    }

    WindowFrame manager() {
        return mManager;
    }

    this() {
        setVirtualFrame(false);

        loadBindings(globals.loadConfig("window"));

        recreateGui();

        WindowProperties p;
        properties = p; //to be consistent
    }

    //when that button in the titlebar is pressed
    //currently only showed if fullScreen is false, hmmm
    private void onToggleFullScreen(Button sender) {
        fullScreen = !fullScreen;
    }

    private void recreateGui() {
        clear();

        if (mFullScreen) {
            if (mClient) {
                mClient.remove();
                addChild(mClient);
            }
            needRelayout();
        } else {
            //add decorations etc.
            auto all = new TableContainer(3, 3);

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

            auto titlebar = new BoxContainer(true);

            mTitleBar = new Label();
            mTitleBar.drawBorder = false;
            mTitleBar.text = mTitle;
            titlebar.add(mTitleBar);

            auto maximize = new Button();
            maximize.text = "F";
            maximize.onClick = &onToggleFullScreen;
            titlebar.add(maximize, WidgetLayout.Noexpand);

            vbox.add(titlebar, WidgetLayout.Expand(true));

            if (mClient) {
                mClient.remove();
                vbox.add(mClient);
            } else {
                vbox.add(new Spacer());
            }

            all.add(vbox, 1, 1);

            addChild(all);
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

        if (mManager) {
            mManager.setFullScreen(mFullScreen ? this : null);
        }

        if (!set) {
            position = mFSSavedPos;
        }
    }

    Widget client() {
        return mClient;
    }
    void client(Widget w) {
        mClient = w;
        recreateGui();
    }

    WindowProperties properties() {
        WindowProperties res;
        res.windowTitle = mTitle;
        res.background = mBackground.back;
        res.canResize = mCanResize;
        return res;
    }
    void properties(WindowProperties props) {
        mTitleBar.text = mTitle = props.windowTitle;
        mBackground.back = props.background;
        mCanResize = props.canResize;
    }

    void activate() {
        //will also set it to front
        claimFocus();
    }

    override protected void onFocusChange() {
        super.onFocusChange();
        //a matter of taste
        mBackground.border = focused ? Color(0,0,1) : mBackground.border.init;
    }

    //treat all events as handled (?)
    override bool onKeyEvent(KeyInfo key) {
        char[] bind = findBind(key);

        //and if the mouse was clicked _anywhere_, make sure window is on top
        //but don't steal the click-event from the children
        if (key.isMouseButton())
            activate();

        if (bind == "toggle_fs") {
            if (key.isDown())
                fullScreen = !fullScreen;
            return true;
        }

        //let the children handle key events
        bool handled = super.onKeyEvent(key);

        //if a mouse click wasn't handled, start draging the window around
        if (!handled && key.isMouseButton && !key.isPress) {
            mDraging = key.isDown;
            captureSet(mDraging);
        }
        return true;
    }

    protected bool onMouseMove(MouseInfo mouse) {
        bool handled = super.onMouseMove(mouse);
        if (!handled && mDraging && !mFullScreen) {
            if (mManager) {
                mManager.setWindowPosition(this, containedBounds.p1+mouse.rel);
            }
        }
        //always return true => all events as handled
        return true;
    }

    override protected void onDraw(Canvas c) {
        //if fullscreen, the parent clears with this.background
        if (!mFullScreen) {
            common.visual.drawBox(c, widgetBounds, mBackground);
        }
        super.onDraw(c);
    }

    char[] toString() {
        return "["~super.toString~" '"~mTitle~"']";
    }
}

/// Special container for Windows; i.e can deal with "fullscreen" windows
/// efficiently (won't draw other windows then)
class WindowFrame : Container {
    private {
        WindowWidget mFullScreen; //non-null if in fullscreen mode
        WindowWidget[] mWindows;  //all windows
    }

    void addWindow(WindowWidget wnd) {
        wnd.remove();
        wnd.mManager = this;
        mWindows ~= wnd;
        if (!mFullScreen)
            addChild(wnd);
    }

    //hm, stupid, you must use this; wnd.remove() would silently fail
    void removeWindow(WindowWidget wnd) {
        if (mFullScreen is wnd) {
            setFullScreen(null);
        }
        arrayRemove(mWindows, wnd);
        wnd.mManager = null;
        wnd.remove();
    }

    //called by Window
    private void setFullScreen(WindowWidget wnd) {
        if (wnd is mFullScreen)
            return;

        auto was_focused = localFocus; //focus state should survive

        if (wnd) {
            mFullScreen = wnd;
            //for some stupid reasons, the following will relayouts us at least
            //for mWindows.length time (or 1 if it was fullscreen before)
            clear();
            addChild(mFullScreen);
            mFullScreen.fullScreen = true;
        } else {
            if (mFullScreen) {
                mFullScreen.fullScreen = false;
            }
            auto old = mFullScreen;
            mFullScreen = null;
            clear(); //possibly kill old fullscreen
            foreach (w; mWindows) {
                addChild(w);
            }
            //this is slightly stupid:
        }

        if (was_focused) {
            was_focused.claimFocus();
            //zorder gets completely messed up, and claimFocus refuses
            was_focused.toFront();
        }
    }

    void setWindowPosition(WindowWidget wnd, Vector2i pos) {
        wnd.layoutContainerAllocate(Rect2i(pos, pos + wnd.size));
    }

    protected override Vector2i layoutSizeRequest() {
        if (mFullScreen) {
            return mFullScreen.layoutCachedContainerSizeRequest();
        } else {
            return super.layoutSizeRequest();
        }
    }

    protected override void layoutSizeAllocation() {
        if (mFullScreen) {
            mFullScreen.layoutContainerAllocate(widgetBounds());
        } else {
            foreach (WindowWidget w; mWindows) {
                //maybe want to support invisible window sometime
                //so if a window isn't parented, it's invisible
                if (w.parent is this) {
                    auto s = w.layoutCachedContainerSizeRequest();
                    auto p = w.containedBounds.p1;
                    w.layoutContainerAllocate(Rect2i(p, p + s));
                }
            }
        }
    }

    override protected void onDraw(Canvas c) {
        if (mFullScreen) {
            //xxx: possibly unnecessary clearing when it really covers the whole
            //  screen; it should use getFramework.clearColor then, maybe
            c.drawFilledRect(Vector2i(0), size,
                mFullScreen.properties.background);
        }
        super.onDraw(c);
    }
}
