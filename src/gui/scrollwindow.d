module gui.scrollwindow;

import common.visual;
import gui.button;
import gui.container;
import gui.scrollbar;
import gui.tablecontainer;
import gui.widget;
import framework.framework;
import framework.event;
import utils.vector2;
import utils.rect2;
import utils.log;
import utils.misc;
import utils.time;

/// The child for ScrollArea can implement this; then scrolling can be owner
/// defined; else the ScrollArea will scroll it as Widget.
interface ScrollClient {
    //Get the maximal scroll value
    Vector2i getScrollSize();
    //Set the scroll position (i.e. actually scroll)
    //guaranteed to be between 0..getScrollSize for each component
    void setScrollPositions(Vector2i pos);
}

/// This frame always sizes its child to its requested size, and enables
/// scrolling within it.
class ScrollArea : SimpleContainer {
    private {
        Vector2i mOffset;
        Vector2i mScrollSize;
        Vector2i mClientSize;

        //stuff for smooth scrolling
        bool mEnableSmoothScrolling;

        Vector2f mScrollDest, mScrollOffset;
        long mTimeLast;

        const cScrollStepMs = 10;
        const float K_SCROLL = 0.01f;
    }

    //changes to scroll size or scrollability
    void delegate(ScrollArea sender) onStateChange;
    //changes to the scroll position
    void delegate(ScrollArea sender) onPositionChange;

    protected {
        ScrollClient mScroller; //maybe null, even if child available
        //[x, y], true if allow scrolling if it's "required"
        bool[2] mEnableScroll = [true, true];
    }

    this() {
        setBinContainer(true);
    }

    override protected void onAddChild(Widget c) {
        //optional ScrollClient interface
        mScroller = cast(ScrollClient)c;
    }
    override protected void onRemoveChild(Widget c) {
        mScroller = null;
    }

    void setEnableScroll(bool[2] enable) {
        mEnableScroll[] = enable;
        needRelayout();
    }
    void getEnableScroll(bool[2] enable) {
        enable[] = mEnableScroll;
    }

    void setScroller(ScrollClient c) {
        mScroller = c;
        updateScrollSize();
    }

    final Vector2i getScrollSize() {
        return mScrollSize;
    }

    final Vector2i clientSize() {
        return mClientSize;
    }

    //same as child.coordsToParent, but uses current scroll destination instead
    //of actual position
    //xxx doesn't work with mScroller
    final Vector2i fromClientCoordsScroll(Vector2i p) {
        auto child = getBinChild();
        return child ? p + toVector2i(mScrollDest) : p;
    }

    override protected Vector2i layoutSizeRequest() {
        auto r = Vector2i(0);

        auto child = getBinChild();
        if (child) {
            r = child.layoutCachedContainerSizeRequest();
        }

        if (mScroller) {
            //hm, just leave it as it is
        } else {
            //expand to child's size if it doesn't want to scroll
            r.x = mEnableScroll[0] ? 0 : r.x;
            r.y = mEnableScroll[1] ? 0 : r.y;
        }

        return r;
    }
    override protected void layoutSizeAllocation() {
        auto child = getBinChild();
        if (child) {
            Vector2i csize = child.layoutCachedContainerSizeRequest;
            if (!mScroller) {
                //as in layoutSizeRequest()
                csize.x = mEnableScroll[0] ? csize.x : size.x;
                csize.y = mEnableScroll[1] ? csize.y : size.y;
            }
            child.layoutContainerAllocate(Rect2i(Vector2i(0), csize));
        }
        updateScrollSize();
    }

    //recalculate mScrollSize and maybe adjust mOffset
    public void updateScrollSize() {
        auto child = getBinChild();

        Vector2i ssize;

        if (mScroller) {
            ssize = mScroller.getScrollSize();
        } else if (child) {
            mClientSize = child.layoutCachedContainerSizeRequest();
            auto msize = size;
            auto diff = mClientSize - msize;
            //if it's too small, the child will be layouted using the
            //normal Widget layout stuff (on this axis)
            ssize.x = diff.x > 0 ? diff.x : 0;
            ssize.y = diff.y > 0 ? diff.y : 0;
        }

        mScrollSize.x = mEnableScroll[0] ? ssize.x : 0;
        mScrollSize.y = mEnableScroll[1] ? ssize.y : 0;

        //assert it's within the scrolling region (call setter...)
        offset = mOffset;

        if (onStateChange)
            onStateChange(this);
    }

    final public Vector2i clipOffset(Vector2i offs) {
        return Rect2i(-mScrollSize, Vector2i(0)).clip(offs);
    }

    //sigh?
    final public Vector2f clipOffset(Vector2f offs) {
        //xxx hack against float rounding error of offs
        //(when scrolling to right border)
        return Rect2f(-toVector2f(mScrollSize) - Vector2f(.99f,.99f),
            Vector2f(0)).clip(offs);
    }

    Vector2i offset() {
        return mOffset;
    }
    void offset(Vector2i offs) {
        mOffset = clipOffset(offs);
        auto child = getBinChild();
        if (mScroller) {
            mScroller.setScrollPositions(mOffset);
        } else if (child) {
            child.adjustPosition(mOffset);
        }
        if (onPositionChange)
            onPositionChange(this);
    }

    ///calculate the offset that would center pos in the middle of this Widget
    ///(pos in the child's coordinates)
    Vector2i centeredOffset(Vector2i pos) {
        //xxx don't know if this is correct when using mScroller or so
        //aim: mOffset + pos == size/2
        return size/2 - pos;
    }

    void scrollDelta(Vector2i d) {
        offset = mOffset - d;
    }

    // --- (optional) smooth scrolling (works completely in top of the rest)

    ///Stop all active scrolling and stay at the currently visible position
    public void stopSmoothScrolling() {
        mEnableSmoothScrolling = false;
    }

    ///smoothly make offs to new offset
    public void scrollToSmooth(Vector2i offs) {
        stopSmoothScrolling();
        scrollDeltaSmooth(-offs);
    }

    public void scrollDeltaSmooth(Vector2i d) {
        if (!mEnableSmoothScrolling) {
            mEnableSmoothScrolling = true;
            mScrollDest = toVector2f(offset);
            mScrollOffset = mScrollDest;
            //xxx: what exactly is the GUIs timesource?
            mTimeLast = timeCurrentTime.msecs();
        }
        mScrollDest = clipOffset(mScrollDest - toVector2f(d));
    }

    override protected void simulate() {
        if (!mEnableSmoothScrolling)
            return;

        long curTimeMs = timeCurrentTime.msecs;

        if ((mScrollDest-mScrollOffset).quad_length > 0.1f) {
            while (mTimeLast + cScrollStepMs < curTimeMs) {
                mScrollOffset +=
                    (mScrollDest - mScrollOffset)*K_SCROLL*cScrollStepMs;
                mTimeLast += cScrollStepMs;
            }
            offset = toVector2i(mScrollOffset-Vector2f(.5f));
        } else {
            mEnableSmoothScrolling = false;
        }
    }

    override void loadFrom(GuiLoader loader) {
        auto node = loader.node;

        bool[2] enable = mEnableScroll;
        enable[0] = node.getBoolValue("enable_scroll_x", enable[0]);
        enable[1] = node.getBoolValue("enable_scroll_y", enable[1]);
        setEnableScroll(enable);

        //will load a child, if available
        super.loadFrom(loader);
    }

    static this() {
        WidgetFactory.register!(typeof(this))("scrollarea");
    }
}

/// Combines a ScrollArea and 0-2 ScrollBars
/// (currently provides access to a ScrollArea directly, hmmm)
//xxx: there's no technical reason why this is derived from a Container, instead
//  of deriving from TableContainer or so, but it seemed unclean
class ScrollWindow : Container {
    private {
        ScrollArea mArea;
        ScrollBar[2] mBars;
        TableContainer mLayout;
        //used to block recursive change notifications (!= 0 means updating)
        int mUpdating;
    }

    /// Use this to set scoll client and properties
    ScrollArea area() {
        return mArea;
    }

    this() {
        mArea = new ScrollArea();
        recreateGui();
    }

    /// Init with "child" as child for the ScrollArea, and do setEnableScroll
    /// with "enable"
    this(Widget child, bool[2] enable = [true, true]) {
        this();
        area.setEnableScroll(enable);
        area.addChild(child);
    }

    //callbacks must be left to this object
    void setScrollArea(ScrollArea arr) {
        destroyGui();
        mArea = arr;
        recreateGui();
    }

    private void destroyGui() {
        //especially remove callbacks; before they are even fired on removal
        foreach (ScrollBar b; mBars) {
            if (b) {
                b.onValueChange = null;
            }
        }
        mBars[] = mBars.init;
        mLayout = null;
        mArea.onPositionChange = null;
        mArea.onStateChange = null;
        clear();
        mArea.remove();
    }

    private void recreateGui() {
        //recreate only if necessary
        //this prevents an infinite loop, triggered by recreating the GUI,
        //which makes the ScrollArea trigger onStateChange, which calls us (this
        //function) again... argh
        //xxx: horrible implementation, make better

        bool[2] scr;
        Vector2i sizes;
        if (mArea) {
            mArea.getEnableScroll(scr);
            sizes = mArea.getScrollSize();
        }
        //sizes as set
        Vector2i setsizes;
        if (mBars[0] && scr)
            setsizes[0] = mBars[0].maxValue;
        if (mBars[1] && scr)
            setsizes[1] = mBars[1].maxValue;

        //if GUI is existing, check if anything that must be changed below is
        //different
        if (mLayout && !!mBars[0] == scr[0] && !!mBars[1] == scr[1])
        {
            if (sizes != setsizes) {
                //only the sizes changed; handle that without triggering
                //relayouting *sigh*
                if (mBars[0]) {
                    mBars[0].maxValue = mArea.clientSize[0]-1;
                    mBars[0].pageSize = mArea.size[0];
                }
                if (mBars[1]) {
                    mBars[1].maxValue = mArea.clientSize[1]-1;
                    mBars[1].pageSize = mArea.size[1];
                }
            }
            return;
        }

        destroyGui();

        if (!mArea)
            return;

        try {
            mUpdating++;

            mArea.onPositionChange = &onDoScroll;
            mArea.onStateChange = &onScrollChange;
            mLayout = new TableContainer(scr[1]?2:1, scr[0]?2:1);
            mLayout.add(mArea, 0, 0);
            for (int n = 0; n < 2; n++) {
                if (scr[n]) {
                    auto bar = new ScrollBar(!n);
                    mBars[n] = bar;
                    mLayout.add(bar, n?1:0, n?0:1, WidgetLayout.Expand(!n));
                    bar.onValueChange = &onScrollbar;
                    bar.maxValue = mArea.clientSize[n]-1;
                    bar.pageSize = mArea.size[n];
                    bar.curValue = -mArea.offset[n];
                }
            }

            addChild(mLayout);
        } finally {
            mUpdating--;
        }
    }

    private void onScrollbar(ScrollBar sender) {
        if (mUpdating)
            return;

        Vector2i offset = mArea.offset;
        if (sender is mBars[0]) {
            offset[0] = -sender.curValue;
        } else if (sender is mBars[1]) {
            offset[1] = -sender.curValue;
        }
        try {
            mUpdating++;
            mArea.offset = offset;
        } finally {
            mUpdating--;
        }
    }

    //its onPositionChange
    private void onDoScroll(ScrollArea scroller) {
        if (mUpdating)
            return;

        try {
            mUpdating++;
            if (mBars[0])
                mBars[0].curValue = -scroller.offset[0];
            if (mBars[1])
                mBars[1].curValue = -scroller.offset[1];
        } finally {
            mUpdating--;
        }
    }

    //its onStateChange
    private void onScrollChange(ScrollArea scroller) {
        recreateGui();
    }

    void loadFrom(GuiLoader loader) {
        auto node = loader.node;

        //possibly load a child, which must be a ScrollArea (or a subtype of it)
        auto child = node.findNode("area");
        if (child) {
            auto childw = loader.loadWidget(child);
            auto arr = cast(ScrollArea)childw;
            if (!arr)
                throw new Exception("whatever");
            setScrollArea(arr);
        }

        super.loadFrom(loader);
    }

    static this() {
        WidgetFactory.register!(typeof(this))("scrollwindow");
    }
}
