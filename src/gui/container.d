module gui.container;

static import common.visual;
import framework.framework : Canvas;
import gui.widget;
import gui.gui;
import utils.array;
import utils.configfile;
import utils.misc;
import utils.vector2;
import utils.rect2;
import utils.time;
import utils.log;

class Container : Widget {
    private {
        //helper
        struct ZWidget {
            Widget w;
            int opCmp(ZWidget* o) {
                if (w.mZOrder == o.w.mZOrder) {
                    return w.mZOrder2 - o.w.mZOrder2;
                }
                return w.mZOrder - o.w.mZOrder;
            }
            char[] toString() {
                return std.string.format("%s(%s,%s)", w, w.mZOrder, w.mZOrder2);
            }
        }

        Widget[] mWidgets;   //sorted by order of insertion
        ZWidget[] mZWidgets; //sorted as itself (mZChildren.sort)

        //local focus
        Widget mFocus;
        //only grows, wonder what happens if it overflows
        int mCurrentFocusAge;
        //frame is "transparent"
        bool mIsVirtualFrame = true;
        //only one element per child
        bool mIsBinFrame;
        //also grows only; used to do "soft" zorder
        int mLastZOrder2;

        Widget mEventCaptured;
    }

    common.visual.BoxProperties drawBoxStyle;
    bool drawBox = false;

    ///use Widget.doesCover
    protected bool checkCover = false;

    // --- insertion/deletion including zorder-stuff

    /// Add sub GUI element
    protected void addChild(Widget o) {
        if (o.parent !is null) {
            assert(false, "already added");
        }
        assert(arraySearch(mWidgets, o) < 0);

        o.mParent = this;
        mWidgets ~= o;
        mZWidgets ~= ZWidget(o);
        updateZOrder(o);

        onAddChild(o);

        if (o.greedyFocus && o.canHaveFocus)
            o.claimFocus();
        //just to be sure
        o.needRelayout();

        //gDefaultLog("added %s to %s", o, this);
    }

    /// Undo addChild()
    protected void removeChild(Widget o) {
        bool hadglobalfocus = o.focused;

        if (o.parent !is this) {
            assert(false, "was not child of this");
        }

        if (o is mEventCaptured)
            childSetCapture(mEventCaptured, false);

        arrayRemove(mWidgets, o);
        arrayRemove(mZWidgets, ZWidget(o));
        o.mParent = null;

        onRemoveChild(o);

        //gDefaultLog("removed %s from %s", o, this);

        if (o is mFocus) {
            mFocus = null;
            findNextFocusOnKill(o);
        } else {
            assert(!hadglobalfocus);
            //that's just kind and friendly?
            o.pollFocusState();
        }

        needRelayout();
    }

    //work around protection...
    package void doRemoveChild(Widget o) {
        removeChild(o);
    }
    package void doSetChildToFront(Widget o) {
        setChildToFront(o);
    }

    //called after child has been added/removed, and before relayouting etc.
    //is done -- might be very fragile
    protected void onAddChild(Widget c) {
    }
    protected void onRemoveChild(Widget c) {
    }

    private void updateZOrder(Widget child) {
        child.mZOrder2 = ++mLastZOrder2;
        mZWidgets.sort;
    }

    ///set this child to highest z-order possible for it
    ///also used from various places to update the child's zorder internally
    final protected void setChildToFront(Widget child) {
        //what concidence
        updateZOrder(child);
    }

    protected void setChildLayout(Widget child, WidgetLayout layout) {
        child.setLayout(layout);
        needRelayout();
    }

    /// "Virtual" frame: It just groups all its child object, but isn't visible
    /// itself, doesn't accept any events for itself (only child objects, but
    /// i.e. doesn't take focus or accept mouse events for itself), doesn't draw
    /// anything (except to show child objects),  but it does clipping
    protected void setVirtualFrame(bool v) {
        mIsVirtualFrame = v;
    }

    /// if true, allow only one child and enable getBinChild()
    protected void setBinContainer(bool b) {
        if (b) {
            assert(children.length <= 1);
        }
        mIsBinFrame = b;
    }

    protected Widget getBinChild() {
        assert(mIsBinFrame);
        assert(mWidgets.length <= 1);
        return mWidgets.length ? mWidgets[0] : null;
    }

    ///treat the return value as const
    protected Widget[] children() {
        return mWidgets;
    }

    // --- focus handling

    //in the case a Widget disclaimed focus, find the Widget which was focused
    //before; check Widget.mFocusAge to do this (the only reason why it exists)
    protected override Widget findLastFocused() {
        Widget winner = null;
        foreach (cur; mWidgets) {
            if (cur.canHaveFocus &&
                (!winner || (winner.mFocusAge < cur.mFocusAge)))
            {
                winner = cur;
            }
        }
        return winner ? winner : this;
    }

    //hack
    protected int getChildFocusAge(Widget w) {
        assert(w && w.parent is this);
        return w.mFocusAge;
    }

    //focus rules:
    // object becomes active => if greedy focus, set focus immediately
    // object becomes inactive => object which was focused before gets focus
    //    to do that, Widget.mFocusAge is used
    // tab => next focusable Widget in GUI is focused

    /// call when child.canHaveFocus changed
    protected void recheckChildFocus(Widget child) {
        assert(child !is null);
        assert(child.parent is this);

        if (child.canHaveFocus) {
            if (child.greedyFocus) {
                child.claimFocus();
            }
        } else {
            //maybe was killed, take focus
            if (child.focused) {
                //was even globally focused! special case.
                findNextFocusOnKill(child);
            }
        }
    }

    //fuck
    package void doRecheckChildFocus(Widget child) {
        recheckChildFocus(child);
    }

    private void findNextFocusOnKill(Widget child) {
        if (!isTopLevel) {
            //this can't have happened because this is _only_ called if the
            //child was globally focused, and this again can only happen if the
            //child has the toplevel-container as indirect parent
            //xxx sometimes fails for unknown reaons *g*
            //    assert(parent !is null);
            if (!parent) {
                registerLog("GUI")("warning: !parent condition failed");
                return;
            }
            parent.findNextFocusOnKill(child);
            pollFocusState();
        } else {
            child.pollFocusState();
            Widget nfocus = findLastFocused();
            if (nfocus)
                nfocus.claimFocus();
        }
    }

    override bool nextFocus() {
        //the container itself also should be focusable
        //so possibly set focus already
        bool ok = super.nextFocus();

        //try to next-focus the children

        int index = arraySearch(mWidgets, mFocus);
        if (index < 0) {
            assert(mFocus is null); //else not-added Widget would be focused
            index = 0; //start with first
        }

        while (index < mWidgets.length) {
            auto cur = mWidgets[index];
            //try to find a new focus and if so, be happy
            if (cur.nextFocus()) {
                return true;
            }
            index++;
        }

        //reset, so it starts cycling again if we're focused next time
        if (!ok)
            localFocus = null;

        return ok;
    }

    //doesn't set the global focus; do "go.focused = true;" for that
    package void localFocus(Widget go) {
        if (go is mFocus)
            return;

        if (mFocus) {
            version (LogFocus)
                gDefaultLog("remove local focus: %s from %s", mFocus, this);
            auto tmp = mFocus;
            mFocus = null;
            tmp.pollFocusState();
        }
        mFocus = go;
        if (go && go.canHaveFocus) {
            go.mFocusAge = ++mCurrentFocusAge;
            version (LogFocus)
                gDefaultLog("set local focus: %s for %s", mFocus, this);
            go.pollFocusState();
        }
    }

    package Widget localFocus() {
        return mFocus;
    }

    override void onFocusChange() {
        super.onFocusChange();
        //propagate focus change downwards...
        foreach (o; mWidgets) {
            o.pollFocusState();
        }
    }

    /// For "virtual frames", the Container itself is not focusable, but
    /// children are.
    override bool canHaveFocus() {
        if (mIsVirtualFrame) {
            //xxx maybe a bit expensive; cache it?
            foreach (o; mWidgets) {
                if (o.canHaveFocus)
                    return true;
            }
            return false;
        }
        return true;
    }

    /// Frames should always respect focus-greedyness of children, and so does
    /// the default implementation.
    override bool greedyFocus() {
        foreach (o; mWidgets) {
            if (o.greedyFocus)
                return true;
        }
        return false;
    }

    // --- layouting

    protected override Vector2i layoutSizeRequest() {
        //report the biggest
        Vector2i biggest;
        foreach (w; children) {
            biggest = biggest.max(w.layoutCachedContainerSizeRequest());
        }
        return biggest;
    }

    protected override void layoutSizeAllocation() {
        Rect2i b = widgetBounds();
        foreach (w; children) {
            w.layoutContainerAllocate(b);
        }
    }

    protected void requestedRelayout(Widget child) {
        assert(child.parent is this);
        //propagate upwards, indirectly
        needRelayout();
    }

    //I hate D
    package void doRequestedRelayout(Widget child) {
        requestedRelayout(child);
    }

    // --- input handling

    override bool testMouse(Vector2i pos) {
        if (!super.testMouse(pos))
            return false;

        //virtual frame => only if a child was hit
        if (mIsVirtualFrame) {
            foreach (o; mWidgets) {
                if (o.testMouse(o.coordsFromParent(pos)))
                    return true;
            }
            return false;
        }

        return true;
    }

    override protected void onMouseEnterLeave(bool mouseIsInside) {
        //if it's inside, rely on mouse-event stuff
        if (mouseIsInside)
            return;
        foreach (o; mWidgets) {
            o.doMouseEnterLeave(mouseIsInside);
        }
    }

    override protected bool onKeyEvent(KeyInfo key) {
        //first try to handle locally
        //the super.-method also invokes the old onKey*() functions
        if (super.onKeyEvent(key))
            return true;

        bool ok;

        //event wasn't handled, handle by child objects
        if (!key.isMouseButton) {
            //normal key: dispatch by focus
            //when captured, the captured one gets all events
            if (!mEventCaptured) {
                ok = mFocus && mFocus.handleKeyEvent(key);
            } else {
                ok = mEventCaptured.handleKeyEvent(key);
            }
        } else {
            //mouse key: dispatch by mouse position
            ok = checkChildrenMouseEvent(mousePos,
                (Widget child) {
                    //attention: local return within a delegate
                    return child.handleKeyEvent(key);
                }
            );
        }

        return ok;
    }

    override protected bool onMouseMove(MouseInfo mouse) {
        //first handle locally (currently the super-method is empty, hmm)
        if (super.onMouseMove(mouse))
            return true;

        return checkChildrenMouseEvent(mouse.pos,
            (Widget child) {
                //mouse-struct needs to be translated to the child
                mouse.pos = child.mousePos; //xxx: unkosher?
                return child.handleMouseEvent(mouse);
            }
        );
    }

    //enumerate all children which would handle the event for mousepos "mouse"
    //the check_child-delegate is supposed to actually call the child's event-
    //handler; it returns whether to child did handle the event
    protected bool checkChildrenMouseEvent(Vector2i mouse,
        bool delegate(Widget child) check_child)
    {
        Widget got_it;

        //check if any children are hit by this
        //objects towards the end of the array are later drawn => _reverse
        foreach_reverse (zchild; mZWidgets) {
            auto child = zchild.w;
            auto clientmp = child.coordsFromParent(mouse);

            //mouse capture means mEventCaptured gets all events
            bool captured = child is mEventCaptured;
            bool capturing = mEventCaptured !is null;

            if ((capturing && captured)
                || (!capturing && child.testMouse(clientmp)))
            {
                child.updateMousePos(clientmp);
                child.doMouseEnterLeave(true);
                //(try to) deliver event, but only if noone got it yet
                if (!got_it && check_child(child))
                    got_it = child;
            } else {
                child.doMouseEnterLeave(false);
            }
        }

        return got_it !is null;
    }

    //you should use Widget.captureEnable/captureDisable/captureSet
    //returns if action could be performed
    bool childSetCapture(Widget child, bool set) {
        assert(child.parent is this);
        if (set) {
            if (mEventCaptured)
                return false;
            mEventCaptured = child;
            //propagate upwards
            bool res = captureSet(true);
            if (!res)
                mEventCaptured = null;
            return res;
        } else {
            if (mEventCaptured !is child)
                return false;
            mEventCaptured = null;
            return captureSet(false);
        }
    }

    // --- all the rest

    override void internalSimulate() {
        foreach (obj; mWidgets) {
            obj.internalSimulate();
        }
        super.internalSimulate();
    }

    override protected void onDraw(Canvas c) {
        if (drawBox) {
            common.visual.drawBox(c, widgetBounds, drawBoxStyle);
        }
        if (!checkCover) {
            foreach (obj; mZWidgets) {
                obj.w.doDraw(c);
            }
        } else {
            //special hack-like thing to speed up drawing *shrug*
            Widget last_cover;
            foreach (obj; mZWidgets) {
                if (obj.w.doesCover)
                    last_cover = obj.w;
            }
            bool draw = !last_cover;
            foreach (obj; mZWidgets) {
                draw |= obj.w is last_cover;
                if (draw)
                    obj.w.doDraw(c);
            }
        }
        super.onDraw(c);
    }

    protected void clear() {
        while (children.length > 0) {
            removeChild(children[0]);
        }
    }

    //only intended for debugging; not to subvert any protection
    //rather use this.children() (which is protected)
    void enumChildren(void delegate(Widget w) callback) {
        foreach (w; children.dup) {
            callback(w);
        }
    }
}

///Container with a public Container-interface
///Container introduces some public methods too, but only ones that need a
///valid object reference to child widgets
///xxx: maybe do it right, I didn't even catch all functions, but it makes
///     problems in widget.d/Widget
class PublicContainer : Container {
    void clear() {
        super.clear();
    }
}

///PublicContainer which supports simple layouting
///by coincidence only needs to add more accessors to the original Container
///also supports loading of children widgets using loadFrom()
class SimpleContainer : PublicContainer {
    /// Add an element to the GUI, which gets automatically cleaned up later.
    void add(Widget obj) {
        addChild(obj);
    }

    /// Add and set layout.
    void add(Widget obj, WidgetLayout layout) {
        setChildLayout(obj, layout);
        addChild(obj);
    }

    override void loadFrom(GuiLoader loader) {
        auto node = loader.node;

        auto children = node.findNode("children");
        if (children) {
            clear();
            foreach (ConfigItem sub; children) {
                add(loader.loadWidget(sub));
            }
        }

        //hmpf
        drawBox = node.getBoolValue("draw_box", drawBox);

        super.loadFrom(loader);
    }

    /+
    moved to widget.d because of "circular initialization dependency" :(
    static this() {
        WidgetFactory.register!(typeof(this))("simplecontainer");
    }+/
}
