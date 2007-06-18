module game.visual;

import framework.framework;
import framework.font;
import game.common;
import game.scene;
import utils.misc;

class FontLabel : SceneObjectPositioned {
    private char[] mText;
    private Font mFont;
    private Vector2i mBorder;

    this(Font font) {
        mFont = font;
        assert(font !is null);
        recalc();
    }

    private void recalc() {
        //fit size to text
        size = mFont.textSize(mText) + border * 2;
    }

    void text(char[] txt) {
        mText = txt;
        recalc();
    }
    char[] text() {
        return mText;
    }

    //(invisible!) border around text
    void border(Vector2i b) {
        mBorder = b;
        recalc();
    }
    Vector2i border() {
        return mBorder;
    }

    void draw(Canvas canvas) {
        mFont.drawText(canvas, pos+mBorder, mText);
    }
}

private class FontLabelBoxed : FontLabel {
    this(Font font) {
        super(font);
    }
    void draw(Canvas canvas) {
        drawBox(canvas, pos, size);
        super.draw(canvas);
    }
}


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
    props.borderWidth = borderWidth;
    props.cornerRadius = cornerRadius;
    props.border = border;
    props.back = back;

    BoxTex tex = getBox(props);

    c.draw(tex.left, pos);
    c.draw(tex.right, pos+size.X-tex.right.size.X);
    c.drawTiled(tex.middle, pos+tex.left.size.X,
        size.X-tex.right.size.X-tex.left.size.X+tex.middle.size.Y);
}


//quite a hack to draw boxes with rounded borders...
struct BoxProps {
    int height, borderWidth, cornerRadius;
    Color border, back;
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

BoxTex getBox(BoxProps props) {
    auto t = props in boxes;
    if (t)
        return *t;

    //create it
    //middle texture
    Vector2i size = Vector2i(10,props.height);
    auto surfMiddle = globals.framework.createSurface(size,
        DisplayFormat.Screen, Transparency.None);
    auto c = surfMiddle.startDraw();
    c.drawFilledRect(Vector2i(0),size,props.back);
    c.drawFilledRect(Vector2i(0),Vector2i(size.x,props.borderWidth),
        props.border);
    c.drawFilledRect(Vector2i(0,size.y-props.borderWidth),
        Vector2i(size.x,props.borderWidth),props.border);
    c.endDraw();
    Texture texMiddle = surfMiddle.createTexture();


    void drawSideTex(Surface s, bool right) {
        auto c = s.startDraw();
        int xs = right?s.size.x-props.borderWidth:0;
        c.drawFilledRect(Vector2i(0),s.size,props.back);
        c.drawFilledRect(Vector2i(xs, s.size.x),Vector2i(xs+props.borderWidth,
            s.size.y-s.size.x), props.border);

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
                    *line = colorToRGBA32(Color(
                        props.border.r*colBuf+props.back.r*(1.0f-colBuf),
                        props.border.g*colBuf+props.back.g*(1.0f-colBuf),
                        props.border.b*colBuf+props.back.b*(1.0f-colBuf),aBuf));
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
    int sidew = min(props.cornerRadius,props.height/2);
    size = Vector2i(sidew,props.height);

    //left texture
    auto surfLeft = globals.framework.createSurface(size,
        DisplayFormat.Screen, Transparency.Alpha);
    drawSideTex(surfLeft, false);
    Texture texLeft = surfLeft.createTexture();

    //right texture
    auto surfRight = globals.framework.createSurface(size,
        DisplayFormat.Screen, Transparency.Alpha);
    drawSideTex(surfRight, true);
    Texture texRight = surfRight.createTexture();

    //store struct with texture refs in hashmap
    boxes[props] = BoxTex(texLeft, texMiddle, texRight);
    return boxes[props];
}

