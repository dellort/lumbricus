module game.gui.levelpaint;

import framework.framework;
import framework.i18n;
import common.task;
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

import str = std.string;

private uint rgba32(Color c) {
    return (cast(ubyte)(255*c.a)<<24) | (cast(ubyte)(255*c.b)<<16)
        | (cast(ubyte)(255*c.g)<<8) | (cast(ubyte)(255*c.r));
}

class PainterWidget : Widget {
    Lexel[] levelData;

    private {
        Surface mImage;

        const cPaintScale = 0.33;
        //CTFE ftw
        const Color[3] cLexelToColor = [Color(0.2, 0.2, 1.0),
            Color(1, 1, 1), Color(0, 0, 0)];
        const uint[3] cLexelToRGBA32 = [rgba32(cLexelToColor[0]),
            rgba32(cLexelToColor[1]), rgba32(cLexelToColor[2])];
        const cPenRadius = [10, 75];
        const cPenChange = 5;

        Vector2i mLevelSize = Vector2i(2000, 700);
        Rect2i mLevelRect;
        Lexel mPaintMode = Lexel.INVALID;
        int mPenRadius = 30;
        Lexel[] mScaledLevel;
        Vector2i mMouseLast;
    }

    this() {
        auto drawSize = toVector2i(toVector2f(mLevelSize)*cPaintScale);
        mImage = gFramework.createSurface(drawSize, Transparency.None, Color(0));
        mLevelRect.p2 = mLevelSize;
        mScaledLevel = new Lexel[drawSize.x*drawSize.y];

        levelData = new Lexel[mLevelSize.x*mLevelSize.y];
        fill(Lexel.Null);
    }

    this(LandscapeBitmap level) {
        mLevelSize = level.size;
        auto drawSize = toVector2i(toVector2f(mLevelSize)*cPaintScale);
        mImage = gFramework.createSurface(drawSize, Transparency.None, Color(0));
        mLevelRect.p2 = mLevelSize;
        mScaledLevel = new Lexel[drawSize.x*drawSize.y];

        levelData = level.levelData.dup;
        fullUpdate();
    }

    override bool canHaveFocus() {
        return true;
    }
    override bool greedyFocus() {
        return true;
    }

    protected void onDraw(Canvas c) {
        c.draw(mImage, Vector2i(0, 0));
    }

    private bool onKeyDown(char[] bind, KeyInfo infos) {
        if (infos.code == Keycode.MOUSE_LEFT) {
            mPaintMode = Lexel.SolidSoft;
            paintAtMouse(true);
            return true;
        }
        if (infos.code == Keycode.MOUSE_MIDDLE) {
            mPaintMode = Lexel.SolidHard;
            paintAtMouse(true);
            return true;
        }
        if (infos.code == Keycode.MOUSE_RIGHT) {
            mPaintMode = Lexel.Null;
            paintAtMouse(true);
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
            mPaintMode = Lexel.INVALID;
            return true;
        }
        return false;
    }

    override protected void onKeyEvent(KeyInfo ki) {
        auto b = findBind(ki);
        (ki.isDown && onKeyDown(b, ki))
            || (ki.isUp && onKeyUp(b, ki));
    }

    override void onMouseMove(MouseInfo info) {
        if (mPaintMode != Lexel.INVALID) {
            paintAtMouse();
        }
    }

    private void paintAtMouse(bool clicked = false) {
        Vector2i levelPos = Vector2i(
            cast(int)(mLevelSize.x*(cast(float)mousePos.x)/mImage.size.x),
            cast(int)(mLevelSize.y*(cast(float)mousePos.y)/mImage.size.y));
        if (clicked)
            mMouseLast = levelPos;
        doPaint(mMouseLast, levelPos);
        mMouseLast = levelPos;
    }

    //called with absolute position in final level (0, 0)-mLevelSize
    //draw a line from p1 to p2, using mPaintMode and mPenRadius
    private void doPaint(Vector2i p1, Vector2i p2) {
        assert(mPaintMode >= 0 && mPaintMode < 3);

        void drawThickLine(Vector2i p1, Vector2i p2, int radius, Vector2i size,
            void delegate(int x1, int x2, int y) dg)
        {
            drawing.circle(p1.x, p1.y, radius, dg);
            if (p1 != p2) {
                drawing.circle(p2.x, p2.y, radius, dg);
                Vector2f[4] poly;
                Vector2f line_o = toVector2f(p2-p1).orthogonal.normal;
                poly[0] = toVector2f(p1)-line_o*radius;
                poly[1] = toVector2f(p1)+line_o*radius;
                poly[2] = toVector2f(p2)+line_o*radius;
                poly[3] = toVector2f(p2)-line_o*radius;
                rasterizePolygon(size.x, size.y, poly, false, dg);
            }
        }

        //draw into final level
        void scanline(int x1, int x2, int y) {
            if (y < 0 || y >= mLevelSize.y) return;
            if (x1 < 0) x1 = 0;
            if (x2 >= mLevelSize.x) x2 = mLevelSize.x-1;
            int ly = y*mLevelSize.x;
            for (int x = x1; x <= x2; x++) {
                levelData[ly+x] = mPaintMode;
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
                mScaledLevel[ly+x] = mPaintMode;
                *dstptr = cLexelToRGBA32[mPaintMode];
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
    }

    //fill the whole level with l
    private void fill(Lexel l) {
        assert(l != Lexel.INVALID);
        levelData[] = l;
        //this should be faster than calling fullUpdate()
        mScaledLevel[] = l;
        mImage.fill(mImage.rect, cLexelToColor[l]);
    }

    void fillSolidSoft() {
        fill(Lexel.SolidSoft);
    }

    void clear() {
        fill(Lexel.Null);
    }

    //refresh the whole scaled lexel cache and image (e.g. after clearing,
    //   or loading an existing level)
    //xxx this is quite slow
    private void fullUpdate() {
        assert(mScaledLevel.length == mImage.size.x*mImage.size.y);
        assert(levelData.length == mLevelSize.x*mLevelSize.y);

        //scale down from full size to image size
        mScaledLevel[] = Lexel.Null;
        for (int y = 0; y < mLevelSize.y; y++) {
            int ly = y*mLevelSize.x;
            int py = cast(int)(y*cPaintScale)*mImage.size.x;
            for (int x = 0; x < mLevelSize.x; x++) {
                Lexel cur = levelData[ly+x];
                int px = cast(int)(x*cPaintScale);
                mScaledLevel[py+px] = max(mScaledLevel[py+px],cur);
            }
        }

        //transfer lexel data to image
        void* pixels; uint pitch;
        mImage.lockPixelsRGBA32(pixels, pitch);
        for (int y = 0; y < mImage.size.y; y++) {
            uint* dstptr = cast(uint*)(pixels+pitch*y);
            int lsrc = y*mImage.size.x;
            for (int x = 0; x < mImage.size.x; x++) {
                uint col = cLexelToRGBA32[mScaledLevel[lsrc+x]];
                *dstptr = col;
                dstptr++;
            }
        }
        mImage.unlockPixels(Rect2i.init);
    }

    override Vector2i layoutSizeRequest() {
        return mImage.size;
    }
}

class LevelPaintTask : Task {
    private {
        PainterWidget mPainter;
        Window mWindow;
    }

    this(TaskManager tm) {
        super(tm);

        mPainter = new PainterWidget();

        mWindow = gWindowManager.createWindow(this, mPainter,
            _("levelpaint.caption"));
    }

    static this() {
        TaskFactory.register!(typeof(this))("levelpaint");
    }
}
