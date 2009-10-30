module framework.drawing;

import framework.framework;

public import utils.color;
public import utils.rect2;
public import utils.vector2;

struct Vertex2i {
    //position
    Vector2i p;
    //texture coordinates, in pixels
    //xxx or would Vector2f in range 0.0f-1.0f be better?
    Vector2i t;
}

/// For drawing; the driver inherits his own class from this and overrides the
/// abstract methods.
public class Canvas {
    const int MAX_STACK = 30;

    private {
        struct State {
            Rect2i clip;                    //clip rectangle, screen coords
            Vector2i translate;             //_global_ translation offset
            Vector2i clientsize;            //scaled size of what's visible
            Vector2f scale = {1.0f, 1.0f};  //global scale factor
        }

        State[MAX_STACK] mStack;
        uint mStackTop; //point to next free stack item (i.e. 0 on empty stack)
        Rect2i mParentArea;                 //I don't know what this is
        Rect2i mVisibleArea;                //visible area in local canvas coords
    }

    ///basic per-frame setup, called by driver
    protected final void initFrame(Vector2i screen_size) {
        assert(mStackTop == 0);
        mStack[0].clientsize = screen_size;
        mStack[0].clip.p2 = mStack[0].clientsize;
    }

    ///reverse of initFrame; also called by driver
    protected final void uninitFrame() {
        assert(mStackTop == 0);
    }

    //see FrameworkDriver.getFeatures()
    public abstract int features();

    /// Normally the screen size
    final Vector2i realSize() {
        return mStack[0].clientsize;
    }

    /// Size of the drawable area (not the visible area)
    final Vector2i clientSize() {
        return mStack[mStackTop].clientsize;
    }

    /// The drawable area of the parent canvas in client coords
    /// (no visibility clipping)
    //xxx I don't know if this makes any sense
    final Rect2i parentArea() {
        return mParentArea;
    }

    /// The rectangle in client coords which is visible
    /// (right/bottom borders exclusive; with clipping)
    final Rect2i visibleArea() {
        return mVisibleArea;
    }

    /// Return true if any part of this rectangle is visible
    //public abstract bool isVisible(in Vector2i p1, in Vector2i p2);

    public void draw(Texture source, Vector2i destPos) {
        draw(source, destPos, Vector2i(0, 0), source.size);
    }

    public abstract void draw(Texture source, Vector2i destPos,
        Vector2i sourcePos, Vector2i sourceSize, bool mirrorY = false);

    /// possibly faster version of draw() (driver might override this method)
    /// right now, GL driver uses display lists for these
    /// also, just for the SDL driver, only this function can apply "effects",
    /// as in BitmapEffect
    /// if effect is null, draw normally
    void drawFast(SubSurface source, Vector2i destPos,
        bool mirrorY = false)
    {
        draw(source.surface, destPos, source.origin, source.size, mirrorY);
    }

    public abstract void drawCircle(Vector2i center, int radius, Color color);
    public abstract void drawFilledCircle(Vector2i center, int radius,
        Color color);

    /// the first and last pixels are always included
    public abstract void drawLine(Vector2i p1, Vector2i p2, Color color,
        int width = 1);

    /// the right/bottom border of the passed rectangle (Rect2i(p1, p2) for the
    /// first method) is exclusive!
    public abstract void drawRect(Vector2i p1, Vector2i p2, Color color);
    public void drawRect(Rect2i rc, Color color) {
        drawRect(rc.p1, rc.p2, color);
    }

    /// like with drawRect, bottom/right border is exclusive
    /// use Surface.fill() when the alpha channel should be copied to the
    /// destination surface (without doing alpha blending)
    public abstract void drawFilledRect(Vector2i p1, Vector2i p2, Color color);
    public void drawFilledRect(Rect2i rc, Color color) {
        drawFilledRect(rc.p1, rc.p2, color);
    }

    /// draw a vertical gradient at rc from color c1 to c2
    /// bottom/right border is exclusive
    public abstract void drawVGradient(Rect2i rc, Color c1, Color c2);

    /// draw a filled rect that shows a percentage (like a rectangular
    /// circle arc; non-accel drivers may draw it simpler)
    /// perc = 1.0 means the rectangle is fully visible
    public abstract void drawPercentRect(Vector2i p1, Vector2i p2, float perc,
        Color c);

    /// clear visible area (xxx: I hope, recheck drivers)
    public abstract void clear(Color color);

    //updates parentArea / visibleArea after translating/clipping/scaling
    private void updateAreas() {
        if (mStackTop > 0) {
            mParentArea.p1 =
                -mStack[mStackTop].translate + mStack[mStackTop - 1].translate;
            mParentArea.p1 =
                toVector2i(toVector2f(mParentArea.p1) /mStack[mStackTop].scale);
            mParentArea.p2 = mParentArea.p1 + mStack[mStackTop - 1].clientsize;
        } else {
            mParentArea.p1 = mParentArea.p2 = Vector2i(0);
        }

        mVisibleArea = mStack[mStackTop].clip - mStack[mStackTop].translate;
        mVisibleArea.p1 =
            toVector2i(toVector2f(mVisibleArea.p1) / mStack[mStackTop].scale);
        mVisibleArea.p2 =
            toVector2i(toVector2f(mVisibleArea.p2) / mStack[mStackTop].scale);
    }

    /// Set a clipping rect, and use p1 as origin (0, 0)
    final void setWindow(Vector2i p1, Vector2i p2) {
        clip(p1, p2);
        translate(p1);
        mStack[mStackTop].clientsize = p2 - p1;
        updateAreas();
    }

    /// Add translation offset, by which all coordinates are translated
    final void translate(Vector2i offset) {
        mStack[mStackTop].translate += toVector2i(toVector2f(offset)
            ^ mStack[mStackTop].scale);
        updateAreas();
        updateTranslate(offset);
    }

    //this is called from translate(); drivers can override it
    //but actually, the new translation offset is in mStack[mStackTop].translate
    //popState() also calls thus to reset the translation (that's redundant for
    //  the OpenGL driver, but needed by the SDL one)
    protected void updateTranslate(Vector2i offset) {
    }

    //set the clip rectangle (screen coordinates)
    protected abstract void updateClip(Vector2i p1, Vector2i p2);

    //set the current scale factor
    //if the driver doesn't support scaling, this is never called
    protected void updateScale(Vector2f scale) {
    }

    /// Set the cliprect (doesn't change "window" or so).
    final void clip(Vector2i p1, Vector2i p2) {
        p1 = toVector2i(toVector2f(p1) ^ mStack[mStackTop].scale);
        p2 = toVector2i(toVector2f(p2) ^ mStack[mStackTop].scale);
        p1 += mStack[mStackTop].translate;
        p2 += mStack[mStackTop].translate;
        p1 = mStack[mStackTop].clip.clip(p1);
        p2 = mStack[mStackTop].clip.clip(p2);
        mStack[mStackTop].clip = Rect2i(p1, p2);
        updateAreas();
        updateClip(p1, p2);
    }

    /// Set the factor by which all drawing will be scaled
    /// (also affects clientSize) for the current state
    /// Scale factor multiplies, absolutely and even per-state (opengl logic...)
    final void setScale(Vector2f sc) {
        if (!(features() & DriverFeatures.canvasScaling))
            return;
        updateScale(sc);
        mStack[mStackTop].clientsize =
            toVector2i(toVector2f(mStack[mStackTop].clientsize) / sc);
        mStack[mStackTop].scale = mStack[mStackTop].scale ^ sc;
        updateAreas();
    }

    /// push/pop state as set by most of the functions
    void pushState() {
        assert(mStackTop < MAX_STACK, "canvas stack overflow");

        mStack[mStackTop+1] = mStack[mStackTop];
        mStackTop++;
        updateAreas();
    }

    void popState() {
        assert(mStackTop > 0, "canvas stack underflow (incorrect nesting?)");

        Vector2i oldtrans = mStack[mStackTop].translate;

        mStackTop--;
        updateClip(mStack[mStackTop].clip.p1, mStack[mStackTop].clip.p2);
        updateAreas();

        //this silliness is just for the SDL driver
        updateTranslate(mStack[mStackTop].translate - oldtrans);
    }

    //NOTE: the quad parameter is already by ref (one of the most stupied Disms)
    public abstract void drawQuad(Surface tex, Vertex2i[4] quad);

    /// Fill the area (destPos, destPos+destSize) with source, tiled on wrap
    //will be specialized in OpenGL
    public void drawTiled(Texture source, Vector2i destPos, Vector2i destSize) {
        int w = source.size.x1;
        int h = source.size.x2;
        int x;
        Vector2i tmp;

        if (w == 0 || h == 0)
            return;

        int y = 0;
        while (y < destSize.y) {
            tmp.y = destPos.y + y;
            int resty = ((y+h) < destSize.y) ? h : destSize.y - y;
            x = 0;
            while (x < destSize.x) {
                tmp.x = destPos.x + x;
                int restx = ((x+w) < destSize.x) ? w : destSize.x - x;
                draw(source, tmp, Vector2i(0, 0), Vector2i(restx, resty));
                x += restx;
            }
            y += resty;
        }
    }

    //the line is drawn as textured rectangle between p1 and p2
    //the line is filled with tex, where tex.height is the width of the line
    //if no 3D engine is available, a line with the given fallback color is
    //drawn, the width is still taken from the texture
    public void drawTexLine(Vector2i p1, Vector2i p2, Surface tex, int offset,
        Color fallback)
    {
        if (p1 == p2)
            return;

        if (!(features() & DriverFeatures.transformedQuads)) {
            drawLine(p1, p2, fallback, tex.size.y);
            return;
        }

        auto s = tex.size();
        auto dir = toVector2f(p2)-toVector2f(p1);
        auto ndir = dir.normal;
        auto n = dir.orthogonal.normal;
        auto up = n*(s.y/2.0f);
        auto down = -n*(s.y/2.0f);
        float pos = 0;
        float len = dir.length;

        assert (s.x > 0);

        auto p1f = toVector2f(p1);

        Vertex2i[4] q;
        while (pos < len) {
            auto pnext = pos + s.x;
            if (pnext > len) {
                pnext = len;
            }

            //xxx: requires OpenGL to wrap the texture coordinate, and the
            //     texture must have an OpenGL conform size for it to work
            int offset2 = offset + cast(int)(pnext-pos);

            auto pcur = p1f + ndir*pos;
            auto pcur2 = p1f + ndir*pnext;

            q[0].p = toVector2i(pcur+up);
            q[0].t = Vector2i(offset, 0);
            q[1].p = toVector2i(pcur2+up);
            q[1].t = Vector2i(offset2, 0);
            q[2].p = toVector2i(pcur2+down);
            q[2].t = Vector2i(offset2, s.y);
            q[3].p = toVector2i(pcur+down);
            q[3].t = Vector2i(offset, s.y);

            drawQuad(tex, q);

            pos = pnext;
            offset = offset2;
        }
    }
}
