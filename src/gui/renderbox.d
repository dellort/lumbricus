//actually independent from GUI
module gui.renderbox;

import framework.framework;
import utils.configfile;
import utils.misc;
import utils.rect2;
import utils.vector2;
import math = tango.math.Math;

struct BoxProperties {
    int borderWidth = 1, cornerRadius = 5;
    Color border, back = {1,1,1}, bevel = {0.5,0.5,0.5};
    bool drawBevel = false; //bevel = other color for left/top sides
    bool noRoundedCorners = false; //use normal line drawing => no cache needed
    //if false, disable drawing - possibly makes user code simpler
    bool enabled = true;

    void loadFrom(ConfigNode node) {
        border = node.getValue("border", border);
        back = node.getValue("back", back);
        bevel = node.getValue("bevel", bevel);
        borderWidth = node.getIntValue("border_width", borderWidth);
        cornerRadius = node.getIntValue("corner_radius", cornerRadius);
        drawBevel = node.getValue("drawBevel", drawBevel);
    }

    //whatever this is; return a border width that's useful to fit a rectangle
    //  inside the box (that doesn't intersect with the border)
    int effectiveBorderWidth() {
        return borderWidth + cornerRadius/3;
        //would be better, but messes up GUI
        //return max(borderWidth, cornerRadius);
    }
}

///draw a box with rounded corners around the specified rect
///alpha is unsupported (blame drawFilledRect) and will be ignored
///if any value from BoxProperties (see below) changes, the box needs to be
///redrawn (sloooow)
void drawBox(Canvas c, Vector2i pos, Vector2i size, int borderWidth = 1,
    int cornerRadius = 5, Color back = Color(1,1,1),
    Color border = Color(0,0,0))
{
    BoxProperties props;
    props.borderWidth = borderWidth;
    props.cornerRadius = cornerRadius;
    props.border = border;
    props.back = back;

    drawBox(c, pos, size, props);
}

void drawBox(Canvas c, in Rect2i rect, in BoxProperties props) {
    drawBox(c, rect.p1, rect.size, props);
}

void drawBox(Canvas c, Vector2i p, Vector2i s, BoxProperties props) {
    if (!props.enabled)
        return;

    //all error checking here
    s.x = max(0, s.x);
    s.y = max(0, s.y);
    int m = min(s.x, s.y) / 2;
    props.borderWidth = min(max(0, props.borderWidth), m);
    props.cornerRadius = min(max(0, props.cornerRadius), m);

    if (props.noRoundedCorners) {
        drawSimpleBox(c, Rect2i.Span(p, s), props);
        return;
    }

    if (props.cornerRadius == 0 && props.borderWidth == 0) {
        c.drawFilledRect(Rect2i.Span(p, s), props.back);
        return;
    }

    BoxTex tex = getBox(props);

    //size of the box quad
    int qi = max(props.borderWidth, props.cornerRadius);
    Vector2i q = Vector2i(qi);
    assert(tex.corners.size == q*2);
    assert(tex.sides[0].size.y == q.y*2);
    assert(tex.sides[1].size.x == q.x*2);

    //corners
    void corner(Vector2i dst_offs, Vector2i src_offs) {
        c.drawPart(tex.corners, p + dst_offs, src_offs, q);
    }
    corner(Vector2i(0), Vector2i(0));
    corner(Vector2i(s.x - q.x, 0), Vector2i(q.x, 0));
    corner(Vector2i(0, s.y - q.y), Vector2i(0, q.y));
    corner(s - q, q);

    //borders along X-axis
    int px = p.x + q.x;
    int ex = p.x + s.x - q.x;
    auto sx = tex.sides[0].size.x;
    while (px < ex) {
        auto w = Vector2i(min(sx, ex - px), q.y);
        auto curTex = tex.sides[0];
        c.drawPart(curTex, Vector2i(px, p.y + s.y - q.y), Vector2i(0, q.y), w);
        if (props.drawBevel)
            curTex = tex.bevelSides[0];
        c.drawPart(curTex, Vector2i(px, p.y), Vector2i(0), w);
        px += w.x;
    }

    //along Y-axis, code is symmetric to above => code duplication sry
    int py = p.y + q.y;
    int ey = p.y + s.y - q.y;
    auto sy = tex.sides[1].size.y;
    while (py < ey) {
        auto h = Vector2i(q.x, min(sy, ey - py));
        auto curTex = tex.sides[1];
        c.drawPart(curTex, Vector2i(p.x + s.x - q.x, py), Vector2i(q.x, 0), h);
        if (props.drawBevel)
            curTex = tex.bevelSides[1];
        c.drawPart(curTex, Vector2i(p.x, py), Vector2i(0), h);
        py += h.y;
    }

    //interior
    c.drawFilledRect(Rect2i(p + q, p + s - q), props.back);
}

//no rounded corners + doesn't need a cache
void drawSimpleBox(Canvas c, Rect2i rc, BoxProperties props) {
    if (!props.enabled)
        return;

    if (props.back.a > 0) {
        auto rc2 = rc;
        auto b = Vector2i(props.borderWidth);
        rc2.p1 += b;
        rc2.p2 -= b;
        c.drawFilledRect(rc2, props.back);
    }

    if (props.borderWidth > 0 && props.border.a > 0) {
        c.drawRect(rc, props.border, props.borderWidth);
    }
}

///draw a circle with its center at the specified position
///props.cornerRadius is the radius of the circle to be drawn
void drawCircle(Canvas c, Vector2i pos, BoxProperties props) {
    Vector2i p1, p2;
    auto d = Vector2i(props.cornerRadius);
    p1 = pos - d;
    //NOTE: could speed up drawing by not trying to draw the side textures and
    //  the interior; add special cases to drawBox if this becomes important
    //  (only tex.corners had to be drawn once, since it shows already a circle)
    drawBox(c, p1, d*2, props);
}

private:

//quite a hack to draw boxes with rounded borders...
struct BoxTex {
    //corners: quadratic bitmap which looks like
    //         | left-top    |    right-top |
    //         | left-bottom | right-bottom |
    //this is actually simply a circle, which is used by drawCircle
    Texture corners;
    //sides[0]: | top x-axis    |
    //          | bottom x-axis |
    //sides[1]: | left y-axis | right y-axis |
    Texture[2] sides;
    //same as above, just a different color
    Texture[2] bevelSides;
    static BoxTex opCall(Texture c, Texture[2] s, Texture[2] b = [null, null]) {
        BoxTex ret;
        ret.corners = c;
        ret.sides[] = s;
        ret.bevelSides[] = b;
        return ret;
    }
}

BoxTex[BoxProperties] boxes;

//xxx: maybe introduce a global on-framework-creation callback registry for
//     these cases? currently init() is simply called in getBox().
bool didInit;

void init() {
    if (didInit)
        return;
    didInit = true;
    gFramework.registerCacheReleaser(toDelegate(&releaseBoxCache));
}

int releaseBoxCache() {
    int rel;

    void killtex(Texture t) {
        if (t) {
            t.free();
            rel++;
        }
    }

    foreach (BoxTex t; boxes) {
        killtex(t.corners);
        killtex(t.sides[0]);
        killtex(t.sides[1]);
        killtex(t.bevelSides[0]);
        killtex(t.bevelSides[1]);
    }

    boxes = null;

    return rel;
}

BoxTex getBox(BoxProperties props) {
    init();

    auto t = props in boxes;
    if (t)
        return *t;

    auto orgprops = props;

    //avoid blending in of colors which shouldn't be there
    if (props.borderWidth <= 0)
        props.border = props.back;

    //border color used, except for circle; circle modifies alpha scaling itself
    Color border = props.border;
    //hm I think the border shouldn't be blended by the background's alpha
    //border.a = border.a * props.back.a;

    //corners are of size q x q, side textures are also of size q in one dim.
    int q = max(props.borderWidth, props.cornerRadius);

    //border textures on the box sides

    //dir = 0 x-axis, 1 y-axis
    Texture createSide(int dir, Color sideFore) {
        int inv = !dir;

        Vector2i size;
        size[dir] = 50; //choose as you like
        size[inv] = q*2;

        bool needAlpha = (props.back.a < (1.0f - Color.epsilon))
            || (sideFore.a < (1.0f - Color.epsilon));

        auto surface = new Surface(size,
            needAlpha ? Transparency.Alpha : Transparency.None);

        Vector2i p1 = Vector2i(0), p2 = size;
        auto bw = props.borderWidth;
        p1[inv] = bw;
        p2[inv] = p2[inv] - bw;

        surface.fill(Rect2i(size), sideFore);
        surface.fill(Rect2i(p1, p2), props.back);

        surface.enableCaching = true;
        return surface;
    }

    Texture[2] sides; //will be BoxText.sides
    sides[0] = createSide(0, props.border);
    sides[1] = createSide(1, props.border);
    Texture[2] bevelSides;
    if (props.drawBevel) {
        bevelSides[0] = createSide(0, props.bevel);
        bevelSides[1] = createSide(1, props.bevel);
    }

    void drawCorner(Surface s) {
        s.fill(Rect2i(s.size), props.back);

        //simple distance test, quite expensive though
        //-1 if outside, 0 if hit, 1 if inside
        int onCircle(Vector2f p, Vector2f c, float w, float r) {
            float dist = (c-p).length;
            if (dist < r-w/2.0f)
                return 1;
            else if (dist > r+w/2.0f)
                return -1;
            return 0;
        }

        //resolution of the AA grid (will do cGrid*cGrid samples)
        const int cGrid = 4;

        //draw a circle inside a w x w rect with center c and radius w
        //offset the result by offs
        void drawCircle(Vector2i offs, Vector2f c, int w) {
            Color.RGBA32* pixels;
            uint pitch;
            s.lockPixelsRGBA32(pixels, pitch);

            for (int y = 0; y < w*2; y++) {
                auto line = pixels+pitch*(y+offs.y);
                line += offs.x;
                for (int x = 0; x < w*2; x++) {
                    assert(x < s.size.x);
                    assert(y < s.size.y);
                    //accumulate color and alpha value
                    float colBuf = 0, aBuf = 0;
                    //do multiple regular grid samples for AA
                    for (int iy = 0; iy < cGrid; iy++) {
                        for (int ix = 0; ix < cGrid; ix++) {
                            //get the pos of the current sample to the
                            //circle to draw
                            int cPos = onCircle(Vector2f(x + (0.5f + ix)/cGrid,
                                y + (0.5f + iy)/cGrid), c, props.borderWidth,
                                w - cast(float)props.borderWidth/2.0f);
                            if (cPos <= 0)
                                //outside or hit -> gather border color
                                colBuf += 1.0f/(cGrid * cGrid);
                            if (cPos >= 0)
                                //inside or hit -> gather opaqueness
                                aBuf += 1.0f/(cGrid * cGrid);
                        }
                    }
                    Color fore = props.border;
                    if (props.drawBevel) {
                        //on beveled drawing, the left/top corners show a
                        //different color than right/bottom, with fadeover
                        //float perc = clampRangeC(((x+y)
                        //    / (4.0f*w) - 0.25f) * 2.0f, 0f, 1f);
                        //changed drawing code for thick borders
                        //not sure if this is "correct" or completely idiotic
                        float pf = 1.0f*(x-w)/w;
                        float pb = 1.0f*(y-w)/w;
                        float perc = math.atan2(pf, pb)/(math.PI/2) + 1.0;
                        if (perc > 1.0f)
                            perc = 3.0f - perc;
                        perc = clampRangeC(perc, 0f, 1f);
                        fore = fore * perc + props.bevel * (1.0f - perc);
                    }
                    *line = Color(
                        fore.r*colBuf+props.back.r*(1.0f-colBuf),
                        fore.g*colBuf+props.back.g*(1.0f-colBuf),
                        fore.b*colBuf+props.back.b*(1.0f-colBuf),
                        aBuf*(fore.a*colBuf+props.back.a*(1.0f-colBuf)))
                            .toRGBA32();
                    line++;
                }
            }

            s.unlockPixels(Rect2i(Vector2i(0), s.size));
        }

        drawCircle(Vector2i(0), Vector2f(q,q), q);

        s.enableCaching = true;
    }

    auto size = Vector2i(q)*2;
    auto corners = new Surface(size, Transparency.Alpha);
    drawCorner(corners);

    //store struct with texture refs in hashmap
    boxes[orgprops] = BoxTex(corners, sides, bevelSides);
    return boxes[orgprops];
}
