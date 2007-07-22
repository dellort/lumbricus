module gui.container;

static import common.visual;
import framework.framework : Canvas;
import gui.widget;
import gui.gui;
import utils.array;
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

        //to send mouse-leave events
        Widget mLastMouseReceiver;

        Vector2i mInternalBorder;
    }

    common.visual.BoxProperties drawBoxStyle;
    bool drawBox = false;

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
            assert(parent !is null);
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

        return ok;
    }

    //doesn't set the global focus; do "go.focused = true;" for that
    package void localFocus(Widget go) {
        if (go is mFocus)
            return;

        if (mFocus) {
            gDefaultLog("remove local focus: %s from %s", mFocus, this);
            auto tmp = mFocus;
            mFocus = null;
            tmp.pollFocusState();
        }
        mFocus = go;
        if (go && go.canHaveFocus) {
            go.mFocusAge = ++mCurrentFocusAge;
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
        biggest += mInternalBorder*2;
        return biggest;
    }

    protected override void layoutSizeAllocation() {
        Rect2i b = widgetBounds();
        b.extendBorder(-mInternalBorder);
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
        if (!mouseIsInside && mLastMouseReceiver) {
            mLastMouseReceiver.doMouseEnterLeave(false);
            mLastMouseReceiver = null;
        }
    }

    override bool handleKeyEvent(KeyInfo info) {
        //first try to handle locally
        //the super.-method invokes the onKey*() functions
        if (super.handleKeyEvent(info))
            return true;
        //event wasn't handled, handle by child objects
        if (mFocus) {
            if (mFocus.handleKeyEvent(info))
                return true;
        }
        return false;
    }

    override bool handleMouseEvent(MouseInfo* mi, KeyInfo* ki) {
        //NOTE: mouse buttons (ki) don't have the mousepos; use the old one then

        Widget got_it;

        //first, check if the parent wants it; if it returns true, don't deliver
        //this event to the children
        if (!super.handleMouseEvent(mi, ki)) {

            //check if any children are hit by this
            //objects towards the end of the array are later drawn => _reverse
            foreach_reverse (zchild; mZWidgets) {
                auto child = zchild.w;
                auto clientmp = child.coordsFromParent(mousePos);
                if (child.testMouse(clientmp)) {
                    //huhuhu a hit! call its event handler
                    bool res;
                    //MouseInfo.pos should contain the translated mousepos
                    if (mi) {
                        MouseInfo mi2 = *mi;
                        mi2.pos = clientmp;
                        res = child.handleMouseEvent(&mi2, null);
                    } else {
                        res = child.handleMouseEvent(null, ki);
                    }
                    if (res) {
                        got_it = child;
                        break;
                    }
                }
            }
        }

        if (mLastMouseReceiver && (mLastMouseReceiver !is got_it)) {
            mLastMouseReceiver.doMouseEnterLeave(false);
        }

        mLastMouseReceiver = got_it;

        return got_it !is null;
    }

    // --- all the rest

    void internalBorder(Vector2i b) {
        mInternalBorder = b;
        needRelayout();
    }
    Vector2i internalBorder() {
        return mInternalBorder;
    }

    override void internalSimulate(Time curTime, Time deltaT) {
        foreach (obj; mWidgets) {
            obj.internalSimulate(curTime, deltaT);
        }
        super.internalSimulate(curTime, deltaT);
    }

    override protected void onDraw(Canvas c) {
        if (drawBox) {
            common.visual.drawBox(c, widgetBounds, drawBoxStyle);
        }
        foreach (obj; mZWidgets) {
            obj.w.doDraw(c);
        }
        super.onDraw(c);
    }
}

///Container with a public Container-interface
///Container introduces some public methods too, but only ones that need a
///valid object reference to child widgets
///xxx: maybe do it right, I didn't even catch all functions, but it makes
///     problems in widget.d/Widget
class PublicContainer : Container {
    void clear() {
        while (children.length > 0) {
            removeChild(children[0]);
        }
    }
}

///PublicContainer which supports simple layouting
///by coincidence only needs to add more accessors to the original Container
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
}
