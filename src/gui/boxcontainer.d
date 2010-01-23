module gui.boxcontainer;
import gui.container;
import gui.widget;
import utils.configfile;
import utils.vector2;
import utils.rect2;
import utils.misc;

///contains boxes in a row
class BoxContainer : SimpleContainer {
    private {
        int mDir; //0==X, 1==Y
        bool mHomogeneous;
        //spacing _between_ boxes
        int mCellSpacing;

        //temporary between layoutSizeRequest() and allocation
        Vector2i mLastMinSize;
        int mExpandableCount;
        int mAllSpacing;
    }

    //needed for gui.loader only
    this() {
        this(false);
    }

    this(bool horiz, bool homogeneous = false, int cellspacing = 0) {
        mDir = horiz ? 0 : 1;
        mHomogeneous = homogeneous;
        mCellSpacing = cellspacing;
    }

    protected override Vector2i layoutSizeRequest() {
        //report the biggest
        Vector2i rsize;
        int count;
        int inv = 1-mDir;
        mExpandableCount = 0;
        foreach (Widget w; children) {
            Vector2i s = w.layoutCachedContainerSizeRequest();
            if (mHomogeneous) {
                rsize[mDir] = max(rsize[mDir], s[mDir]);
            } else {
                rsize[mDir] = rsize[mDir] + s[mDir];
            }
            //other direction: simple the maximum
            rsize[inv] = max(rsize[inv], s[inv]);
            count++;
            if (mHomogeneous || w.layout.expand[mDir])
                mExpandableCount++;
        }

        if (mHomogeneous) {
            rsize[mDir] = rsize[mDir] * count;
        }

        //cell spacing is between boxes and never at the start or end
        mAllSpacing = (count ? (count-1) * mCellSpacing : 0);
        rsize[mDir] = rsize[mDir] + mAllSpacing;

        mLastMinSize = rsize;

        return rsize;
    }

    protected override void layoutSizeAllocation() {
        int inv = 1-mDir;
        Vector2i asize = size;
        if (!mHomogeneous) {
            int extra = (asize - mLastMinSize)[mDir];
            if (extra < 0)
                extra = 0; //don't really deal with shrinking
            //distribute extra space over all cells that are expandable
            int distextra = mExpandableCount ? extra / mExpandableCount : 0;
            Rect2i cur;
            cur.p2[inv] = asize[inv];
            int p = 0;
            foreach (Widget w; children) {
                auto s = w.layoutCachedContainerSizeRequest();
                int add = s[mDir];
                if (w.layout.expand[mDir])
                    add += distextra;
                cur.p1[mDir] = p;
                cur.p2[mDir] = p + add;
                w.layoutContainerAllocate(cur);
                p += add;
                p += mCellSpacing;
            }
        } else {
            //hm, is it really that dumb?
            int add = mExpandableCount ?
                (asize[mDir] - mAllSpacing) / mExpandableCount : 0;
            Rect2i cur;
            cur.p2[inv] = asize[inv];
            int p = 0;
            foreach (Widget w; children) {
                cur.p1[mDir] = p;
                cur.p2[mDir] = p + add;
                w.layoutContainerAllocate(cur);
                p += add;
                p += mCellSpacing;
            }
        }
    }

    void loadFrom(GuiLoader loader) {
        auto node = loader.node;
        clear();
        mHomogeneous = node.getBoolValue("homogeneous", mHomogeneous);
        mCellSpacing = node.getIntValue("cell_spacing", mCellSpacing);
        mDir = node["direction"] == "x" ? 0 : 1; //other possible choice is "y"
        //reload children; order in list decides layout
        foreach (ConfigNode child; node.getSubNode("cells")) {
            add(loader.loadWidget(child));
        }
        super.loadFrom(loader);
    }

    static this() {
        WidgetFactory.register!(typeof(this))("boxcontainer");
    }
}

class HBoxContainer : BoxContainer {
    this(bool homogeneous = false, int cellspacing = 0) {
        super(true, homogeneous, cellspacing);
    }

    static this() {
        WidgetFactory.register!(typeof(this))("hbox");
    }
}

class VBoxContainer : BoxContainer {
    this(bool homogeneous = false, int cellspacing = 0) {
        super(false, homogeneous, cellspacing);
    }

    static this() {
        WidgetFactory.register!(typeof(this))("vbox");
    }
}
