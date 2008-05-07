module gui.splitter;

import framework.framework;
import gui.container;
import gui.widget;
import utils.misc;
import utils.rect2;
import utils.vector2;

///the Splitter contains two children and a splitter-bar
///this widget is like a BoxContainer with at most two children, where the user
///can control how much space each child gets
class Splitter : Container {
    private {
        int mDir;
        Widget[2] mChildren;
        Widget mSplit; //this is between the two other children
        //absolute split position; if the mSplit widget can move so far, this
        //is equal to the middle of it
        int mSplitPos;
        int mSplitFix; //offset from beginning of splitter-widget to pos

        //the real splitter; this is used for mSplit
        class Split : Spacer {
            bool mDraging;
            Vector2i mStartDrag;

            this() {
                minSize = Vector2i(5);
            }

            override bool onKeyEvent(KeyInfo info) {
                if (info.isMouseButton() && !info.isPress()) {
                    mDraging = info.isDown();
                    mStartDrag = mousePos();
                }
                return true;
            }

            override bool onMouseMove(MouseInfo info) {
                if (mDraging) {
                    auto p = (containedBounds().p1+info.pos-mStartDrag)[mDir];
                    splitPos = p + mSplitFix;
                }
                return true;
            }
        }
    }

    ///horiz = false: vertical splitter (move splitter along x axis),
    ///        true: horizontal (along y)
    this (bool horiz) {
        mDir = horiz ? 0 : 1;
        mSplit = new Split();
        addChild(mSplit);
    }

    ///set one of the children, if there's an old one it's removed first
    /// ch = 0: set the left/top child, 1: set the right/bottom one
    void setChild(int ch, Widget w) {
        assert(ch == 0 || ch == 1);
        if (auto old = mChildren[ch])
            old.remove();
        w.remove();
        mChildren[ch] = w;
        addChild(w);
    }

    override void removeChild(Widget w) {
        foreach (inout c; mChildren) {
            c = c is w ? null : c;
        }
        super.removeChild(w);
    }

    ///what was passed to the constructor
    int dir() {
        return mDir;
    }

    ///set/get the splitter position in absolute units (range [0..size[dir]])
    ///the GUI layouting code will probably position the splitter different
    ///from the requested position to respect the size requests of the child
    ///widgets etc., but splitPos always refers to the user-requested value
    ///xxx not really useful, needs something more sophisticated, probably:
    /// - settable alignment (currently alignment is forced to top/left)
    /// - maintain splitter-pos as a ratio of the width/height
    int splitPos() {
        return mSplitPos;
    }
    void splitPos(int pos) {
        //accept any value; clamping is done by the resize function,
        mSplitPos = pos;
        needRelayout();
    }

    override Vector2i layoutSizeRequest() {
        Vector2i res;
        foreach (c; [mChildren[0], mSplit, mChildren[1]]) {
            auto ch = c ? c.requestSize() : Vector2i(0);
            res[mDir] = res[mDir] + ch[mDir];
            res[!mDir] = max(res[!mDir], ch[!mDir]);
        }
        return res;
    }

    override void layoutSizeAllocation() {
        auto border = mSplit.requestSize()[mDir];
        mSplitFix = (border+1)/2;
        auto c1 = mChildren[0] ? mChildren[0].requestSize() : Vector2i(0);
        auto c2 = mChildren[1] ? mChildren[1].requestSize() : Vector2i(0);
        //pos is in the middle of the splitter; clamp to possible range
        //NOTE: when we got less size than requested, this probably goes wrong
        //  but that shouldn't normally happen anyway
        auto pos = clampRangeC(mSplitPos, c1[mDir] + mSplitFix,
            size()[mDir] - c2[mDir] - (border-mSplitFix));
        int[4] p;
        p[0] = 0;
        p[1] = pos - mSplitFix;
        p[2] = p[1] + border;
        p[3] = size()[mDir];
        foreach (int i, c; [mChildren[0], mSplit, mChildren[1]]) {
            Rect2i rc;
            rc.p1[mDir] = p[i];
            rc.p2[mDir] = p[i+1];
            rc.p1[!mDir] = 0;
            rc.p2[!mDir] = size()[!mDir];
            if (c)
                c.layoutContainerAllocate(rc);
        }
    }
}