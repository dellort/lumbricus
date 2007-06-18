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

/+
  0 -- 1 -- 2
  |         |
  3   (4)   5
  |         |
  6 -- 7 -- 8
  (png files start with 1)
+/
Texture[9] boxParts;
bool boxesLoaded;

//NOTE: won't work correctly for sizes below the two corner boxes
void drawBox(Canvas c, Vector2i pos, Vector2i size) {
    BoxProps props;
    props.height = size.y;
    props.borderWidth = 2;
    props.border = Color(0,0,0,1);
    props.back = Color(1,1,1,1);

    BoxTex tex = getBox(props);

    c.draw(tex.left, pos);
    c.draw(tex.right, pos+size.X-tex.right.size.X);
    c.drawTiled(tex.middle, pos+tex.left.size.X,
        size.X-tex.right.size.X-tex.left.size.X+tex.middle.size.Y);

    /*if (!boxesLoaded) {
        for (int n = 0; n < 9; n++) {
            auto s = globals.loadGraphic("box" ~ str.toString(n+1) ~ ".png");
            s.enableAlpha();
            boxParts[n] = s.createTexture();
        }
        boxesLoaded = true;
    }
    //corners
    c.draw(boxParts[0], pos);
    c.draw(boxParts[2], pos+size.X-boxParts[2].size.X);
    c.draw(boxParts[6], pos+size.Y-boxParts[6].size.Y);
    c.draw(boxParts[8], pos+size-boxParts[8].size);
    //border lines
    c.drawTiled(boxParts[1], pos+boxParts[0].size.X,
        size.X-boxParts[2].size.X-boxParts[0].size.X+boxParts[1].size.Y);
    c.drawTiled(boxParts[3], pos+boxParts[0].size.Y,
        size.Y-boxParts[6].size.Y-boxParts[0].size.Y+boxParts[3].size.X);
    c.drawTiled(boxParts[5], pos+size.X-boxParts[8].size.X+boxParts[2].size.Y,
        size.Y-boxParts[2].size.Y-boxParts[8].size.Y+boxParts[8].size.X);
    c.drawTiled(boxParts[7], pos+size.Y-boxParts[7].size.Y+boxParts[6].size.X,
        size.X-boxParts[6].size.X-boxParts[8].size.X+boxParts[7].size.Y);
    //fill
    c.drawTiled(boxParts[4], pos+boxParts[0].size,
        size-boxParts[0].size-boxParts[8].size);*/
}


//quite a hack to draw boxes with rounded borders...
struct BoxProps {
    int height, borderWidth;
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

        bool onCircle(Vector2f p, Vector2f c, float w, float r) {
            float dist = (c-p).length;
            if (dist < r+w/2.0f && dist > r-w/2.0f)
                return true;
            return false;
        }

        const float cSamples = 1.0f;

        void drawCircle(Vector2i offs, Vector2i c, int w) {
            void* pixels;
            uint pitch;
            s.lockPixelsRGBA32(pixels, pitch);

            float colBuf;
            for (int y = 0; y < w; y++) {
                uint* line = cast(uint*)(pixels+pitch*(y+offs.y));
                line += offs.x;
                for (int x = 0; x < w; x++) {
                    colBuf = 0;
                    if (onCircle(Vector2f(x,y),toVector2f(c),props.borderWidth,
                        w-1))
                    {
                        colBuf += 1.0f;
                    }
                    *line = colorToRGBA32(props.border*(colBuf/cSamples));
                    line++;
                }
            }
            s.unlockPixels();
        }

        xs = right?0:s.size.x;
        drawCircle(Vector2i(0), Vector2i(xs,s.size.x), s.size.x);
        drawCircle(Vector2i(0,s.size.y-s.size.x), Vector2i(xs,0), s.size.x);

        c.endDraw();
    }

    int sidew = min(10,props.height/2);
    size = Vector2i(sidew,props.height);

    //left texture
    auto surfLeft = globals.framework.createSurface(size,
        DisplayFormat.Screen, Transparency.None);
    drawSideTex(surfLeft, false);
    Texture texLeft = surfLeft.createTexture();

    //right texture
    auto surfRight = globals.framework.createSurface(size,
        DisplayFormat.Screen, Transparency.None);
    drawSideTex(surfRight, true);
    Texture texRight = surfRight.createTexture();



    /*c.drawFilledRect(Vector2i(0, radius), Vector2i(1, size.y-radius), border);
    c.drawFilledRect(Vector2i(size.x-1, radius),
        Vector2i(size.x, size.y-radius), border);
    circle(radius, radius, radius,
        (int x1, int x2, int y) {
            if (y >= radius)
                y += size.y - radius*2;
            x2 += size.x - radius*2;
            auto p1 = Vector2i(x1, y);
            auto p2 = Vector2i(x2, y);
            //transparency on the side
            c.drawFilledRect(Vector2i(0, y), p1, surface.colorkey);
            c.drawFilledRect(p2, Vector2i(size.x, y), surface.colorkey);
            //circle pixels
            c.drawFilledRect(p1, p1+Vector2i(1), border);
            c.drawFilledRect(p2, p2+Vector2i(1), border);
        }
    );
    c.endDraw();*/

    boxes[props] = BoxTex(texLeft, texMiddle, texRight);
    return boxes[props];
}

