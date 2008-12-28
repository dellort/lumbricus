module gui.tablecontainer;
import gui.container;
import gui.widget;
import utils.configfile;
import utils.vector2;
import utils.rect2;
import utils.misc;

//like BoxContainer, but two dimensional
//the width of a row is taken from the maximum width of all other cells in the
//same column; same reverse for the height of them
//cells without widgets have request size 0 and are not expanded
//cell spanning:
//  works as in GTK and the expand property isn't used for spanning cells
//  but you still can use setForceExpand()
//  an algorithm to support automatic expand for spannin cells:
//      - for each header, count how many spanning cells it includes that wants
//        to expand
//      - set column with highest count to expand
//      - set a flag on all cells whose expand is now satisfied
//      - repeat until no spanning cells with unset flags anymore
class TableContainer : PublicContainer {
    private {
        int[2] mSize; //size in cells

        struct PerChild {
            Widget w;
            //cell the widget is in
            int[2] p;
            //number of cells this cell spans, usually only [1,1]
            int[2] join;
            //temporary during resize
            Vector2i minSize;
            bool[2] expand;
        }
        PerChild[] mChildren;

        //spacing _between_ cells (per direction)
        Vector2i mCellSpacing;

        bool[2] mHomogeneous;
        bool[2] mForceExpand;

        //temporary between layoutSizeRequest() and allocation
        Vector2i mLastSize;

        //header array for each direction; mHeaders[0] = columns, ...[1] = rows
        Header[][2] mHeaders;

        //header for each row or column
        struct Header {
            //force this column/row to expand
            bool forceExpand;

            //temporaries between sizing and allocation
            bool expand;
            //minimal requested width/height in this column/row
            int minSize;
            //allocated size (valid after allocation)
            //start and end of the column/row
            int allocA, allocB;
        }
    }

    ///default constructor needed for WidgetFactory/gui.loader
    this() {
        setSize(0, 0);
    }

    ///a_w, a_h = number of cells in this direction
    ///cellspacing = spacing between cells (doesn't add borders around the
    ///  table, use the table-widget's .setLayout() for that)
    ///homogeneous = for each direction if all cells should have the same size
    ///forceExpand = for each direction if all cells should be expanded
    this(int a_w, int a_h, Vector2i cellspacing = Vector2i(),
        bool[2] homogeneous = [false, false],
        bool[2] forceExpand = [false, false])
    {
        setSize(a_w, a_h);

        mHomogeneous[] = homogeneous;
        mForceExpand[] = forceExpand;
        mCellSpacing = cellspacing;
    }

    ///per column/row force-expand setting
    /// dir = 0 address a column, 1 address a row
    /// num = row or column to set
    /// force_expand = guess what
    void setForceExpand(int dir, int num, bool force_expand) {
        mHeaders[dir][num].forceExpand = force_expand;
        needRelayout();
    }

    ///getter for setForceExpand()
    bool getForceExpand(int dir, int num) {
        return mHeaders[dir][num].forceExpand;
    }

    ///query if a column/row was expanded (after layouting)
    bool isExpandedAt(int dir, int num) {
        return mHeaders[dir][num].expand;
    }

    //NOTE: static arrays are reference types by default lol
    void getParams(bool[2] homogeneous, bool[2] force_expand) {
        homogeneous[] = mHomogeneous;
        force_expand[] = mForceExpand;
    }
    void setParams(bool[2] homogeneous, bool[2] force_expand) {
        mHomogeneous[] = homogeneous;
        mForceExpand[] = force_expand;
        needRelayout();
    }

    Vector2i cellSpacing() {
        return mCellSpacing;
    }
    void cellSpacing(Vector2i sp) {
        mCellSpacing = sp;
        needRelayout();
    }

    private bool checkCoordinates(PerChild pc) {
        bool ok = true;
        for (int n = 0; n < 2; n++) {
            ok &= pc.p[n] >= 0 && pc.join[n] >= 1
                && pc.p[n] + pc.join[n] <= mSize[n];
        }
        return ok;
    }

    ///set size in cell count; if it gets smaller, widgets which don't fit into
    ///the table anymore are removed
    void setSize(int a_w, int a_h) {
        mSize[0] = a_w;
        mSize[1] = a_h;

        mHeaders[0].length = mSize[0];
        mHeaders[1].length = mSize[1];

        //remove children that have invalid table coordinates
        //iterates backwards; .remove calls removeChildren => array changes
        Widget[] removelist; //removing triggers relayout -> delay it
        for (int n = mChildren.length-1; n >= 0; n--) {
            if (!checkCoordinates(mChildren[n])) {
                removelist ~= mChildren[n].w;
                mChildren = mChildren[0..n] ~ mChildren[n+1..$];
            }
        }
        foreach (w; removelist) {
            w.remove();
        }

        needRelayout();
    }

    ///add a row/column; returns _index_ of the new row/column
    int addRow() {
        setSize(width(), height()+1);
        return height() - 1;
    }
    int addColumn() {
        setSize(width()+1, height());
        return width() - 1;
    }

    final int width() {
        return mSize[0];
    }
    final int height() {
        return mSize[1];
    }

    void add(Widget w, int x, int y, WidgetLayout layout) {
        w.setLayout(layout);
        add(w, x, y);
    }

    //add a child at (x,y), with spans (s_x,s_y) cells
    void add(Widget w, int x, int y, int s_x = 1, int s_y = 1) {
        PerChild pc;
        pc.p[0] = x; pc.p[1] = y;
        pc.join[0] = s_x; pc.join[1] = s_y;
        bool ok = checkCoordinates(pc);
        if (!ok) {
            assert(false);
        }
        w.remove();
        pc.w = w;
        mChildren ~= pc;
        addChild(w);
    }

    private int find_pc(Widget w) {
        for (int n = 0; n < mChildren.length; n++) {
            if (mChildren[n].w is w)
                return n;
        }
        return -1;
    }

    override protected void removeChild(Widget w) {
        int index = find_pc(w);
        if (index >= 0) {
            mChildren = mChildren[0..index] ~ mChildren[index+1..$];
        }
        super.removeChild(w);
    }

    void getChildRowCol(Widget w, out int x, out int y, out int s_x,
        out int s_y)
    {
        int index = find_pc(w);
        if (index < 0)
            throw new Exception("getChildRowCol: bad parameter");
        auto pc = mChildren[index];
        x = pc.p[0];
        y = pc.p[1];
        s_x = pc.join[0];
        s_y = pc.join[1];
    }

    //some stupid code needed this sigh
    Widget get(int x, int y) {
        foreach (inout pc; mChildren) {
            if (pc.p[0] == x && pc.p[1] == y)
                return pc.w;
        }
        return null;
    }

    //find all children which cover a cell in the given range (cf. add())
    //never calls d twice for a child
    void findCellsAt(int x, int y, int s_x, int s_y, void delegate(Widget c) d)
    {
        //lol why not
        auto rc = Rect2i.Span(Vector2i(x, y), Vector2i(s_x, s_y));
        foreach (inout pc; mChildren) {
            auto rc2 = Rect2i.Span(Vector2i(pc.p[0], pc.p[1]),
                Vector2i(pc.join[0], pc.join[1]));
            if (rc2.intersects(rc) && pc.w)
                d(pc.w);
        }
    }

    //process size request for one direction
    private int doSizeRequest(int dir) {
        Header[] heads = mHeaders[dir];
        int space = max(0, mCellSpacing[dir]);

        foreach (inout h; heads) {
            h.expand = h.forceExpand | mForceExpand[dir] | mHomogeneous[dir];
            h.minSize = 0;
        }

        //set expand, but only if it doesn't join multiple cells
        foreach (inout pc; mChildren) {
            if (pc.join[dir] == 1) {
                int n = pc.p[dir];
                heads[n].expand |= pc.expand[dir];
            }
        }

        //set minimal sizes (processes normal and spanning cells)
        foreach (inout pc; mChildren) {
            int requestSize = pc.minSize[dir];
            int n = pc.p[dir];
            int count = pc.join[dir];

            //sum up width (also count expandable cells for below)
            int expandCount, size;
            for (int i = n; i < n+count; i++) {
                expandCount += heads[i].expand ? 1 : 0;
                //substract cell spacing because that gets added seperately
                size += heads[i].minSize - space;
            }
            size += space; //count only spacing _between_ cells

            //if the columns/rows are too small, add as much as is still needed
            //for a normal cell, this is minSize = max(minSize, requestSize)
            int need = requestSize - size;
            if (need > 0) {
                //need more size => distribute it across cells
                bool forceExpand = (expandCount == 0);
                if (forceExpand)
                    expandCount = count; //to all cells
                //note: /+round up+/
                int add = (need /++ expandCount - 1+/) / expandCount;
                for (int i = n; i < n+count; i++) {
                    if (forceExpand || heads[i].expand) {
                        heads[i].minSize += add;
                    }
                }
            }
        }

        if (mHomogeneous[dir]) {
            //homogenize
            int minWidth;
            foreach (inout h; heads) {
                minWidth = max(minWidth, h.minSize);
            }
            foreach (inout h; heads) {
                h.minSize = minWidth;
            }
        }

        //sum up (could speed up this when homogeneous)
        int sum;
        foreach (inout h; heads) {
            sum += h.minSize + space;
        }
        //only space between cells; when grid has size 0 it becomes -space
        sum = max(0, sum - space);

        return sum;
    }

    //allocate row/column header coordinates according to extrasize, which is
    //the additional size to the requested minimum size
    //fills out the Header.alloc fields
    private void doSizeAlloc(int dir, int extrasize) {
        Header[] heads = mHeaders[dir];
        int space = max(0, mCellSpacing[dir]);

        if (extrasize < 0)
            extrasize = 0; //sorry no shrinking, but also don't blow up

        //distribute extra space equally accross all expanding cells

        int expandcount;
        foreach (inout h; heads) {
            expandcount += h.expand ? 1 : 0;
        }

        //the 0-case occurs when not expanding at all, but there's extra space
        //be top-left aligned then
        //also, /+round up the division+/ <- no, looks fugly
        auto extra = expandcount ? (extrasize/++expandcount-1+/)/expandcount : 0;

        int cur;
        foreach (inout h; heads) {
            h.allocA = cur;
            cur += h.minSize + (h.expand ? extra : 0);
            h.allocB = cur;
            cur += space;
        }
    }

    protected Vector2i layoutSizeRequest() {
        foreach (inout pc; mChildren) {
            assert(pc.w !is null);
            pc.minSize = pc.w.layoutCachedContainerSizeRequest();
            pc.expand[] = pc.w.layout.expand;
        }

        mLastSize.x = doSizeRequest(0);
        mLastSize.y = doSizeRequest(1);

        return mLastSize;
    }

    protected override void layoutSizeAllocation() {
        Vector2i extra = size - mLastSize;

        //first calculate allocations...
        doSizeAlloc(0, extra[0]);
        doSizeAlloc(1, extra[1]);

        //and then assign them
        foreach (inout pc; mChildren) {
            pc.w.layoutContainerAllocate(cellRect(pc.p[0], pc.p[1], pc.join[0],
                pc.join[1]));
        }
    }

    //similar to the cell's allocated size (without cell spacing)
    Rect2i cellRect(int x, int y, int s_x = 1, int s_y = 1) {
        Rect2i box;
        box.p1.x = mHeaders[0][x].allocA;
        box.p1.y = mHeaders[1][y].allocA;
        box.p2.x = mHeaders[0][x + s_x - 1].allocB;
        box.p2.y = mHeaders[1][y + s_y - 1].allocB;
        return box;
    }

    //xxx change this to use public methods only
    void loadFrom(GuiLoader loader) {
        auto node = loader.node;

        auto size = Vector2i(mSize[0], mSize[1]);
        parseVector(node.getStringValue("size"), size);
        setSize(size.x, size.y);

        parseVector(node.getStringValue("cellspacing"), mCellSpacing);

        mHomogeneous[0] = node.getBoolValue("homogeneous_x", mHomogeneous[0]);
        mHomogeneous[1] = node.getBoolValue("homogeneous_y", mHomogeneous[1]);

        mForceExpand[0] = node.getBoolValue("force_expand_x", mForceExpand[0]);
        mForceExpand[1] = node.getBoolValue("force_expand_y", mForceExpand[1]);

        //childrens are loaded in order, line by line
        Vector2i pos;
        //skip k many cells
        void skip(int k) {
            if (!mSize[0])
                return;
            pos.x += k;
            pos.y += pos.x / mSize[0];
            pos.x = pos.x % mSize[0];
        }
        foreach (ConfigNode child; node.getSubNode("cells")) {
            //if a cell contains "table_skip", it doesn't contain a Widget
            const cSkip = "table_skip";
            if (child.hasValue(cSkip)) {
                skip(child.getIntValue(cSkip, 1));
            } else {
                //allow explicit relocation, but it isn't required
                parseVector(child.getStringValue("table_at"), pos);
                Vector2i span;
                //xxx error checking
                if (!parseVector(child.getStringValue("table_span"), span))
                    span = Vector2i(1, 1);
                add(loader.loadWidget(child), pos.x, pos.y, span.x, span.y);
                skip(span.x*span.y);
            }
        }

        super.loadFrom(loader);
    }

    static this() {
        WidgetFactory.register!(typeof(this))("tablecontainer");
    }
}

