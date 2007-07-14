module gui.tablecontainer;
import gui.container;
import gui.widget;
import utils.vector2;
import utils.rect2;
import utils.misc;

//like BoxContainer, but two dimensional
//the width of a row is taken from the maximum width of all other cells in the
//same column; same reverse for the height of them
//only 0 or 1 widgets per cell; cells without widgets have request size 0 and
//are not expanded
//no cell spanning
class TableContainer : PublicContainer {
    private {
        int mW, mH;
        bool[2] mHomogeneous;
        //organized as [x][y]
        PerWidget[][] mCells;
        //spacing _between_ cells (per direction)
        Vector2i mCellSpacing;

        //temporary between layoutSizeRequest() and allocation
        int[2] mExpandableCount;
        Vector2i mAllSpacing;
        bool[] mExpandX;
        bool[] mExpandY;
        int[] mMinWidths;  //minimal requested widths (for each cell)
        int[] mMinHeights; //minimal heights
        //temporary for allocation (just here for memory managment)
        //these are one element longer than the size in that direction, to
        //catch the last border
        int[] mAllocX;
        int[] mAllocY;
    }

    this(int a_w, int a_h, Vector2i cellspacing = Vector2i(),
        bool[2] homogeneous = [false, false])
    {
        mCells.length = a_w;
        foreach (inout r; mCells) {
            r.length = a_h;
        }

        mW = a_w; mH = a_h;

        mMinWidths.length = mW;
        mExpandX.length = mW;
        mAllocX.length = mW + 1;

        mMinHeights.length = mH;
        mExpandY.length = mH;
        mAllocY.length = mH + 1;

        mHomogeneous[] = homogeneous;
        mCellSpacing = cellspacing;
    }

    void add(Widget w, int x, int y, WidgetLayout layout = WidgetLayout()) {
        //check bounds, no overwriting of cells
        assert(mCells[x][y] is null);
        auto pw = addChild(w);
        mCells[x][y] = pw;
        setChildLayout(w, layout);
    }

    override protected void removeWidget(PerWidget w) {
        loop: foreach (col; mCells) {
            foreach (inout c; col) {
                if (c is w) {
                    c = null;
                    break loop;
                }
            }
        }
        super.removeWidget(w);
    }

    protected Vector2i layoutSizeRequest() {
        //if homogeneous, always expand all cells, else look into the loop below
        for (int x = 0; x < mW; x++) {
            mMinWidths[x] = 0;
            mExpandX[x] = mHomogeneous[0];
        }
        for (int y = 0; y < mH; y++) {
            mMinHeights[y] = 0;
            mExpandY[y] = mHomogeneous[1];
        }

        //help for homogeneous layout
        int allMinX, allMinY;

        //go over each col and row, update sizes progressively
        for (int x = 0; x < mW; x++) {
            for (int y = 0; y < mH; y++) {
                auto cur = mCells[x][y];
                bool[2] expand;
                Vector2i s;
                if (cur) {
                    expand[] = cur.layout.expand;
                    s = layoutDoRequestChild(cur);
                }
                mMinWidths[x] = max(mMinWidths[x], s.x);
                mMinHeights[y] = max(mMinHeights[y], s.y);
                allMinX = max(allMinX, mMinWidths[x]);
                allMinY = max(allMinY, mMinHeights[y]);
                //if one item in the row wants to expand, make all expanded
                mExpandX[x] |= expand[0];
                mExpandY[y] |= expand[1];
            }
        }

        //homogenize (could be implemented more efficiently)
        if (mHomogeneous[0]) {
            foreach (inout w; mMinWidths) {
                w = allMinX;
            }
        }
        if (mHomogeneous[1]) {
            foreach (inout h; mMinHeights) {
                h = allMinY;
            }
        }

        //summed up
        Vector2i rsize;

        for (int x = 0; x < mW; x++) {
            auto w = mMinWidths[x];
            rsize.x += w;
            mExpandableCount[0] += mExpandX[x] ? 1 : 0;
        }

        for (int y = 0; y < mH; y++) {
            auto h = mMinHeights[y];
            rsize.y += h;
            mExpandableCount[1] += mExpandY[y] ? 1 : 0;
        }

        //spacing only between cells, so n-1 in total
        mAllSpacing.x = max(0, (mW-1) * mCellSpacing.x);
        mAllSpacing.y = max(0, (mH-1) * mCellSpacing.y);

        rsize += mAllSpacing;

        return rsize;
    }

    protected override void layoutSizeAllocation() {
        Vector2i asize = size;

        //first calculate allocations...

        Vector2i extra = asize - lastLayoutRequestSize();
        //distribute extra space accross all expanding cells
        //the 0-case occurs when not expanding at all, but there's extra space
        //be right-top aligned then
        extra.x = mExpandableCount[0] ? extra.x/mExpandableCount[0] : 0;
        extra.y = mExpandableCount[1] ? extra.y/mExpandableCount[1] : 0;

        int cur;
        for (int x = 0; x < mW; x++) {
            int add = mMinWidths[x] + (mExpandX[x] ? extra.x : 0);
            mAllocX[x] = cur;
            cur += add + mCellSpacing.x;
        }
        mAllocX[$-1] = cur; //goes beyond asize by cellspacing.x, but see below

        cur = 0;
        for (int y = 0; y < mH; y++) {
            int add = mMinHeights[y] + (mExpandY[y] ? extra.y : 0);
            mAllocY[y] = cur;
            cur += add + mCellSpacing.y;
        }
        mAllocY[$-1] = cur;

        //and then assign them.
        Rect2i box;
        for (int x = 0; x < mW; x++) {
            box.p1.x = mAllocX[x];
            box.p2.x = mAllocX[x+1] - mCellSpacing.x;
            for (int y = 0; y < mH; y++) {
                auto w = mCells[x][y];
                if (w) {
                    box.p1.y = mAllocY[y];
                    box.p2.y = mAllocY[y+1] - mCellSpacing.y;
                    layoutDoAllocChild(w, box);
                }
            }
        }
    }
}

