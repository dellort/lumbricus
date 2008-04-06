module common.visual;

import framework.framework;
import framework.font;
import utils.configfile : ConfigNode;
import utils.misc;
import utils.rect2;
import utils.vector2;

///draw a box with rounded corners around the specified rect
///alpha is unsupported (blame drawFilledRect) and will be ignored
///if any value from BoxProps (see below) changes, the box needs to be
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

void drawBox(Canvas c, ref Vector2i p, ref Vector2i s, ref BoxProperties props)
{
    BoxProps bp;
    bp.p = props;

    //all error checking here
    s.x = max(0, s.x);
    s.y = max(0, s.y);
    int m = min(s.x, s.y) / 2;
    bp.p.borderWidth = min(max(0, bp.p.borderWidth), m);
    bp.p.cornerRadius = min(max(0, bp.p.cornerRadius), m);

    BoxTex tex = getBox(bp);

    //size of the box quad
    int qi = max(bp.p.borderWidth, bp.p.cornerRadius);
    Vector2i q = Vector2i(qi);
    assert(tex.corners.size == q*2);
    assert(tex.sides[0].size.y == q.y*2);
    assert(tex.sides[1].size.x == q.x*2);

    //corners
    c.draw(tex.corners, p, Vector2i(0), q);
    c.draw(tex.corners, p + Vector2i(s.x - q.x, 0), Vector2i(q.x, 0), q);
    c.draw(tex.corners, p + Vector2i(0, s.y - q.y), Vector2i(0, q.y), q);
    c.draw(tex.corners, p + s - q, q, q); //tripple q lol

    //borders along X-axis
    int px = p.x + q.x;
    int ex = p.x + s.x - q.x;
    auto sx = tex.sides[0].size.x;
    while (px < ex) {
        auto w = Vector2i(min(sx, ex - px), q.y);
        c.draw(tex.sides[0], Vector2i(px, p.y), Vector2i(0), w);
        c.draw(tex.sides[0], Vector2i(px, p.y + s.y - q.y), Vector2i(0, q.y), w);
        px += w.x;
    }

    //along Y-axis, code is symmetric to above => code duplication sry
    int py = p.y + q.y;
    int ey = p.y + s.y - q.y;
    auto sy = tex.sides[1].size.y;
    while (py < ey) {
        auto h = Vector2i(q.x, min(sy, ey - py));
        c.draw(tex.sides[1], Vector2i(p.x, py), Vector2i(0), h);
        c.draw(tex.sides[1], Vector2i(p.x + s.x - q.x, py), Vector2i(q.x, 0), h);
        py += h.y;
    }

    //interrior
    c.drawFilledRect(p + q, p + s - q, props.back);
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

struct BoxProperties {
    int borderWidth = 1, cornerRadius = 5;
    Color border, back = {1,1,1};

    void loadFrom(ConfigNode node) {
        border.parse(node.getStringValue("border"));
        back.parse(node.getStringValue("back"));
        borderWidth = node.getIntValue("border_width", borderWidth);
        cornerRadius = node.getIntValue("corner_radius", cornerRadius);
    }
}

private:

//quite a hack to draw boxes with rounded borders...
struct BoxProps {
    BoxProperties p;
}

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
    static BoxTex opCall(Texture c, Texture[2] s) {
        BoxTex ret;
        ret.corners = c;
        ret.sides[] = s;
        return ret;
    }
}

BoxTex[BoxProps] boxes;

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
        t.free(true);
        rel++;
    }

    foreach (BoxTex t; boxes) {
        killtex(t.corners);
        killtex(t.sides[0]);
        killtex(t.sides[1]);
    }

    boxes = null;

    return rel;
}

BoxTex getBox(BoxProps props) {
    init();

    auto t = props in boxes;
    if (t)
        return *t;

    auto orgprops = props;

    //avoid blending in of colors which shouldn't be there
    if (props.p.borderWidth <= 0)
        props.p.border = props.p.back;

    //border color used, except for circle; circle modifies alpha scaling itself
    Color border = props.p.border;
    //hm I think the border shouldn't be blended by the background's alpha
    //border.a = border.a * props.p.back.a;

    //corners are of size q x q, side textures are also of size q in one dim.
    int q = max(props.p.borderWidth, props.p.cornerRadius);

    //border textures on the box sides

    //dir = 0 x-axis, 1 y-axis
    Texture createSide(int dir) {
        int inv = !dir;

        Vector2i size;
        size[dir] = 50; //choose as you like
        size[inv] = q*2;

        bool needAlpha = (props.p.back.a < (1.0f - Color.epsilon))
            || (props.p.border.a < (1.0f - Color.epsilon));

        auto surface = gFramework.createSurface(size,
            needAlpha ? Transparency.Alpha : Transparency.None);

        Vector2i p1 = Vector2i(0), p2 = size;
        auto bw = props.p.borderWidth;
        p1[inv] = bw;
        p2[inv] = p2[inv] - bw;

        surface.fill(Rect2i(size), border);
        surface.fill(Rect2i(p1, p2), props.p.back);

        surface.enableCaching = true;
        return surface;
    }

    Texture[2] sides; //will be BoxText.sides
    sides[0] = createSide(0);
    sides[1] = createSide(1);

    void drawCorner(Surface s) {
        s.fill(Rect2i(s.size), props.p.back);

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
            void* pixels;
            uint pitch;
            s.lockPixelsRGBA32(pixels, pitch);

            for (int y = 0; y < w*2; y++) {
                uint* line = cast(uint*)(pixels+pitch*(y+offs.y));
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
                                y + (0.5f + iy)/cGrid), c, props.p.borderWidth,
                                w - cast(float)props.p.borderWidth/2.0f);
                            if (cPos <= 0)
                                //outside or hit -> gather border color
                                colBuf += 1.0f/(cGrid * cGrid);
                            if (cPos >= 0)
                                //inside or hit -> gather opaqueness
                                aBuf += 1.0f/(cGrid * cGrid);
                        }
                    }
                    *line = Color(
                        props.p.border.r*colBuf+props.p.back.r*(1.0f-colBuf),
                        props.p.border.g*colBuf+props.p.back.g*(1.0f-colBuf),
                        props.p.border.b*colBuf+props.p.back.b*(1.0f-colBuf),
                        aBuf*(border.a*colBuf+props.p.back.a*(1.0f-colBuf)))
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
    auto corners = gFramework.createSurface(size, Transparency.Alpha);
    drawCorner(corners);

    //store struct with texture refs in hashmap
    boxes[orgprops] = BoxTex(corners, sides);
    return boxes[orgprops];
}

