module gui.progress;

import framework.drawing;
import gui.container;
import gui.label;
import gui.renderbox;
import gui.tablecontainer;
import gui.widget;
import utils.time;
import utils.misc;

///like a progress bar
class Foobar : Widget {
    BoxProperties border;
    Vector2i spacing = {2, 2};
    private Color mFill;

    ///between 0 and 1
    float percent = 1.0f;

    void fill(Color c) {
        mFill = c;
    }

    this() {
        setVirtualFrame();
    }

    Vector2i layoutSizeRequest() {
        return Vector2i(xpadding*2);
    }

    //border on the left and right
    private int xpadding() {
        //two boxes, the outside and the inside ones
        //return border.cornerRadius*2 + spacing.x;
        return border.cornerRadius; //effective spacing: /2
    }

    override protected void onDraw(Canvas c) {
        auto s = widgetBounds();
        //padding so it doesn't look stupid when percent == 0
        int pad = xpadding();
        s.p2.x = s.p1.x + pad + cast(int)((s.p2.x - s.p1.x - pad*2) * percent);
        drawBox(c, s, border);
        s.extendBorder(-spacing);
        BoxProperties fill = border;
        fill.back = mFill;
        fill.borderWidth = 0;
        fill.cornerRadius = fill.cornerRadius-1; //whatever
        drawBox(c, s, fill);
    }
}
