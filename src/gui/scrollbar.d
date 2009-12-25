module gui.scrollbar;

import gui.button;
import gui.container;
import gui.global;
import gui.widget;
import framework.framework;
import framework.event;
import utils.vector2;
import utils.rect2;
import utils.log;
import utils.misc;
import utils.time;

class ScrollBar : Widget {
    private {
        int mDir; //0=in x direction, 1=y
        Button mSub, mAdd;
        Bar mBar;
        Rect2i mBarArea;

        int mCurValue;
        int mMinValue, mMaxValue, mPageSize;
        //increment/decrement for button click (small) and area click (large)
        int mSmallChange = 1;
        int mLargeChange = 1;
        //scale factor = pixels / value
        double mScaleFactor;

        //amount of pixels the bar can be moved
        int mBarFreeSpace;

        bool mSizesValid;

        //constraints for drag thing
        const int cMinSliderSize = 8;
        const int cDefSliderSize = 16;

        const char[][] cAddImg = ["scroll_right","scroll_down"];
        const char[][] cSubImg = ["scroll_left","scroll_up"];
    }

    //that thing which sits between the two buttons
    private class Bar : Widget {
        bool drag_active;
        Vector2i drag_start, drag_displace;

        this() {
            super();
            styles.addClass("w-scrollbar-floater");
        }

        override protected Vector2i layoutSizeRequest() {
            return Vector2i(0);
        }

        override protected void onMouseMove(MouseInfo mouse) {
            if (drag_active) {
                auto rel = coordsToParent(mouse.pos) - drag_displace;
                auto pos = drag_start + rel;

                //xxx is this even correct?
                curValue = cast(int)((pos[mDir] - mBarArea.p1[mDir]
                    + 0.5*mScaleFactor) / mScaleFactor) + mMinValue;
                raiseValueChange();
            }
        }

        override protected void onKeyEvent(KeyInfo key) {
            if (!key.isPress && key.code == Keycode.MOUSE_LEFT) {
                drag_active = key.isDown;
                drag_start = containerPosition();
                drag_displace = coordsToParent(mousePos);
            }
        }
    }

    void delegate(ScrollBar sender) onValueChange;

    this() {
        //eh
        this(false);
    }

    ///horizontal if horiz = true, else vertical
    this(bool horiz) {
        mDir = horiz ? 0 : 1;
        //xxx: let the button be load completely by the styles system (huh)
        mAdd = new Button();
        mAdd.image = gGuiResources.get!(Surface)(cAddImg[mDir]);
        mAdd.onClick = &onAddSub;
        mAdd.autoRepeat = true;
        addChild(mAdd);
        mSub = new Button();
        mSub.image = gGuiResources.get!(Surface)(cSubImg[mDir]);
        mSub.onClick = &onAddSub;
        mSub.autoRepeat = true;
        addChild(mSub);
        mBar = new Bar();
        addChild(mBar);

        foreach (w; [mAdd, mSub])
            w.styles.addClass("scrollbar-button");
    }

    //the buttons etc. can't be focused
    //the ScrollBar widget itself is focusable
    override bool allowSubFocus() {
        return false;
    }

    private void onAddSub(Button sender) {
        if (sender is mAdd) {
            curValue = curValue+mSmallChange;
        } else if (sender is mSub) {
            curValue = curValue-mSmallChange;
        }
        raiseValueChange();
    }

    override protected void onKeyEvent(KeyInfo ki) {
        //nothing was hit -> free area of scrollbar, between the bar and the
        //two buttons

        auto at = mousePos;
        if (ki.code == Keycode.MOUSE_LEFT && mBarArea.isInside(at)) {
            if (ki.isDown) {
                //xxx: would need some kind of auto repeat too
                //also, this looks ugly
                auto bar = mBar.containedBounds;
                int dir = (at[mDir] > ((bar.p1 + bar.p2)/2)[mDir]) ? +1 : -1;
                //multiply dir with the per-click increment (fixed to 1 now)
                curValue = curValue + dir*mLargeChange;
                raiseValueChange();
            }
        }
    }

    override protected Vector2i layoutSizeRequest() {
        Vector2i[3] stuff;
        stuff[0] = mSub.requestSize;
        stuff[1] = mAdd.requestSize;
        stuff[2] = mBar.requestSize;
        Vector2i res;
        foreach (s; stuff) {
            res[mDir] = res[mDir] + s[mDir];
            res[!mDir] = max(res[!mDir], s[!mDir]);
        }
        return res;
    }

    override protected void layoutSizeAllocation() {
        auto sa = mAdd.requestSize;
        auto sb = mSub.requestSize;

        assert(sa[!mDir] <= size[!mDir]);
        assert(sb[!mDir] <= size[!mDir]);

        sa[!mDir] = size[!mDir];
        sb[!mDir] = size[!mDir];

        mSub.layoutContainerAllocate(Rect2i(Vector2i(0), sb));
        mAdd.layoutContainerAllocate(Rect2i(size - sa, size));

        //rectangle between the two buttons mAdd and mSub
        mBarArea = widgetBounds;
        mBarArea.p1[mDir] = mSub.containerBounds.p2[mDir];
        mBarArea.p2[mDir] = mAdd.containerBounds.p1[mDir];

        assert(mBarArea.size[mDir] >= mBar.requestSize[mDir]);

        adjustBar();
    }

    void raiseValueChange() {
        if (onValueChange)
            onValueChange(this);
    }

    //reset position of mBar according to mCurValue/mMaxValue
    private void adjustBar() {
        //NOTE: there's a problem with ScrollWindow and switching themes:
        //  ScrollWindow calls adjustBar() (by setting curValue) when resizing,
        //  but at that time, this ScrollBar isn't resized yet; but when the
        //  theme changed, mBar.requestSize will return a value different from
        //  the last this.layoutSizeAllocation() call. Thus, all the sizes are
        //  inconsistent
        //=> don't rely on the sizes, lol. adjustBar() will be called with the
        //  correct values later

        //the range of values set during scrolling
        //when mPageSize!=0, subtract size of one (last) page
        int diff = max(mMaxValue - mMinValue - mPageSize + (mPageSize?1:0),0);
        int areah = mBarArea.size[mDir];
        int barh = cDefSliderSize;
        if (diff == 0) //no scrolling in this case
            barh = areah;
        else if (mPageSize != 0)
            //using full client size here instead of diff
            barh = (mPageSize*areah)/(mMaxValue - mMinValue + 1);
        barh = max(barh, cMinSliderSize);
        if (barh > areah)
            barh = areah;
        barh = max(barh, mBar.requestSize[mDir]); //possibly borders etc.
        mBarFreeSpace = areah - barh;
        Vector2i sz = size;
        sz[mDir] = barh;
        //pixel offset of bar inside mBarArea
        int pos;
        mScaleFactor = diff ? cast(double)mBarFreeSpace/diff : 0;
        if (diff > 0)
            //using mScaleFactor is not precise enough (strange)
            pos = cast(int)(((mCurValue-mMinValue)*mBarFreeSpace)/diff);
        Vector2i start = mBarArea.p1;
        start[mDir] = start[mDir] + pos;
        mBar.layoutContainerAllocate(Rect2i(start, start+sz));
    }

    ///current scrollbar position, normally goes from minValue to maxValue
    ///different if using page mode, see pageSize
    int curValue() {
        return mCurValue;
    }
    void curValue(int v) {
        v = clampRangeC(v, mMinValue,
            max(mMinValue, mMaxValue - mPageSize + (mPageSize?1:0)));
        if (v != mCurValue) {
            mCurValue = v;
            adjustBar();
        }
    }

    ///minimum value that can be reached by scrolling
    int minValue() {
        return mMinValue;
    }
    void minValue(int v) {
        mMinValue = v;  //max(v,0);
        if (mMaxValue < mMinValue)
            mMaxValue = mMinValue;
        //hmmmm
        curValue = curValue;
        pageSize = pageSize;
    }

    ///maximum value for scrollbar
    ///different meaning if pageSize!=0, see below
    int maxValue() {
        return mMaxValue;
    }
    void maxValue(int v) {
        mMaxValue = v;  //max(v,0);
        if (mMinValue > mMaxValue)
            mMinValue = mMaxValue;
        //hmmmm
        curValue = curValue;
        pageSize = pageSize;
    }

    //increment/decrement for button click
    int smallChange() {
        return mSmallChange;
    }
    void smallChange(int v) {
        mSmallChange = max(v, 1);
    }

    //increment/decrement for empty area click
    int largeChange() {
        return mLargeChange;
    }
    void largeChange(int v) {
        mLargeChange = max(v, 1);
    }

    ///size of scrolling window, same unit as curValue
    ///set to 0 to disable page mode
    ///when set !=0, maxValue is not the maximum value but the index
    ///of the last visible item
    ///Example:
    ///  6 lines of text, so minValue = 0, maxValue = 5
    ///  -> with pageSize==5 scrolling would be last possible
    ///     and curValue would reach 0 and 1
    int pageSize() {
        return mPageSize;
    }
    void pageSize(int ps) {
        mPageSize = max(ps,0);
        if (mPageSize > 0)
            largeChange = mPageSize;
        adjustBar();
    }

    static this() {
        WidgetFactory.register!(typeof(this))("scrollbar");
    }
}
