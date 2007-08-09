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
    private Vector2i mMinSize = {100, 0};

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
        needRelayout();
    }

    this() {
        mFill.borderWidth = 0;
    }

    Vector2i layoutSizeRequest() {
        return mMinSize;
    }

    override protected void onDraw(Canvas c) {
        auto s = widgetBounds();
        //padding so it doesn't look stupid when percent == 0
        int pad = border.cornerRadius + mFill.cornerRadius + spacing.x;
        s.p2.x = s.p1.x + pad + cast(int)((s.p2.x - s.p1.x - pad*2) * percent);
        drawBox(c, s, border);
        s.extendBorder(-spacing);
        drawBox(c, s, mFill);
    }
}
