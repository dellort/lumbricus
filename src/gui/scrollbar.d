module gui.scrollbar;

import common.common;
import common.visual;
import framework.restypes.bitmap;
import framework.resources;
import gui.button;
import gui.container;
import gui.widget;
import framework.framework;
import framework.event;
import utils.vector2;
import utils.rect2;
import utils.log;
import utils.misc;
import utils.time;

class ScrollBar : Container {
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

        //constraints for drag thing
        const int cMinSliderSize = 8;
        const int cDefSliderSize = 16;

        const char[][] cAddImg = ["scroll_right","scroll_down"];
        const char[][] cSubImg = ["scroll_left","scroll_up"];

        //that thing which sits between the two buttons
        //xxx: drag and drop code partially copied from window.d
        class Bar : Widget {
            BoxProperties mBorder;
            bool drag_active;
            Vector2i drag_start;

            protected void onDraw(Canvas c) {
                if (size.x >= cMinSliderSize && size.y >= cMinSliderSize)
                common.visual.drawBox(c, widgetBounds, mBorder);
            }

            override protected Vector2i layoutSizeRequest() {
                return Vector2i(0);
            }

            override protected void onMouseMove(MouseInfo mouse) {
                if (drag_active) {
                    //get position within the container
                    assert(parent && this.outer.parent);
                    auto pos = coordsToParent(mouse.pos);
                    pos -= drag_start; //click offset

                    curValue = cast(int)((pos[mDir] - mBarArea.p1[mDir]
                        + 0.5*mScaleFactor) / mScaleFactor) + mMinValue;
                }
            }

            override protected void onKeyEvent(KeyInfo key) {
                if (!key.isPress && key.code == Keycode.MOUSE_LEFT) {
                    drag_active = key.isDown;
                    drag_start = mousePos;
                }
            }
        }
    }

    void delegate(ScrollBar sender) onValueChange;

    ///horizontal if horiz = true, else vertical
    this(bool horiz) {
        mDir = horiz ? 0 : 1;
        //xxx: replace text by images
        mAdd = new Button();
        mAdd.image = globals.guiResources.get!(Surface)(cAddImg[mDir]);
        //mAdd.text = "A";
        mAdd.onClick = &onAddSub;
        mAdd.autoRepeat = true;
        addChild(mAdd);
        mSub = new Button();
        mSub.image = globals.guiResources.get!(Surface)(cSubImg[mDir]);
        //mSub.text = "B";
        mSub.onClick = &onAddSub;
        mSub.autoRepeat = true;
        addChild(mSub);
        mBar = new Bar();
        addChild(mBar);
    }

    private void onAddSub(Button sender) {
        if (sender is mAdd) {
            curValue = curValue+mSmallChange;
        } else if (sender is mSub) {
            curValue = curValue-mSmallChange;
        }
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
            }
        }
    }

    //prevent Container from returning false if no child is hit
    override bool onTestMouse(Vector2i pos) {
        return true;
    }

    override protected Vector2i layoutSizeRequest() {
        auto r1 = mSub.requestSize;
        auto r2 = mAdd.requestSize;
        Vector2i res;
        auto mindir = max(r1[mDir], r2[mDir])*2;
        //leave at least mindir/4 space for the bar, as a hopefully-ok guess
        //(removed, will hide slider if no space)
        res[mDir] = mindir/* + mindir/4*/;
        res[!mDir] = max(r1[!mDir], r2[!mDir]);
        return res;
    }

    override protected void layoutSizeAllocation() {
        auto sz = size;

        Vector2i buttons = mSub.requestSize.max(mAdd.requestSize);
        buttons[!mDir] = sz[!mDir];
        auto bsize = Rect2i(Vector2i(0), buttons);

        mSub.layoutContainerAllocate(bsize);
        Vector2i r;
        r[mDir] = sz[mDir] - mAdd.requestSize[mDir];
        mAdd.layoutContainerAllocate(bsize + r);
        mBarArea = widgetBounds;
        //xxx hack against error in x direction
        //(requestSize seems to be off by 1, but I don't dare changing the
        //layout code)
        //xxx again: seems to work with images
        mBarArea.p1[mDir] = mSub.requestSize[mDir]/* + (mDir==0?1:0)*/;
        mBarArea.p2[mDir] = r[mDir];

        adjustBar();
    }

    //reset position of mBar according to mCurValue/mMaxValue
    private void adjustBar() {
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
        if (barh < cMinSliderSize)
            barh = cMinSliderSize;
        if (barh > areah)
            barh = areah;
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
            if (onValueChange)
                onValueChange(this);
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
}
