module common.visual;

import framework.framework;
import framework.font;
import common.common;
import utils.configfile : ConfigNode;
import utils.misc;
import utils.rect2;
import utils.vector2;

///draw a box with rounded corners around the specified rect
///alpha is unsupported (blame drawFilledRect) and will be ignored
///if any value from BoxProps (see below) changes, the box needs to be
///redrawn (sloooow)
void drawBox(Canvas c, Vector2i pos, Vector2i size, int borderWidth = 1,
    int cornerRadius = 8, Color back = Color(1,1,1),
    Color border = Color(0,0,0))
{
    BoxProps props;
    props.height = size.y;
    props.width = size.x;
    props.p.borderWidth = borderWidth;
    props.p.cornerRadius = cornerRadius;
    props.p.border = border;
    props.p.back = back;

    BoxTex tex = getBox(props);

    c.draw(tex.left, pos);
    c.draw(tex.right, pos+size.X-tex.right.size.X);
    c.drawTiled(tex.middle, pos+tex.left.size.X,
        size.X-tex.right.size.X-tex.left.size.X+tex.middle.size.Y);
}

///same functionality as above
///sry for the code duplication
void drawBox(Canvas c, in Rect2i rect, in BoxProperties props) {
    BoxProps p;
    p.height = rect.size.y;
    p.width = rect.size.x;
    p.p = props;

    BoxTex tex = getBox(p);

    c.draw(tex.left, rect.p1);
    c.draw(tex.right, rect.p1+rect.size.X-tex.right.size.X);
    c.drawTiled(tex.middle, rect.p1+tex.left.size.X,
        rect.size.X-tex.right.size.X-tex.left.size.X+tex.middle.size.Y);
}

struct BoxProperties {
    int borderWidth = 1, cornerRadius = 5;
    Color border, back = {1,1,1};

    void loadFrom(ConfigNode node) {
        parseColor(node.getStringValue("border"), border);
        parseColor(node.getStringValue("back"), back);
        borderWidth = node.getIntValue("border_width", borderWidth);
        cornerRadius = node.getIntValue("corner_radius", cornerRadius);
    }
}

private:

//quite a hack to draw boxes with rounded borders...
struct BoxProps {
    int height, width;
    BoxProperties p;
}

struct BoxTex {
    Texture left, middle, right;
    static BoxTex opCall(Texture l, Texture m, Texture r) {
        BoxTex ret;
        ret.left = l;
        ret.middle = m;
        ret.right = r;
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
    getFramework.registerCacheReleaser(toDelegate(&releaseBoxCache));
}

int releaseBoxCache() {
    int rel;

    void killtex(Texture t) {
        t.clearCache();
        t.getSurface().free();
        rel++;
    }

    foreach (BoxTex t; boxes) {
        killtex(t.left);
        killtex(t.middle);
        killtex(t.right);
    }

    boxes = null;

    return rel;
}

BoxTex getBox(BoxProps props) {
    init();

    auto t = props in boxes;
    if (t)
        return *t;

    bool needAlpha = props.p.back.a < (1.0f - Color.epsilon);

    //border color used, except for circle; circle modifies alpha scaling itself
    //xxx doesn't really work
    Color border = props.p.border;
    border.a = border.a * props.p.back.a;

    //create it
    //middle texture
    Vector2i size = Vector2i(10,max(0, props.height));
    auto surfMiddle = globals.framework.createSurface(size,
        needAlpha ? DisplayFormat.ScreenAlpha : DisplayFormat.Screen,
        needAlpha ? Transparency.Alpha : Transparency.None);
    auto c = surfMiddle.startDraw();
    c.drawFilledRect(Vector2i(0),size,props.p.back,false);
    c.drawFilledRect(Vector2i(0),Vector2i(size.x,props.p.borderWidth),
        border,false);
    c.drawFilledRect(Vector2i(0,size.y-props.p.borderWidth),
        Vector2i(size.x,props.p.borderWidth),border,false);
    c.endDraw();
    Texture texMiddle = surfMiddle.createTexture();


    void drawSideTex(Surface s, bool right) {
        auto c = s.startDraw();
        int xs = right?s.size.x-props.p.borderWidth:0;
        c.drawFilledRect(Vector2i(0),s.size,props.p.back,false);
        c.drawFilledRect(Vector2i(xs, s.size.x),Vector2i(xs+props.p.borderWidth,
            s.size.y-s.size.x), border,false);

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

            for (int y = 0; y < w; y++) {
                uint* line = cast(uint*)(pixels+pitch*(y+offs.y));
                line += offs.x;
                for (int x = 0; x < w; x++) {
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
                    *line = colorToRGBA32(Color(
                        props.p.border.r*colBuf+props.p.back.r*(1.0f-colBuf),
                        props.p.border.g*colBuf+props.p.back.g*(1.0f-colBuf),
                        props.p.border.b*colBuf+props.p.back.b*(1.0f-colBuf),
                        aBuf*props.p.back.a));
                    line++;
                }
            }
            s.unlockPixels();
        }

        float xc = right?0:s.size.x;
        drawCircle(Vector2i(0), Vector2f(xc,s.size.x), s.size.x);
        drawCircle(Vector2i(0,s.size.y-s.size.x), Vector2f(xc,0), s.size.x);

        c.endDraw();
    }

    //width of the side textures
    int sidew = min(min(props.p.cornerRadius,props.height/2),props.width/2);
    size = Vector2i(max(0,sidew),max(0,props.height));

    Texture createSideT(bool right) {
        bool usecc = false; //!needAlpha;
        auto res = globals.framework.createSurface(size, DisplayFormat.RGBA32,
            usecc ? Transparency.Colorkey : Transparency.Alpha);
        if (usecc) {
            res.enableColorkey(Color(0,0,0,0));
        }
        drawSideTex(res, right);
        return res.createTexture();
    }

    //left texture
    Texture texLeft = createSideT(false);

    //right texture
    Texture texRight = createSideT(true);

    //store struct with texture refs in hashmap
    boxes[props] = BoxTex(texLeft, texMiddle, texRight);
    return boxes[props];
}

