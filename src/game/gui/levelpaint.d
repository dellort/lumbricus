module game.gui.levelpaint;

import framework.drawing;
import framework.event;
import framework.i18n;
import framework.main;
import framework.surface;
import game.levelgen.generator;
import game.levelgen.renderer;
import game.levelgen.level;
import game.levelgen.landscape;
import gui.renderbox;
import gui.widget;
import gui.edit;
import gui.dropdownlist;
import gui.button;
import gui.loader;
import gui.list;
import utils.rect2;
import utils.vector2;
import utils.configfile;
import utils.log;
import utils.misc;
import drawing = utils.drawing;
import rand = utils.random;

import tango.math.Math : abs;

enum DrawMode {
    circle,
    square,
    line,
    rect,
}

class PainterWidget : Widget {
    private {
        bool mOwnsLevel;    //true if we can free mLevel, false otherwise
        LandscapeBitmap mLevel;

        //can be overridden by config file
        const Color[Lexel.Max+1] cDefLexelToColor = [Color(0.2, 0.2, 1.0),
            Color(1, 1, 1), Color(0, 0, 0)];
        const cPenRadius = [10, 75];
        const cPenChange = 5;
        const cPenColor = Color(1, 0, 0, 0.5);

        Color[Lexel] mLexelToColor;

        //normally, this is unused; remove it if it's in the way
        const Color[Lexel.Max+1] cDefLexelToBmpColor = [Color.Transparent,
            Color(0.5), Color(0)];
        Surface[Lexel.Max+1] mTex;

        float mPaintScale;
        Vector2i mFitInto = Vector2i(650, 250);
        Vector2i mDrawSize;
        Lexel mPaintLexel = Lexel.INVALID;
        int mPenRadius = 30;
        Vector2i mMouseLast, mClickPos, mClickPosLevel;
        bool mMouseInside, mMouseDown;
        DrawMode mDrawMode = DrawMode.circle;

        enum PMState {
            down,
            up,
            move,
        }
    }

    //?
    const Vector2i cLevelSize = Vector2i(2000, 700);

    //called when levelData is changed (also by external calls like setData)
    void delegate(PainterWidget sender) onChange;

    this() {
        focusable = true;
        setColors(cDefLexelToColor);
        setData(new LandscapeBitmap(cLevelSize, true), true);
    }

    //take the level by reference
    this(LandscapeBitmap lv) {
        focusable = true;
        setColors(cDefLexelToColor);
        setData(lv, false);
    }

    override bool greedyFocus() {
        return true;
    }

    private bool shiftDown() {
        return gFramework.getKeyState(Keycode.LSHIFT)
            || gFramework.getKeyState(Keycode.RSHIFT);
    }

    private void straightenLine(Vector2i lineFrom, ref Vector2i lineTo) {
        Vector2i d = lineTo - lineFrom;
        //4 areas in a quadrant: sin(22.5°) = 0.38
        if (0.38*abs(d.x) > abs(d.y))
            //90° left/right
            d.y = 0;
        else if (0.38*abs(d.y) > abs(d.x))
            //90° up/down
            d.x = 0;
        else {
            //45°
            int c = (abs(d.x) + abs(d.y))/2;
            d.x = d.x<0 ? -c : c;
            d.y = d.y<0 ? -c : c;
        }
        lineTo = lineFrom + d;
    }

    private void straightenRect(Vector2i lineFrom, ref Vector2i lineTo) {
        Vector2i d = lineTo - lineFrom;
        //just 45°, which makes a square
        int c = (abs(d.x) + abs(d.y))/2;
        d.x = d.x<0 ? -c : c;
        d.y = d.y<0 ? -c : c;
        lineTo = lineFrom + d;
    }

    protected void onDraw(Canvas c) {
        if (auto img = mLevel.previewImage())
            c.draw(img, Vector2i(0, 0));
        if (mMouseInside) {
            //draw the current pen for visual feedback of what will be drawn
            int r = cast(int)(mPenRadius*mPaintScale);
            switch (mDrawMode) {
                case DrawMode.circle:
                    c.drawFilledCircle(mousePos, r, cPenColor);
                    break;
                case DrawMode.square:
                    c.drawFilledRect(Rect2i(mousePos-Vector2i(r),
                        mousePos+Vector2i(r)), cPenColor);
                    break;
                case DrawMode.line:
                    if (mMouseDown) {
                        Vector2i lineTo = mousePos;
                        if (shiftDown)
                            straightenLine(mClickPos, lineTo);
                        //overlaps at start and end, feel free to do it properly
                        c.drawFilledCircle(mClickPos, r, cPenColor);
                        c.drawFilledCircle(lineTo, r, cPenColor);
                        c.drawLine(mClickPos, lineTo, cPenColor, 2*r);
                    } else {
                        c.drawFilledCircle(mousePos, r, cPenColor);
                    }
                    break;
                case DrawMode.rect:
                    //draws a thin rectangle and four circles at the edges
                    if (mMouseDown) {
                        Vector2i lineTo = mousePos;
                        if (shiftDown)
                            straightenRect(mClickPos, lineTo);
                        c.drawFilledCircle(mClickPos, r, cPenColor);
                        c.drawFilledCircle(mClickPos.X+lineTo.Y, r,cPenColor);
                        c.drawFilledCircle(mClickPos.Y+lineTo.X, r,cPenColor);
                        c.drawFilledCircle(lineTo, r, cPenColor);
                        Rect2i rc = Rect2i(mClickPos, lineTo);
                        rc.normalize;
                        //sry, opengl rects with thick borders look stupid
                        c.drawRect(rc, cPenColor);
                    } else {
                        c.drawFilledCircle(mousePos, r, cPenColor);
                    }
                    break;
            }
        }
    }

    override bool onKeyDown(KeyInfo infos) {
        if (infos.code == Keycode.MOUSE_LEFT) {
            mPaintLexel = Lexel.SolidSoft;
            paintAtMouse(PMState.down);
            return true;
        }
        if (infos.code == Keycode.MOUSE_MIDDLE) {
            mPaintLexel = Lexel.SolidHard;
            paintAtMouse(PMState.down);
            return true;
        }
        if (infos.code == Keycode.MOUSE_RIGHT) {
            mPaintLexel = Lexel.Null;
            paintAtMouse(PMState.down);
            return true;
        }
        if (infos.code == Keycode.MOUSE_WHEELUP) {
            mPenRadius = min(mPenRadius+cPenChange, cPenRadius[1]);
            return true;
        }
        if (infos.code == Keycode.MOUSE_WHEELDOWN) {
            mPenRadius = max(mPenRadius-cPenChange, cPenRadius[0]);
            return true;
        }
        return false;
    }

    override void onKeyUp(KeyInfo infos) {
        if (infos.code == Keycode.MOUSE_LEFT
            || infos.code == Keycode.MOUSE_MIDDLE
            || infos.code == Keycode.MOUSE_RIGHT) {
            paintAtMouse(PMState.up);
            mPaintLexel = Lexel.INVALID;
        }
    }

    override protected void onMouseMove(MouseInfo info) {
        if (mPaintLexel != Lexel.INVALID) {
            paintAtMouse();
        }
    }

    override protected void onMouseEnterLeave(bool mouseIsInside) {
        mMouseInside = mouseIsInside;
    }

    private void paintAtMouse(PMState s = PMState.move) {
        if ((s == PMState.down && mMouseDown) ||
            (s == PMState.up && !mMouseDown))
            return;
        Vector2i levelPos = Vector2i(
            cast(int)(mLevel.size.x*(cast(float)mousePos.x)/mDrawSize.x),
            cast(int)(mLevel.size.y*(cast(float)mousePos.y)/mDrawSize.y));

        if (s == PMState.up) {
            mMouseDown = false;
            Vector2i lineTo = levelPos;
            if (mDrawMode == DrawMode.line) {
                if (shiftDown)
                    straightenLine(mClickPosLevel, lineTo);
                doPaint(mClickPosLevel, lineTo);
            }
            if (mDrawMode == DrawMode.rect) {
                if (shiftDown)
                    straightenRect(mClickPosLevel, lineTo);
                doPaint(mClickPosLevel, mClickPosLevel.Y+lineTo.X);
                doPaint(mClickPosLevel.Y+lineTo.X, lineTo);
                doPaint(lineTo, mClickPosLevel.X+lineTo.Y);
                doPaint(mClickPosLevel.X+lineTo.Y, mClickPosLevel);
            }
        }
        if (s == PMState.down) {
            mMouseDown = true;
            mMouseLast = levelPos;
            mClickPos = mousePos;
            mClickPosLevel = levelPos;
        }
        if (s == PMState.move || s == PMState.down) {
            if (mDrawMode == DrawMode.circle || mDrawMode == DrawMode.square)
                doPaint(mMouseLast, levelPos, mDrawMode == DrawMode.square);
        }
        mMouseLast = levelPos;
    }

    //called with absolute position in final level (0, 0)-mLevel.size
    //draw a line from p1 to p2, using mPaintLexel and mPenRadius
    private void doPaint(Vector2i p1, Vector2i p2, bool square = false) {
        assert(mPaintLexel >= 0 && mPaintLexel < 3);

        //NOTE: can pass null as first parameter; if mLevel has no bitmap (data
        //  only, the common case here), the parameter is ignored anyway
        mLevel.drawSegment(mTex[mPaintLexel], mPaintLexel, p1, p2, mPenRadius,
            square);

        if (onChange)
            onChange(this);
    }

    //fill the whole level with l
    private void fill(Lexel l) {
        assert(l != Lexel.INVALID);
        Color* pcol = l in mLexelToColor;
        mLevel.fill(pcol ? *pcol : Color.Black, l);
        if (onChange)
            onChange(this);
    }

    void fillSolidSoft() {
        fill(Lexel.SolidSoft);
    }

    void clear() {
        fill(Lexel.Null);
    }

    void setDrawMode(DrawMode dm) {
        mDrawMode = dm;
    }

    //refresh the whole scaled lexel cache and image (e.g. after clearing,
    //   or loading an existing level)
    //xxx this is quite slow
    void fullUpdate() {

    }

    override Vector2i layoutSizeRequest() {
        return mDrawSize;
    }

    Vector2i levelSize() {
        return mLevel.size;
    }

    LandscapeBitmap copyLexels() {
        return mLevel.copy();
    }

    LandscapeBitmap peekLexels() {
        return mLevel;
    }

    //transfer_ownership = if we can free the level when we're done
    void setData(LandscapeBitmap level, bool transfer_ownership) {
        argcheck(level);
        if (mOwnsLevel && mLevel) {
            mLevel.free();
            mLevel = null;
            mOwnsLevel = false;
        }
        if (level.hasImage())
            gLog.warn("using levelpaint on a level with image, might be slow");
        mLevel = level;
        mOwnsLevel = transfer_ownership;
        reinit();
    }

    //mLevel is set; reinit the rest
    private void reinit() {
        //fit the level into mFitInto, keeping aspect ratio
        mDrawSize = mLevel.size.fitKeepAR(mFitInto);
        mPaintScale = cast(float)mDrawSize.x/mLevel.size.x;

        mLevel.previewDestroy();
        mLevel.previewInit(mDrawSize, mLexelToColor);

        if (onChange)
            onChange(this);
    }


    void setColors(Color[] cols) {
        mLexelToColor = null;
        foreach (uint idx, Color c; cols) {
            mLexelToColor[cast(Lexel)idx] = c;
        }
        for (int i = 0; i < cDefLexelToBmpColor.length; i++) {
            mTex[i] = new Surface(Vector2i(1), Transparency.Alpha);
            mTex[i].fill(Rect2i(0,0,1,1), cDefLexelToBmpColor[i]);
        }
    }

    override MouseCursor mouseCursor() {
        return MouseCursor.None;
    }

    void colorsFromNode(ConfigNode node) {
        Color[] colors;
        foreach (char[] n, char[] value; node) {
            colors ~= Color.fromString(value);
        }
        if (colors.length > 0)
            setColors(colors);
    }

    override void loadFrom(GuiLoader loader) {
        auto node = loader.node;

        mFitInto = node.getValue("fit_into", mFitInto);
        colorsFromNode(node.getSubNode("colors"));
        clear();

        super.loadFrom(loader);
    }
}
