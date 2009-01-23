module game.gui.levelpaint;

import framework.framework;
import framework.i18n;
import common.common;
import common.visual;
import game.gfxset;
import game.levelgen.generator;
import game.levelgen.renderer;
import game.levelgen.level;
import game.levelgen.landscape;
import gui.widget;
import gui.edit;
import gui.dropdownlist;
import gui.button;
import gui.wm;
import gui.loader;
import gui.list;
import utils.rect2;
import utils.vector2;
import utils.configfile;
import utils.misc;
import drawing = utils.drawing;
import rand = utils.random;

import str = stdx.string;

enum DrawMode {
    circle,
    square,
    line,
    rect,
}

class PainterWidget : Widget {
    private {
        Lexel[] mLevelData;

        Surface mImage;

        const cPaintScale = 0.33;
        //CTFE ftw
        const Color[Lexel.Max+1] cDefLexelToColor = [Color(0.2, 0.2, 1.0),
            Color(1, 1, 1), Color(0, 0, 0)];
        const cPenRadius = [10, 75];
        const cPenChange = 5;
        const cPenColor = Color(1, 0, 0, 0.5);

        Color[Lexel.Max+1] mLexelToColor;
        uint[Lexel.Max+1] mLexelToRGBA32;

        Vector2i mLevelSize = Vector2i(2000, 700);
        Rect2i mLevelRect;
        Lexel mPaintLexel = Lexel.INVALID;
        int mPenRadius = 30;
        Lexel[] mScaledLevel;
        Vector2i mMouseLast, mClickPos, mClickPosLevel;
        bool mMouseInside, mMouseDown;
        DrawMode mDrawMode = DrawMode.circle;

        enum PMState {
            down,
            up,
            move,
        }
    }

    void delegate(PainterWidget sender) onChange;

    this() {
        setColors(cDefLexelToColor);

        auto drawSize = toVector2i(toVector2f(mLevelSize)*cPaintScale);
        mImage = gFramework.createSurface(drawSize, Transparency.None, Color(0));
        mLevelRect.p2 = mLevelSize;
        mScaledLevel = new Lexel[drawSize.x*drawSize.y];

        mLevelData = new Lexel[mLevelSize.x*mLevelSize.y];
        clear();
    }

    this(LandscapeBitmap level) {
        setData(level.levelData.dup, level.size);
    }

    override bool canHaveFocus() {
        return true;
    }
    override bool greedyFocus() {
        return true;
    }

    protected void onDraw(Canvas c) {
        c.draw(mImage, Vector2i(0, 0));
        if (mMouseInside) {
            //draw the current pen for visual feedback of what will be drawn
            int r = cast(int)(mPenRadius*cPaintScale);
            switch (mDrawMode) {
                case DrawMode.circle:
                    c.drawFilledCircle(mousePos, r, cPenColor);
                    break;
                case DrawMode.square:
                    c.drawFilledRect(mousePos-Vector2i(r), mousePos+Vector2i(r),
                        cPenColor);
                    break;
                case DrawMode.line:
                    //overlaps at start and end, feel free to do it properly
                    c.drawFilledCircle(mousePos, r, cPenColor);
                    if (mMouseDown) {
                        c.drawFilledCircle(mClickPos, r, cPenColor);
                        c.drawLine(mClickPos, mousePos, cPenColor, 2*r);
                    }
                    break;
                case DrawMode.rect:
                    //draws a thin rectangle and four circles at the edges
                    c.drawFilledCircle(mousePos, r, cPenColor);
                    if (mMouseDown) {
                        c.drawFilledCircle(mClickPos, r, cPenColor);
                        c.drawFilledCircle(mClickPos.X+mousePos.Y, r,cPenColor);
                        c.drawFilledCircle(mClickPos.Y+mousePos.X, r,cPenColor);
                        Rect2i rc = Rect2i(mClickPos, mousePos);
                        rc.normalize;
                        //sry, opengl rects with thick borders look stupid
                        c.drawRect(rc, cPenColor);
                    }
                    break;
            }
        }
    }

    private bool onKeyDown(char[] bind, KeyInfo infos) {
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

    private bool onKeyUp(char[] bind, KeyInfo infos) {
        if (infos.code == Keycode.MOUSE_LEFT
            || infos.code == Keycode.MOUSE_MIDDLE
            || infos.code == Keycode.MOUSE_RIGHT) {
            paintAtMouse(PMState.up);
            mPaintLexel = Lexel.INVALID;
            return true;
        }
        return false;
    }

    override protected void onKeyEvent(KeyInfo ki) {
        auto b = findBind(ki);
        (ki.isDown && onKeyDown(b, ki))
            || (ki.isUp && onKeyUp(b, ki));
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
            cast(int)(mLevelSize.x*(cast(float)mousePos.x)/mImage.size.x),
            cast(int)(mLevelSize.y*(cast(float)mousePos.y)/mImage.size.y));

        if (s == PMState.up) {
            mMouseDown = false;
            if (mDrawMode == DrawMode.line)
                doPaint(mClickPosLevel, levelPos);
            if (mDrawMode == DrawMode.rect) {
                doPaint(mClickPosLevel, mClickPosLevel.Y+levelPos.X);
                doPaint(mClickPosLevel.Y+levelPos.X, levelPos);
                doPaint(levelPos, mClickPosLevel.X+levelPos.Y);
                doPaint(mClickPosLevel.X+levelPos.Y, mClickPosLevel);
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

    //called with absolute position in final level (0, 0)-mLevelSize
    //draw a line from p1 to p2, using mPaintLexel and mPenRadius
    private void doPaint(Vector2i p1, Vector2i p2, bool square = false) {
        assert(mPaintLexel >= 0 && mPaintLexel < 3);

        //just for convenience
        void drawRect(Vector2i p, int radius,
            void delegate(int x1, int x2, int y) dg)
        {
            for (int y = p.y-radius; y < p.y+radius; y++) {
                dg(p.x-radius, p.x+radius-1, y);
            }
        }

        void drawThickLine(Vector2i p1, Vector2i p2, int radius, Vector2i size,
            void delegate(int x1, int x2, int y) dg)
        {
            if (square)
                drawRect(p1, radius, dg);
            else
                drawing.circle(p1.x, p1.y, radius, dg);
            if (p1 != p2) {
                if (square)
                    drawRect(p2, radius, dg);
                else
                    drawing.circle(p2.x, p2.y, radius, dg);
                Vector2f[4] poly;
                if (!square) {
                    Vector2f line_o = toVector2f(p2-p1).orthogonal.normal;
                    poly[0] = toVector2f(p1)-line_o*radius;
                    poly[1] = toVector2f(p1)+line_o*radius;
                    poly[2] = toVector2f(p2)+line_o*radius;
                    poly[3] = toVector2f(p2)-line_o*radius;
                } else {
                    int r = radius;
                    if (p1.x > p2.x && p1.y > p2.y
                        || p1.x < p2.x && p1.y < p2.y)
                    {
                        poly[0] = toVector2f(p1+Vector2i(r, -r));
                        poly[1] = toVector2f(p1+Vector2i(-r, r));
                        poly[2] = toVector2f(p2+Vector2i(-r, r));
                        poly[3] = toVector2f(p2+Vector2i(r, -r));
                    } else {
                        poly[0] = toVector2f(p1+Vector2i(r, r));
                        poly[1] = toVector2f(p1+Vector2i(-r, -r));
                        poly[2] = toVector2f(p2+Vector2i(-r, -r));
                        poly[3] = toVector2f(p2+Vector2i(r, r));
                    }
                }
                drawing.rasterizePolygon(size.x, size.y, poly, false, dg);
            }
        }

        //draw into final level
        void scanline(int x1, int x2, int y) {
            if (y < 0 || y >= mLevelSize.y) return;
            if (x1 < 0) x1 = 0;
            if (x2 >= mLevelSize.x) x2 = mLevelSize.x-1;
            int ly = y*mLevelSize.x;
            for (int x = x1; x <= x2; x++) {
                mLevelData[ly+x] = mPaintLexel;
            }
        }
        drawThickLine(p1, p2, mPenRadius, mLevelSize, &scanline);


        //points scaled to image width
        Vector2i p1_sc = toVector2i(toVector2f(p1)*cPaintScale);
        Vector2i p2_sc = toVector2i(toVector2f(p2)*cPaintScale);
        int r_sc = cast(int)(mPenRadius*cPaintScale);

        //draw into displayed image
        void* pixels; uint pitch;
        mImage.lockPixelsRGBA32(pixels, pitch);

        void scanline2(int x1, int x2, int y) {
            if (y < 0 || y >= mImage.size.y) return;
            if (x1 < 0) x1 = 0;
            if (x2 >= mImage.size.x) x2 = mImage.size.x-1;
            int ly = y*mImage.size.x;
            uint* dstptr = cast(uint*)(pixels+pitch*y)+x1;
            for (int x = x1; x <= x2; x++) {
                //actually, the following line is not necessary
                mScaledLevel[ly+x] = mPaintLexel;
                *dstptr = mLexelToRGBA32[mPaintLexel];
                dstptr++;
            }
        }
        drawThickLine(p1_sc, p2_sc, r_sc, mImage.size, &scanline2);

        //update modified area (for opengl)
        Rect2i mod = Rect2i(p1_sc, p2_sc);
        mod.normalize();
        mod.extendBorder(Vector2i(r_sc+1, r_sc+1));
        mod.fitInsideB(mImage.rect);
        mImage.unlockPixels(mod);

        if (onChange)
            onChange(this);
    }

    //fill the whole level with l
    private void fill(Lexel l) {
        assert(l != Lexel.INVALID);
        mLevelData[] = l;
        //this should be faster than calling fullUpdate()
        mScaledLevel[] = l;
        mImage.fill(mImage.rect, mLexelToColor[l]);
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
        assert(mScaledLevel.length == mImage.size.x*mImage.size.y);
        assert(mLevelData.length == mLevelSize.x*mLevelSize.y);

        //scale down from full size to image size
        scaleLexels(mLevelData, mScaledLevel, mLevelSize, mImage.size);

        //transfer lexel data to image
        void* pixels; uint pitch;
        mImage.lockPixelsRGBA32(pixels, pitch);
        for (int y = 0; y < mImage.size.y; y++) {
            uint* dstptr = cast(uint*)(pixels+pitch*y);
            int lsrc = y*mImage.size.x;
            for (int x = 0; x < mImage.size.x; x++) {
                uint col = mLexelToRGBA32[mScaledLevel[lsrc+x]];
                *dstptr = col;
                dstptr++;
            }
        }
        mImage.unlockPixels(mImage.rect);
    }

    override Vector2i layoutSizeRequest() {
        return mImage.size;
    }

    Vector2i levelSize() {
        return mLevelSize;
    }

    Lexel[] levelData() {
        return mLevelData;
    }

    void setData(Lexel[] data, Vector2i size) {
        mLevelSize = size;
        auto drawSize = toVector2i(toVector2f(mLevelSize)*cPaintScale);
        if (mImage)
            mImage.free;
        mImage = gFramework.createSurface(drawSize, Transparency.None, Color(0));
        mLevelRect.p2 = mLevelSize;
        mScaledLevel = new Lexel[drawSize.x*drawSize.y];

        mLevelData = data;
        fullUpdate();
        if (onChange)
            onChange(this);
    }

    void setColors(Color[] cols) {
        for (int i = 0; i <= Lexel.Max; i++) {
            if (i < cols.length) {
                mLexelToColor[i] = cols[i];
                mLexelToRGBA32[i] = cols[i].toRGBA32();
            }
        }
    }

    override void loadFrom(GuiLoader loader) {
        auto node = loader.node;

        Color[] colors;
        foreach (char[] n, char[] value; node.getSubNode("colors")) {
            Color c;
            c.parse(value);
            colors ~= c;
        }
        setColors(colors);
        clear();

        super.loadFrom(loader);
    }
}
