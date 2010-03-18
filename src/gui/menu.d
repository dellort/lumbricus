module gui.menu;

import gui.widget;
import utils.misc;
import utils.rect2;
import utils.vector2;

//helper to enable nested menu invocation etc.
//class MenuStack : Widget {
//}

//list of MenuEntries
class Menu : Widget {
}

class MenuEntry {
}

//light-weight layouter
//see box model graphic:
//  http://doc.trolltech.com/4.3/stylesheet-customizing.html
class LayoutItem {
    int margin = 0, border = 0, padding = 0;
    Vector2i content;
    Rect2i map_content;
    Rect2i map_frame;

    //recalculate map_* members
    //rc.size is expected to be at least paddedSize()
    //it depends from the layouter whether extra space is used or not
    void map(Rect2i rc) {
        map_frame = rc;
        auto bordersum = Vector2i(margin + border + padding);
        map_content = map_frame;
        map_content.p1 += bordersum;
        map_content.p2 -= bordersum;
    }

    //recalc content, update margin, border, padding
    //note that you don't need to "recalc" sub items; it's the user's
    //  responsibility to update these (xxx: may be a bad idea, but on the other
    //  hand, the current GUI would do this itself anyway)
    void recalc() {
    }

    //requested minimum size of the frame
    final Vector2i paddedSize() {
        return content + Vector2i(margin+border+padding)*2;
    }
}

class LayoutBox : LayoutItem {
    LayoutItem[] items;
    int dir; //0=x, 1=y; e.g. 0 = horizontal layout
    int spacing = 0; //pixels between items

    override void map(Rect2i rc) {
        super.map(rc);
        Vector2i size = map_content.size;
        Vector2i p1 = map_content.p1;
        foreach (i; items) {
            auto cs = i.paddedSize();
            Rect2i cl = Rect2i.Span(p1, cs);
            i.map(cl);
            //advance to next item
            p1[dir] = p1[dir] + cs[dir] + (i !is items[$-1] ? spacing : 0);
        }
    }

    override void recalc() {
        content = Vector2i(0);
        foreach (i; items) {
            auto cs = i.paddedSize();
            content[dir] = content[dir] + cs[dir] + spacing;
            content[!dir] = max(content[!dir], cs[!dir]);
        }
        super.recalc();
    }
}

//align or center a child layouter
class LayoutAlign : LayoutItem {
    LayoutItem item;
    // -1: upper/left border, 0: center, +1: lower/right border
    Vector2f alignf = Vector2f(0, 0);
    //whether the full size should be filled
    //bool[2] expand = [false, false];

    override void map(Rect2i rc) {
        super.map(rc);
        if (!item)
            return;
        auto cs = item.paddedSize();
        auto avail = map_content.size;
        auto p = toVector2i(toVector2f(avail-cs) ^ ((alignf+Vector2f(1))/2.0));
        item.map(Rect2i.Span(map_content.p1 + p, cs));
    }

    override void recalc() {
        content = item ? item.paddedSize() : Vector2i(0);
        super.recalc();
    }
}
