module gui.list;

import framework.font;
import framework.framework;
import gui.container;
import gui.scrollwindow;
import gui.widget;
import utils.configfile;
import utils.misc;
import utils.rect2;
import utils.vector2;

/// Naive list widget with fixed height entries
/// Simply has the height of all entries multiplicated with the entry height
/// Use ScrollArea/ScrollWindow to scroll the list
class AbstractListWidget : Widget {
    private {
        int mHeight; //as requested by user
        int mRHeight = 1; //real height
        int mCount;
        int mSelected = cUnselected;
        int mHoverIndex = cUnselected;
        //twice on all border for each coord.
        Vector2i mSpacing = {5,1};
        bool mMouseInside;
    }

    const cUnselected = -1;

    /// event for selection; for meaning of index cf. selectedIndex(int)
    /// xxx: unselect event?
    void delegate(int index) onSelect;

    this() {
        styles.addClass("w-list");
        focusable = true;
    }

    int count() {
        return mCount;
    }

    /// selected item, or cUnselected (always below 0) if none selected
    int selectedIndex() {
        return mSelected;
    }

    //is it ok that this is public writeable?
    void selectedIndex(int index) {
        mSelected = (index >= 0 && index < mCount) ? index : cUnselected;
        if (onSelect)
            onSelect(index);
    }

    Vector2i spacing() {
        return mSpacing;
    }

    void setSpacing(Vector2i spacing) {
        if (spacing != mSpacing)
            return;
        mSpacing = spacing;
        needResize(true);
    }

    /// notify about changed numbers of entries
    protected void notifyResize(int acount) {
        if (acount == mCount)
            return;
        mCount = acount;
        if (mSelected >= mCount) //xxx: unselect event?
            mSelected = cUnselected;
        needResize(true);
    }

    /// notify about changed height of the entries
    protected void notifyHeight(int aheight) {
        if (aheight == mHeight)
            return;
        mHeight = aheight;
        needResize(true);
    }

    protected int size_request_x() {
        return 0;
    }

    override protected Vector2i layoutSizeRequest() {
        mRHeight = mHeight + mSpacing.y*2;
        if (mRHeight <= 0)
            mRHeight = 1;
        return Vector2i(size_request_x + mSpacing.x*2, mRHeight*mCount);
    }

    override void onDraw(Canvas canvas) {
        //only draw items which are visible
        auto visible = canvas.visibleArea();
        int index = 0;//visible.p1.y / mRHeight; //first
        Rect2i rc;
        rc.p1.x = mSpacing.x; rc.p2.x = size.x - mSpacing.x;
        for (;;) {
            rc.p1.y = index*mRHeight+mSpacing.y;
            rc.p2.y = rc.p1.y + mHeight;
            //if (visible.p2.y <= rc.p1.y ||
            if (index >= mCount)
                break;
            drawItem(canvas, rc, index,
                mHoverIndex>cUnselected?index==mHoverIndex:index==mSelected);
            index++;
        }
    }

    override protected void onKeyEvent(KeyInfo key) {
        switch (key.code) {
            case Keycode.DOWN: {
                if (key.isPress && selectedIndex+1 < count)
                    selectedIndex = selectedIndex+1;
                break;
            }
            case Keycode.UP: {
                if (key.isPress && selectedIndex-1 >= 0)
                    selectedIndex = selectedIndex-1;
                break;
            }
            case Keycode.MOUSE_LEFT: {
                mHoverIndex = cUnselected;
                int newIndex = mousePos.y / mRHeight;
                newIndex = newIndex>=count ? count-1 : newIndex;
                if ((key.isDown || key.isPress) && mMouseInside) {
                    mHoverIndex = newIndex;
                }
                if (key.isUp && mMouseInside) {
                    selectedIndex = newIndex;
                }
                break;
            }
            default:
        }
    }

    override protected void onMouseMove(MouseInfo mi) {
        mMouseInside = testMouse(mi.pos);
        if (gFramework.getKeyState(Keycode.MOUSE_LEFT) && mMouseInside) {
            int index = mousePos.y / mRHeight;
            mHoverIndex = index>=count ? count-1 : index;
        } else {
            mHoverIndex = cUnselected;
        }
    }

    override protected void onMouseEnterLeave(bool mouseIsInside) {
        super.onMouseEnterLeave(mouseIsInside);
        if (!mouseIsInside)
            mMouseInside = false;
    }

    /// draw an item with that index on canvas at rc
    /// highlight = if this is a (currently only: the) selected entry
    /// NOTE: callee must draw highlighting on its own
    abstract protected void drawItem(Canvas canvas, Rect2i rc, int index,
        bool highlight);

    override void loadFrom(GuiLoader loader) {
        auto node = loader.node;

        mSpacing = node.getValue("spacing", mSpacing);

        super.loadFrom(loader);
    }
}

/// Contains... strings
class StringListWidget : AbstractListWidget {
    private {
        char[][] mContents;
        Font mFont;
        bool mCheckWidth;
        int mWidth; //only when mCheckWidth is true, else this is 0
    }

    /// This doesn't copy the array.
    /// Hereby I allow the user to change the contents of the array if it
    /// doesn't change anything for the list except the rendering; if elements
    /// are added or removed, call this again after changing...
    /// When checkWidth is true, this should/must be called on each change
    void setContents(char[][] contents) {
        mContents = contents;
        notifyResize(mContents.length);
        recheckWidths();
    }

    char[][] contents() {
        return mContents;
    }

    void recheckWidths() {
        if (!mCheckWidth)
            return;
        int w;
        foreach (char[] item; mContents) {
            w = max(w, mFont.textSize(item).x);
        }
        if (w != mWidth) {
            mWidth = w;
            needResize(true);
        }
    }

    /// If true, the maximum width of all list entries sets the request size of
    /// the list widget; could be S.L.O.W. if enabled
    bool checkWidth() {
        return mCheckWidth;
    }
    void checkWidth(bool set) {
        if (mCheckWidth == set)
            return;
        mCheckWidth = set;
        if (set) {
            recheckWidths();
        } else {
            mWidth = 0;
        }
    }

    override protected int size_request_x() {
        return mWidth;
    }

    this() {
        font = gFontManager.loadFont("");
    }

    Font font() {
        return mFont;
    }
    void font(Font f) {
        assert(!!f);
        mFont = f;
        notifyHeight(f.textSize("").y);
        recheckWidths();
    }

    override protected void drawItem(Canvas canvas, Rect2i rc, int index,
        bool highlight)
    {
        assert(index >= 0 && index < mContents.length);
        mFont.drawText(canvas, rc.p1, mContents[index]);
        //the simple way, hahaha
        if (highlight)
            canvas.drawFilledRect(rc.p1, rc.p2, Color(0.7, 0.7, 0.7, 0.7));
    }

    override void loadFrom(GuiLoader loader) {
        auto node = loader.node;

        mSpacing = node.getValue("spacing", mSpacing);
        auto fnt = gFontManager.loadFont(node["font"], false);
        if (fnt)
            font = fnt;
        checkWidth = node.getBoolValue("check_width", checkWidth);
        auto cnt = node.findNode("contents");
        if (cnt) {
            setContents(cnt.getCurValue!(char[][])());
        }

        super.loadFrom(loader);
    }

    static this() {
        WidgetFactory.register!(typeof(this))("string_list");
    }
}
