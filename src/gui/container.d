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

        if (o.greedyFocus())
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

        //if (o is mEventCaptured)
          //  childSetCapture(mEventCaptured, false);

        //copy... when a function is iterating through these arrays and calls
        //this function (through event handling), and we modify the array, and
        //then return to that function, it gets fucked up
        //but if these functions use foreach (copies the array descriptor), and
        //we copy the array memory, we're relatively safe *SIGH!*
        mWidgets = mWidgets.dup;
        mZWidgets = mZWidgets.dup;
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
        //if (child.mZOrder2 == mLastZOrder2)
            //return; //try to avoid redundant updates
        child.mZOrder2 = ++mLastZOrder2;
        mZWidgets = mZWidgets.dup;
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
            if (childCanHaveFocus(cur) &&
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

        if (childCanHaveFocus(child)) {
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
                log()("warning: !parent condition failed");
                return;
            }
            parent.findNextFocusOnKill(child);
            pollFocusState();
        } else {
            child.pollFocusState();
            Widget nfocus = findLastFocused();
            log()("focus for kill: %s", nfocus);
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
            if (childCanHaveFocus(cur) && cur.nextFocus()) {
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
        log()("%s: attempt to focus %s", this, go);
        assert(!go || go.parent is this);
        if (go is mFocus)
            return;

        if (mFocus) {
            //xxx from now on don't clear focus if go is not focusable
            if (go && !childCanHaveFocus(go)) {
                log()("don't unfocus %s on %s for %s", mFocus, this, go);
                return;
            }
            log()("remove local focus: %s from %s for %s", mFocus, this, go);
            auto tmp = mFocus;
            mFocus = null;
            tmp.pollFocusState();
        }
        mFocus = go;
        if (go && childCanHaveFocus(go)) {
            go.mFocusAge = ++mCurrentFocusAge;
            log()("set local focus: %s for %s", mFocus, this);
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

    override bool onTestMouse(Vector2i pos) {
        if (!super.onTestMouse(pos))
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

    //if an arbitrary child can have input of any kind, if not, the widget
    //(almost?) behaves as if it doesn't exist for the mouse/keyboard
    //also affects focus handling
    //call recheckChildInput() if the returned value changed for a Widget
    protected bool childCanHaveInput(Widget w) {
        assert(w.parent is this);
        return true;
    }

    protected void recheckChildInput(Widget w) {
        assert(w.parent is this);
        recheckChildFocus(w);
    }

    protected final bool childCanHaveFocus(Widget w) {
        assert(w.parent is this);
        return childCanHaveInput(w) && w.canHaveFocus();
    }

    override void doMouseEnterLeave(bool mouseIsInside) {
        //if it's inside, rely on mouse-event stuff
        if (mouseIsInside)
            return;
        foreach (o; mWidgets) {
            //if it can't have input, still deliver go-out events
            if (childCanHaveInput(o) || !mouseIsInside)
                o.doMouseEnterLeave(mouseIsInside);
        }
        super.doMouseEnterLeave(mouseIsInside);
    }

    //special function which enables containers to steal events from the
    //children in special situations - if this returns false, events are not
    //dispatched to the children, even if they could accept them
    //even if this returns true, the usual can-have-input checks are made
    protected bool allowInputForChild(Widget child, InputEvent event) {
        assert(child.parent is this);
        return true;
    }

    //return an event changed so that the child can handle it; currently
    //translates the mouse positions to the child's coordinate system
    //child must be a direct child of this
    InputEvent translateEvent(Widget child, InputEvent event) {
        assert(child.parent is this);
        debug if (event.isMouseEvent)
            assert(event.mousePos == event.mouseEvent.pos);
        event.mousePos = child.coordsFromParent(event.mousePos);
        if (event.isMouseEvent) {
            event.mouseEvent.pos = event.mousePos;
        }
        return event;
    }

    //find a child which wants/can take the input event
    //use the result of the function on this.dispatchInputEvent(), which
    //actually changes state
    override Widget findInputDispatchChild(InputEvent event)
    out (res) {
        assert(!res || res is this || res.parent is this);
    }
    body {
        Widget res;
        bool byMousePos;

        auto main = getTopLevel();
        if (!main) //normally shouldn't happen
            return null;
        //user capturing has priority over mouse capturing
        auto capture = main.captureUser ? main.captureUser : main.captureMouse;
        //find a child which leads to the capture'd Widget (captureTo)
        Widget captureTo;
        if (capture && capture !is this) {
            foreach (w; mWidgets) {
                if (capture.isTransitiveChildOf(w)) {
                    captureTo = w;
                    break;
                }
            }
        }

        debug if (captureTo)
            assert(capture);

        //probably set res, if w can/wants accept input
        void tryw(Widget w) {
            if (!w)
                return;
            assert(!w || w.parent is this);
            if (w && childCanHaveInput(w) && allowInputForChild(w, event)) {
                //xxx insert further checks
                res = w;
            }
        }

        if (event.isKeyEvent) {
            if (!event.keyEvent.isMouseButton) {
                //normal key: dispatch by focus
                //when captured, the captured one gets all events
                if (!capture) {
                    tryw(mFocus);
                } else {
                    tryw(captureTo);
                }
            } else {
                //mouse key: dispatch by mouse position
                byMousePos = true;
            }
        } else if (event.isMouseEvent) {
            byMousePos = true;
        } else {
            assert(false);
        }

        if (byMousePos) {
            assert(!res);

            //objects towards the end of the array are later drawn => _reverse
            //(in ambiguous cases, mouse should pick what's visible first)
            foreach_reverse (zchild; mZWidgets) {
                auto child = zchild.w;
                auto cevent = translateEvent(child, event);
                auto clientmp = cevent.mousePos;

                //happens rarely, e.g. when an input event handler called by us
                //removes a widget which has a lower zorder
                //xxx probably can't happen anymore with the new input dispatching??
                if (child.parent !is this)
                    continue;

                if (!childCanHaveInput(child))
                    continue;

                //mouse capture means capture gets all events
                //captureTo is a direct child widget which leas to capture
                bool captured = child is captureTo;
                bool capturing = capture !is null;

                if ((capturing && captured)
                    || (!capturing && child.testMouse(clientmp)))
                {
                    tryw(child);
                    //if child wasn't accepted, continue search
                    if (res)
                        break;
                }
            }
        }

        if (!res)
            res = this;

        return res;
    }

    protected override void dispatchInputEvent(InputEvent event) {
        Widget child = findInputDispatchChild(event);

        if (event.isMouseRelated()) {
            foreach (zchild; mWidgets) {
                if (zchild.parent !is this) {
                    assert(false);
                    continue;
                }

                if (zchild !is child) {
                    zchild.doMouseEnterLeave(false);
                }
            }
        }

        if (child is this) {
            super.dispatchInputEvent(event);
        } else {
            InputEvent cevent = translateEvent(child, event);
            child.doDispatchInputEvent(cevent);
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
    bool mouseEvents = true; //xxx silly hack

    override bool onTestMouse(Vector2i pos) {
        return mouseEvents ? super.onTestMouse(pos) : false;
    }

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
