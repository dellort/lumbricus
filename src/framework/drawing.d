module framework.drawing;

import framework.framework;

import tango.math.Math : floor, ceil;
public import utils.color;
public import utils.rect2;
public import utils.vector2;
import utils.transform;
import utils.misc;

struct Vertex2f {
    //position
    Vector2f p;
    //texture coordinates, in pixels
    //xxx or would Vector2f in range 0.0f-1.0f be better?
    Vector2i t;
    //
    Color c = Color(1.0f);
}

//default values are set such that no effect is applied
struct BitmapEffect {
    bool mirrorY = false;
    float rotate = 0.0f;    //in radians
    float scale = 1.0f;     //scale factor
    //should this be a property of the SubSurface?
    Vector2i center;        //(relative, positive) center of the bitmap/rotation
    Color color = Color(1.0f);

    //fill a transform matrix based on the effect values
    //xxx: used to use ref params etc. for performance, but that caused trouble
    Transform2f getTransform(Vector2i sourceSize, Vector2i destPos) {
        Transform2f tr = void;

        if (rotate != 0f || scale != 1.0f) {
            tr = Transform2f.RotateScale(rotate, scale);
        } else {
            tr = Transform2f.init;
        }

        tr.t = toVector2f(destPos);

        //substract transformed vector to center
        tr.translate(-center);

        if (mirrorY) {
            //move bitmap by width into x direction
            tr.translateX(sourceSize.x);
            //and mirror on x axis (this is like glScale(-1,1,1))
            tr.mirror(true, false);
        }

        return tr;
    }
}

/// For drawing; the driver inherits his own class from this and overrides the
/// abstract methods.
public class Canvas {
    const int MAX_STACK = 30;

    private {
        struct State {
            Rect2i clip;            //clip rectangle, screen coords
            Vector2i translate;     //_global_ translation offset
            Vector2i clientsize;    //scaled size of what's visible
            Vector2f scale;         //global scale factor
        }

        State[MAX_STACK] mStack;
        uint mStackTop;             //point to current stack item
        //Rect2i mParentArea;       //I don't know what this is
        Rect2i mVisibleArea;        //visible area in local canvas coords
    }

    ///basic per-frame setup, called by driver
    ///also calls a first updateTransform()
    protected final void initFrame(Vector2i screen_size) {
        assert(mStackTop == 0);
        mStack[0].clientsize = screen_size;
        mStack[0].clip = Rect2i.Span(Vector2i(0), mStack[0].clientsize);
        mStack[0].translate = Vector2i(0);
        mStack[0].scale = Vector2f(1.0f);
        do_update_transform();
        updateAreas();
        pushState();
    }

    ///reverse of initFrame; also called by driver
    protected final void uninitFrame() {
        popState();
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

    /+
    /// The drawable area of the parent canvas in client coords
    /// (no visibility clipping)
    //xxx I don't know if this makes any sense
    final Rect2i parentArea() {
        return mParentArea;
    }
    +/

    /// The rectangle in client coords which is visible
    /// (right/bottom borders exclusive; with clipping)
    final Rect2i visibleArea() {
        return mVisibleArea;
    }

    final bool spriteVisible(SubSurface s, Vector2i dest, BitmapEffect* eff) {
        if (!eff) {
            return mVisibleArea.intersects(dest, dest + s.size);
        } else {
            //maybe it would be better to clip-test the transformed vertices
            //but at least for very small stuff (particles), this will be faster
            //xxx: not quite sure if this correct etc
            //m = conservative estimate of max. distance of a pixel of the
            //    sprite to the dest pos
            const cSqrt_2 = 1.42; //rounded up
            float m = max(s.size.x - eff.center.x, s.size.y - eff.center.y,
                eff.center.x, eff.center.y) * eff.scale * cSqrt_2;
            return (dest.x + m >= mVisibleArea.p1.x)
                && (dest.x - m <= mVisibleArea.p2.x)
                && (dest.y + m >= mVisibleArea.p1.y)
                && (dest.y - m <= mVisibleArea.p2.y);
        }
    }

    public void draw(Texture source, Vector2i destPos) {
        draw(source, destPos, Vector2i(0, 0), source.size);
    }

    public abstract void draw(Texture source, Vector2i destPos,
        Vector2i sourcePos, Vector2i sourceSize);

    /// more flexible version of draw()
    /// only this function can apply "effects" as in BitmapEffect
    /// if effect is null, draw normally
    abstract void drawSprite(SubSurface source, Vector2i destPos,
        BitmapEffect* effect = null);

    public abstract void drawCircle(Vector2i center, int radius, Color color);
    public abstract void drawFilledCircle(Vector2i center, int radius,
        Color color);

    /// the first and last pixels are always included
    public abstract void drawLine(Vector2i p1, Vector2i p2, Color color,
        int width = 1);

    /// the right/bottom border of the passed rectangle (Rect2i(p1, p2) for the
    /// first method) is exclusive!
    /// drivers may override this
    void drawRect(Vector2i p1, Vector2i p2, Color color) {
        if (p1.x >= p2.x || p1.y >= p2.y)
            return;
        p2.x -= 1; //border exclusive
        p2.y -= 1;
        drawLine(p1, Vector2i(p1.x, p2.y), color);
        drawLine(Vector2i(p1.x, p2.y), p2, color);
        drawLine(Vector2i(p2.x, p1.y), p2, color);
        drawLine(p1, Vector2i(p2.x, p1.y), color);
    }

    final void drawRect(Rect2i rc, Color color) {
        drawRect(rc.p1, rc.p2, color);
    }

    /// like drawRect(), but stippled lines
    void drawStippledRect(Rect2i rc, Color color) {
        drawRect(rc.p1, rc.p2, color); //default to regular line drawing
    }

    /// like with drawRect, bottom/right border is exclusive
    /// use Surface.fill() when the alpha channel should be copied to the
    /// destination surface (without doing alpha blending)
    abstract void drawFilledRect(Vector2i p1, Vector2i p2, Color color);
    final void drawFilledRect(Rect2i rc, Color color) {
        drawFilledRect(rc.p1, rc.p2, color);
    }

    /// draw a vertical gradient at rc from color c1 to c2
    /// bottom/right border is exclusive
    public abstract void drawVGradient(Rect2i rc, Color c1, Color c2);

    /// draw a filled rect that shows a percentage (like a rectangular
    /// circle arc; non-accel drivers may draw it simpler)
    /// perc = 1.0 means the rectangle is fully visible
    void drawPercentRect(Vector2i p1, Vector2i p2, float perc, Color c) {
        //some simply fall-back implementation; doesn't look like required (see
        //  OpenGL implementation for this; draw_opengl.d), but does the job
        drawFilledRect(Vector2i(p1.x,
            p2.y - cast(int)((p2.y-p1.y)*perc)), p2, c);
    }

    /// clear visible area (xxx: I hope, recheck drivers)
    public abstract void clear(Color color);

    //updates parentArea / visibleArea after translating/clipping/scaling
    private void updateAreas() {
        /+
        if (mStackTop > 0) {
            mParentArea.p1 =
                -mStack[mStackTop].translate + mStack[mStackTop - 1].translate;
            mParentArea.p1 =
                toVector2i(toVector2f(mParentArea.p1) /mStack[mStackTop].scale);
            mParentArea.p2 = mParentArea.p1 + mStack[mStackTop - 1].clientsize;
        } else {
            mParentArea.p1 = mParentArea.p2 = Vector2i(0);
        }
        +/

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
        do_update_transform();
    }

    private void do_update_transform() {
        updateTransform(mStack[mStackTop].translate, mStack[mStackTop].scale);
    }

    //update the current canvas transform; all values are global
    //first apply translation, then scaling
    //if the driver doesn't support scaling, the scale value is/should always be
    //  Vector2f(1.0f)
    protected abstract void updateTransform(Vector2i trans, Vector2f scale);

    //set the clip rectangle (screen coordinates)
    protected abstract void updateClip(Vector2i p1, Vector2i p2);

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
        mStack[mStackTop].clientsize =
            toVector2i(toVector2f(mStack[mStackTop].clientsize) / sc);
        mStack[mStackTop].scale = mStack[mStackTop].scale ^ sc;
        updateAreas();
        do_update_transform();
    }

    /// push/pop state as set by most of the functions
    final void pushState() {
        assert(mStackTop + 1 < MAX_STACK, "canvas stack overflow");

        mStack[mStackTop+1] = mStack[mStackTop];
        mStackTop++;
    }

    final void popState() {
        assert(mStackTop > 0, "canvas stack underflow (incorrect nesting?)");

        mStackTop--;
        updateClip(mStack[mStackTop].clip.p1, mStack[mStackTop].clip.p2);
        updateAreas();

        do_update_transform();
    }

    //if no 3D engine is available, nothing is drawn
    //if it is available is indicated by DriverFeatures.transformedQuads
    //NOTE: the quad parameter is already by ref (one of the most stupied Disms)
    public abstract void drawQuad(Surface tex, Vertex2f[4] quad);

    /// Fill the area (destPos, destPos+destSize) with source, tiled on wrap
    //will be specialized in OpenGL
    public void drawTiled(Texture source, Vector2i destPos, Vector2i destSize) {
        if (!visibleArea.intersects(destPos, destPos + destSize))
            return;

        int w = source.size.x1;
        int h = source.size.x2;
        int x;
        Vector2i tmp;

        if (w <= 0 || h <= 0)
            return;

        int y = 0;
        while (y < destSize.y) {
            tmp.y = destPos.y + y;
            Vector2i rest;
            rest.y = ((y+h) < destSize.y) ? h : destSize.y - y;
            //check visibility (y coordinate)
            if (tmp.y + rest.y > mVisibleArea.p1.y
                && tmp.y < mVisibleArea.p2.y)
            {
                x = 0;
                while (x < destSize.x) {
                    tmp.x = destPos.x + x;
                    rest.x = ((x+w) < destSize.x) ? w : destSize.x - x;
                    //visibility check for x coordinate
                    if (tmp.x + rest.x > mVisibleArea.p1.x
                        && tmp.x < mVisibleArea.p2.x)
                    {
                        draw(source, tmp, Vector2i(0), rest);
                    }
                    x += rest.x;
                }
            }
            y += rest.y;
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
        auto up = n*floor(s.y/2.0f);
        auto down = -n*ceil(s.y/2.0f);
        float pos = 0;
        float len = dir.length;

        assert (s.x > 0);

        auto p1f = toVector2f(p1);

        Vertex2f[4] q;
        while (pos < len) {
            auto pnext = pos + s.x;
            if (pnext > len) {
                pnext = len;
            }

            //xxx: requires OpenGL to wrap the texture coordinate, and the
            //     texture must have an OpenGL conform size for it to work
            int offset2 = offset + cast(int)(pnext-pos);

            //the offset stuff was for making the textured line "continuous"
            //  across edge points (that's why the user can pass an offset
            //  value), but that required GL_REPEAT, and never worked anyway
            //feel free to bring it back
            offset = 0;
            offset2 = s.x;

            auto pcur = p1f + ndir*pos;
            auto pcur2 = p1f + ndir*pnext;

            q[0].p = pcur+up;
            q[0].t = Vector2i(offset, 0);
            q[1].p = pcur+down;
            q[1].t = Vector2i(offset, s.y);
            q[2].p = pcur2+down;
            q[2].t = Vector2i(offset2, s.y);
            q[3].p = pcur2+up;
            q[3].t = Vector2i(offset2, 0);

            drawQuad(tex, q);

            pos = pnext;
            offset = offset2;
        }
    }
}

//helper class for drivers
//implements most of the "annoying" drawing functions using a generic Vertex
//  renderer function - as a result, these functions might be a little bit
//  slower due to the additional overhead, but they are seldomly used, and it
//  doesn't really matter
class Canvas3DHelper : Canvas {
    import tango.math.Math : PI, cos, sin, abs;

    enum Primitive {
        INVALID,
        LINES,
        LINE_STRIP,
        LINE_LOOP,
        TRIS,
        TRI_STRIP,
        TRI_FAN,
        QUADS,
    }

    private {
        //some temporary buffer, just to avoid allocating memory
        //the idea of putting this here is that you could flush the buffer
        //  transparently
        uint mBufferIndex;
        Vertex2f[100] mBuffer;
        Primitive mPrimitive;
        Surface mTexture;
        Color mColor;
    }

    //tex can be null
    protected abstract void draw_verts(Primitive primitive, Surface tex,
        Vertex2f[] verts);

    override void drawQuad(Surface tex, Vertex2f[4] quad) {
        draw_verts(Primitive.QUADS, tex, quad);
    }

    private void begin(Primitive p, Surface tex = null) {
        mPrimitive = p;
        mBufferIndex = 0;
        mTexture = null;
    }

    private void vertex(float x, float y) {
        mBuffer[mBufferIndex].p = Vector2f(x, y);
        mBuffer[mBufferIndex].t = Vector2i.init;
        mBuffer[mBufferIndex].c = mColor;
        mBufferIndex++;
    }

    private void end() {
        assert(mPrimitive != Primitive.INVALID);
        draw_verts(mPrimitive, mTexture, mBuffer[0..mBufferIndex]);
        mPrimitive = Primitive.INVALID;
        mTexture = null;
        //be nice
        mColor = Color(1.0f);
    }

    protected void lineWidth(int width) {
    }

    protected void lineStipple(bool enable) {
    }

    private int getSlices(int radius) {
        //one vertex every 30 pixels on the circumcircle
        //xxx I don't know if this makes much sense
        const cRadiusToSteps = 2*PI/30;
        return clampRangeC(cast(uint)(radius*cRadiusToSteps), 16U,
            mBuffer.length-2);
    }
    override void drawCircle(Vector2i center, int radius, Color color) {
        mColor = color;
        stroke_circle(center.x, center.y, radius, getSlices(radius));
    }

    override void drawFilledCircle(Vector2i center, int radius,
        Color color)
    {
        mColor = color;
        fill_circle(center.x, center.y, radius, getSlices(radius));
    }

    //Code from Luigi, www.dsource.org/projects/luigi, BSD license
    //Copyright (C) 2006 William V. Baxter III
    //modified to not use OpenGL (lol.)
    //Luigi begin -->
    private void fill_circle(float x, float y, float radius, int slices=16)
    {
        begin(Primitive.TRI_FAN);
        vertex(x,y);
        float astep = 2*PI/slices;
        for(int i=0; i<slices+1; i++)
        {
            float a = i*astep;
            float c = radius*cos(a);
            float s = radius*sin(a);
            vertex(x+c,y+s);
        }
        end();
    }

    private void stroke_circle(float x, float y, float radius=1, int slices=16)
    {
        begin(Primitive.LINE_LOOP);
        float astep = 2*PI/slices;
        for(int i=0; i<slices+1; i++)
        {
            float a = i*astep;
            float c = radius*cos(a);
            float s = radius*sin(a);
            vertex(c+x,s+y);
        }
        end();
    }

    private void fill_arc(float x, float y, float radius, float start,
        float radians, int slices=16)
    {
        begin(Primitive.TRI_FAN);
        vertex(x, y);
        float astep = radians/slices;
        for(int i=0; i<slices+1; i++)
        {
            float a = start+i*astep;
            float c = radius*cos(a);
            float s = -radius*sin(a);
            vertex(x+c,y+s);
        }
        end();
    }

    private void stroke_arc(float x, float y, float radius, float start,
        float radians, int slices=16)
    {
        begin(Primitive.LINE_LOOP);
        vertex(x,y);
        float astep = radians/slices;
        for(int i=0; i<slices+1; i++)
        {
            float a = start+i*astep;
            float c = radius*cos(a);
            float s = -radius*sin(a);
            vertex(x+c,y+s);
        }
        end();
    }
    //<-- Luigi end

    override void drawLine(Vector2i p1, Vector2i p2, Color color, int width = 1) {
        //and this was apparently some hack to avoid ugly lines
        //float trans = width%2==0?0f:0.5f;
        ////fixes blurry lines with GL_LINE_SMOOTH
        //glTranslatef(trans, trans, 0);

        mColor = color;

        lineWidth(width);
        begin(Primitive.LINES);
            vertex(p1.x, p1.y);
            vertex(p2.x, p2.y);
        end();
    }

    override void drawRect(Vector2i p1, Vector2i p2, Color color) {
        if (p1.x >= p2.x || p1.y >= p2.y)
            return;
        p2.x -= 1; //border exclusive
        p2.y -= 1;

        //fixes blurry lines with GL_LINE_SMOOTH
        const c = 0.5f;

        mColor = color;
        lineWidth(1);
        begin(Primitive.LINE_LOOP);
            vertex(p1.x+c, p1.y+c);
            vertex(p1.x+c, p2.y+c);
            vertex(p2.x+c, p2.y+c);
            vertex(p2.x+c, p1.y+c);
        end();
    }

    override void drawStippledRect(Rect2i rc, Color color) {
        lineStipple(true);
        drawRect(rc.p1, rc.p2, color);
        lineStipple(false);
    }

    override void drawFilledRect(Vector2i p1, Vector2i p2, Color color) {
        Color[2] c;
        c[0] = c[1] = color;
        doDrawRect(p1, p2, c);
    }

    private void doDrawRect(Vector2i p1, Vector2i p2, Color[2] c) {
        if (p1.x >= p2.x || p1.y >= p2.y)
            return;

        begin(Primitive.QUADS);
            mColor = c[0];
            vertex(p2.x, p1.y);
            vertex(p1.x, p1.y);
            mColor = c[1];
            vertex(p1.x, p2.y);
            vertex(p2.x, p2.y);
        end();
    }

    override void drawVGradient(Rect2i rc, Color c1, Color c2) {
        Color[2] c;
        c[0] = c1;
        c[1] = c2;
        doDrawRect(rc.p1, rc.p2, c);
    }

    override void drawPercentRect(Vector2i p1, Vector2i p2, float perc, Color c)
    {
        if (p1.x >= p2.x || p1.y >= p2.y)
            return;
        //0 -> nothing visible
        if (perc < float.epsilon)
            return;

        //calculate arc angle from percentage (0% is top with an angle of pi/2)
        //increasing percentage adds counter-clockwise
        //xxx what about reversing rotation?
        float a = (perc+0.25)*2*PI;
        //the "do-it-yourself" tangens (invert y -> math to screen coords)
        Vector2f av = Vector2f(cos(a)/abs(sin(a)), -sin(a)/abs(cos(a)));
        av = av.clipAbsEntries(Vector2f(1f));
        Vector2f center = toVector2f(p1+p2)/2.0f;
        //this is the arc end-point on the rectangle border
        Vector2f pOuter = center + ((0.5f*av) ^ toVector2f(p2-p1));

        void doVertices() {
            vertex(center.x, center.y);
            vertex(center.x, p1.y);
            scope(exit) vertex(pOuter.x, pOuter.y);
            //not all corners are always visible
            if (perc<0.125) return;
            vertex(p1.x, p1.y);
            if (perc<0.375) return;
            vertex(p1.x, p2.y);
            if (perc<0.625) return;
            vertex(p2.x, p2.y);
            if (perc<0.875) return;
            vertex(p2.x, p1.y);
        }

        //triangle fan is much faster than polygon
        begin(Primitive.TRI_FAN);
            mColor = c;
            doVertices();
        end();
    }
}
