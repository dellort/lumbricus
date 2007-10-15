module gui.progress;

import common.common;
import common.visual;
import framework.framework;
import gui.container;
import gui.label;
import gui.tablecontainer;
import gui.widget;
import utils.time;
import utils.misc;

///like a progress bar
class Foobar : Widget {
    BoxProperties border;
    Vector2i spacing = {2, 2};
    private BoxProperties mFill;
    private Vector2i mMinSize = {0, 0};
    private int mWidth = 0;

    ///between 0 and 1
    float percent = 1.0f;

    void fill(Color c) {
        mFill.back = c;
    }

    Vector2i minSize() {
        return mMinSize;
    }
    void minSize(Vector2i s) {
        mMinSize = s;
        needResize(true);
    }

    this() {
        mFill.borderWidth = 0;
    }

    Vector2i layoutSizeRequest() {
        int x = max(mMinSize.x, xpadding*2);
        x += mWidth;
        return Vector2i(x, mMinSize.y);
    }

    //border on the left and right
    private int xpadding() {
        return border.cornerRadius + mFill.cornerRadius + spacing.x;
    }

    //set width of the bar; in pixels; when width=0, the minimal size is showed
    void width(int w) {
        mWidth = max(0, w);
        needResize(true);
    }

    override protected void onDraw(Canvas c) {
        auto s = widgetBounds();
        //padding so it doesn't look stupid when percent == 0
        int pad = xpadding();
        s.p2.x = s.p1.x + pad + cast(int)((s.p2.x - s.p1.x - pad*2) * percent);
        drawBox(c, s, border);
        s.extendBorder(-spacing);
        drawBox(c, s, mFill);
    }
}