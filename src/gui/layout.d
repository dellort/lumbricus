module gui.layout;
import gui.guiobject;
import gui.frame;
import utils.vector2;
import utils.rect2;
import utils.log;

///controlls position and size of GuiObjects within a GuiFrame
///make active by doing targetframe.addLayouter(this);
///maybe also should do animations (i.e. scrolling in or out gui elements)
class GuiLayouter {
    protected GuiFrame mFrame;
    protected GuiObject[] mObjects;

    //direct parent of all managed sub objects
    void frame(GuiFrame obj) {
        mFrame = obj;
        relayout();
    }

    protected void doAdd(GuiObject obj) {
        mObjects ~= obj;
        //hack to make creating guis simpler *g*
        if (!obj.parent && mFrame)
            obj.parent = mFrame;
        //needed?
        obj.needRelayout();
    }

    //object changed in any way
    protected abstract void doChange(GuiObject go);

    final void change(GuiObject go) {
        //allow deactivated objects
        //(xxx: when are these objects ever removed from the layouter?)
        if (!go.parent || !mFrame)
            return;
        assert(go.parent is mFrame);
        doChange(go);
        gDefaultLog("do change %s -> %s", go, go.bounds);
    }

    protected void doRelayout() {
        foreach (o; mObjects) {
            change(o);
        }
    }

    //size of frame changed
    void relayout() {
        gDefaultLog("relayout %s %s %s", this, mFrame, mObjects);
        doRelayout();
    }

    void kill() {
        mFrame.removeLayouter(this);
        mFrame = null;
    }
}

///make all client objects to cover the whole frame they're in
class GuiLayouterNull : GuiLayouter {
    void add(GuiObject obj) {
        doAdd(obj);
    }

    protected override void doChange(GuiObject go) {
        go.bounds = mFrame.bounds;
    }
}

enum Borders {
    Left, Top, Right, Bottom
}

///alignment; i.e. constant position from a specific border
class GuiLayouterAlign : GuiLayouter {
    private struct Layout {
        float[4] aligns;
        float[4] borders;
        float[4] sizes;
    }
    private Layout*[GuiObject] mLayouts;

    ///Make obj aligned to the borders of the managed frame.
    ///  aligns = for each border (Borders) give the position the border should
    ///           have within that axis; i.e. aligns[0]==0.2 means the upper
    ///           border of the object should be at 0.2*height+borders[0]
    ///  borders = index as in aligns; gives the constant spacing from border
    ///  sizes = multiplicated weith object's requested size and added to result
    void add(GuiObject obj, float[4] aligns, float[4] borders, float[4] sizes) {
        Layout* ly = new Layout;
        ly.aligns[] = aligns;
        ly.borders[] = borders;
        ly.sizes[] = sizes;
        mLayouts[obj] = ly;
        doAdd(obj);
    }
    ///assume the objects sizes itself, and align it on 2 borders
    ///  x = with -1, 0, +1 select top border, centered, or bottom border
    ///  y = same as x for right border, centered, or left border
    ///  borders = constant distance from these borders
    void add(GuiObject obj, int x, int y, Vector2i borders = Vector2i()) {
        float[4] a, b, s;

        void bla(int offs, int what, float pos) {
            if (what < 0) {
                //left/top
                a[offs] = 0; a[offs+2] = 0;
                b[offs] = pos; b[offs+2] = pos;
                s[offs] = 0.0f; s[offs+2] = 1.0f;
            } else if (what > 0) {
                //right/bottom
                a[offs] = 1.0f; a[offs+2] = 1.0f;
                b[offs] = -pos; b[offs+2] = -pos;
                s[offs] = -1.0f; s[offs+2] = 0.0f;
            } else {
                //centered (pos ignored)
                a[offs] = 0.5f; a[offs+2] = 0.5f;
                b[offs] = 0; b[offs+2] = 0;
                s[offs] = -0.5f; s[offs+2] = 0.5f;
            }
        }

        bla(0, x, borders.x);
        bla(1, y, borders.y);

        add(obj, a, b, s);
    }
    ///"r" gives coordinates between 0 to 1, which is scaled to the frame's size
    void add(GuiObject obj, Rect2f r) {
        add(obj, [r.p1.x, r.p1.y, r.p2.x, r.p2.y], [0f,0,0,0], [0f,0,0,0]);
    }

    protected override void doChange(GuiObject go) {
        Layout* ly = mLayouts[go];
        LayoutConstraints lc;
        go.getLayoutConstraints(lc);

        auto size = lc.minSize;
        auto psize = mFrame.size;
        float[2] sizes;
        sizes[0] = size.x; sizes[1] = size.y;
        float[2] borders;
        borders[0] = psize.x; borders[1] = psize.y;
        float[4] pos;
        for (int n = 0; n < 4; n++) {
            pos[n] =
                ly.aligns[n]*borders[n%2]+ly.borders[n]+ly.sizes[n]*sizes[n%2];
        }

        Rect2i p;
        p.p1.x = cast(int)pos[0];
        p.p1.y = cast(int)pos[1];
        p.p2.x = cast(int)pos[2];
        p.p2.y = cast(int)pos[3];
        //hm, should it?
        p.normalize(); //if negative size, reverse p1 and p2

        go.bounds = p;
    }
}

/// Group objects added to this horizontally or vertically in the order they
/// were added; also can fit the container frame to it.
class GuiLayouterRow : GuiLayouter {
    Vector2i spacing; //border around each object

    private int mDir;
    private bool mFitFrame;

    //fitframe = set size of the container accordingly
    //horiz = horizontal row if true, else group vertically
    this (bool fitframe, bool horiz) {
        assert(!fitframe, "so below");
        mDir = horiz ? 0 : 1;
        mFitFrame = fitframe;
    }

    void add(GuiObject o) {
        doAdd(o);
    }

    override protected void doChange(GuiObject go) {
        doRelayout();
    }

    override protected void doRelayout() {
        auto inv = 1 - mDir;
        //find size (to possibly size all items equally)
        Vector2i csize;
        foreach (o; mObjects) {
            LayoutConstraints lc;
            o.getLayoutConstraints(lc);
            Vector2i s = lc.minSize + spacing*2;
            if (s[inv] > csize[inv]) {
                csize[inv] = s[inv];
            }
            csize[mDir] = csize[mDir] + s[mDir];
        }
        if (mFitFrame) {
            //xxx need to set size of frame in a way that won't cause infinite
            //    recursion...
        }
        Vector2i cur;
        int fsize = mFrame.size[inv];
        foreach (o; mObjects) {
            LayoutConstraints lc;
            o.getLayoutConstraints(lc);
            auto minSize = lc.minSize;
            if (minSize[inv] < csize[inv])
                minSize[inv] = csize[inv];
            auto p = cur;
            p[mDir] = p[mDir] + spacing[mDir];
            Rect2i nb;
            nb.p1 = p;
            //center on inv-dir
            //xxx really center this just adds the spacing
            nb.p1[inv] = nb.p1[inv] + spacing[inv];
            nb.p2 = nb.p1 + minSize;
            o.bounds = nb;
            cur[mDir] = (cur + minSize + spacing*2)[mDir];
        }
    }
}
