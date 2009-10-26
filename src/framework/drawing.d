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

/// Draw stuffies!
public class Canvas {
    //see FrameworkDriver.getFeatures()
    public abstract int features();

    /// Normally the screen size
    public abstract Vector2i realSize();
    /// Size of the drawable area (not the visible area)
    public abstract Vector2i clientSize();

    /// The drawable area of the parent canvas in client coords
    /// (no visibility clipping)
    //xxx I don't know if this makes any sense
    public abstract Rect2i parentArea();

    /// The rectangle in client coords which is visible
    /// (right/bottom borders exclusive; with clipping)
    public abstract Rect2i visibleArea();

    /// Return true if any part of this rectangle is visible
    //public abstract bool isVisible(in Vector2i p1, in Vector2i p2);

    //must be called after drawing done
    public abstract void endDraw();

    public void draw(Texture source, Vector2i destPos) {
        draw(source, destPos, Vector2i(0, 0), source.size);
    }

    public abstract void draw(Texture source, Vector2i destPos,
        Vector2i sourcePos, Vector2i sourceSize, bool mirrorY = false);

    /// possibly faster version of draw() (driver might override this method)
    /// right now, GL driver uses display lists for these
    void drawFast(SubSurface source, Vector2i destPos, bool mirrorY = false) {
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

    public abstract void clear(Color color);

    /// Set a clipping rect, and use p1 as origin (0, 0)
    public abstract void setWindow(Vector2i p1, Vector2i p2);
    /// Add translation offset, by which all coordinates are translated
    public abstract void translate(Vector2i offset);
    /// Set the cliprect (doesn't change "window" or so).
    public abstract void clip(Vector2i p1, Vector2i p2);
    /// Set the factor by which all drawing will be scaled
    /// (also affects clientSize) for the current state
    /// Scale factor multiplies, absolutely and even per-state (opengl logic...)
    public abstract void setScale(Vector2f sc);

    /// push/pop state as set by setWindow() and translate()
    public abstract void pushState();
    public abstract void popState();

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
