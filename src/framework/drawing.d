module framework.drawing;

import framework.framework;

public import utils.color;
public import utils.rect2;
public import utils.vector2;

/// Draw stuffies!
public class Canvas {
    public abstract Vector2i realSize();
    public abstract Vector2i clientSize();

    /// offset to add to client coords to get position of the fist
    /// visible upper left point on the screen or canvas (?)
    //(returns translation relative to last setWindow())
    public abstract Vector2i clientOffset();

    /// Get the rectangle in client coords which is visible
    /// (right/bottom borders exclusive)
    public abstract Rect2i getVisible();

    /// Return true if any part of this rectangle is visible
    //public abstract bool isVisible(in Vector2i p1, in Vector2i p2);

    //must be called after drawing done
    public abstract void endDraw();

    public void draw(Texture source, Vector2i destPos) {
        draw(source, destPos, Vector2i(0, 0), source.size);
    }

    public abstract void draw(Texture source, Vector2i destPos,
        Vector2i sourcePos, Vector2i sourceSize, bool mirrorY = false);

    public abstract void drawCircle(Vector2i center, int radius, Color color);
    public abstract void drawFilledCircle(Vector2i center, int radius,
        Color color);
    public abstract void drawLine(Vector2i p1, Vector2i p2, Color color);
    public abstract void drawRect(Vector2i p1, Vector2i p2, Color color);
    /// properalpha: ignored in OpenGL mode, hack for SDL only mode :(
    public abstract void drawFilledRect(Vector2i p1, Vector2i p2, Color color,
        bool properalpha = true);

    public abstract void clear(Color color);

    /// Set a clipping rect, and use p1 as origin (0, 0)
    public abstract void setWindow(Vector2i p1, Vector2i p2);
    /// Add translation offset, by which all coordinates are translated
    public abstract void translate(Vector2i offset);
    /// Set the cliprect (doesn't change "window" or so).
    public abstract void clip(Vector2i p1, Vector2i p2);
    /// push/pop state as set by setWindow() and translate()
    public abstract void pushState();
    public abstract void popState();

    /// Fill the area (destPos, destPos+destSize) with source, tiled on wrap
    //warning: not very well tested
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
}
