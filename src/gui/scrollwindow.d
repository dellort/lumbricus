module gui.scrollwindow;

import gui.widget;
import gui.container;
import framework.framework;
import framework.event;
import utils.vector2;
import utils.rect2;
import utils.log;
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
///xxx: add a widget which shows scrollbars and which takes a "ScollClient" as
///  client; so ScrollArea would need to implement ScrollClient (or so)
class ScrollArea : SimpleContainer {
    private {
        Vector2i mOffset;
        Vector2i mScrollSize;

        //stuff for smooth scrolling
        bool mEnableSmoothScrolling;

        Vector2f mScrollDest, mScrollOffset;
        long mTimeLast;

        const cScrollStepMs = 10;
        const float K_SCROLL = 0.01f;
    }

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

    void setScroller(ScrollClient c) {
        mScroller = c;
        updateScrollSize();
    }

    final Vector2i getScrollSize() {
        return mScrollSize;
    }

    //xxx doesn't work with mScroller
    final Vector2i fromClientCoordsScroll(Vector2i p) {
        auto child = getBinChild();
        return child ? child.coordsToParent(p) : p;
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
            auto csize = child.layoutCachedContainerSizeRequest();
            auto msize = size;
            auto diff = csize - msize;
            //if it's too small, the child will be layouted using the
            //normal Widget layout stuff (on this axis)
            ssize.x = diff.x > 0 ? diff.x : 0;
            ssize.y = diff.y > 0 ? diff.y : 0;
        }

        mScrollSize.x = mEnableScroll[0] ? ssize.x : 0;
        mScrollSize.y = mEnableScroll[1] ? ssize.y : 0;

        //assert it's within the scrolling region (call setter...)
        offset = mOffset;
    }

    final public Vector2i clipOffset(Vector2i offs) {
        return Rect2i(-mScrollSize, Vector2i(0)).clip(offs);
    }

    //sigh?
    final public Vector2f clipOffset(Vector2f offs) {
        return Rect2f(-toVector2f(mScrollSize), Vector2f(0)).clip(offs);
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
    }

    ///calculate the offset that would center pos in the middle of this Widget
    ///(pos in the child's coordinates)
    Vector2i centeredOffset(Vector2i pos) {
        //xxx don't know if this is correct when using mScroller or so
        //aim: mOffset + pos == size/2
        return size/2 - pos;
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

    override protected void simulate(Time curTime, Time deltaT) {
        if (!mEnableSmoothScrolling)
            return;

        long curTimeMs = curTime.msecs;

        if ((mScrollDest-mScrollOffset).quad_length > 0.1f) {
            while (mTimeLast + cScrollStepMs < curTimeMs) {
                mScrollOffset +=
                    (mScrollDest - mScrollOffset)*K_SCROLL*cScrollStepMs;
                mTimeLast += cScrollStepMs;
            }
            offset = toVector2i(mScrollOffset);
        } else {
            mEnableSmoothScrolling = false;
        }
    }
}
