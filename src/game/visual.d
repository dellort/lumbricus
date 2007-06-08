module game.visual;

import framework.framework;
import framework.font;
import game.common;
import game.scene;

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

    void draw(Canvas canvas, SceneView parentView) {
        mFont.drawText(canvas, pos+mBorder, mText);
    }
}

private class FontLabelBoxed : FontLabel {
    this(Font font) {
        super(font);
    }
    void draw(Canvas canvas, SceneView parentView) {
        drawBox(canvas, pos, size);
        super.draw(canvas, parentView);
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
    if (!boxesLoaded) {
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
        size-boxParts[0].size-boxParts[8].size);
}

/+
//quite a hack to draw boxes with rounded borders...
struct BoxProps {
    Vector2i size;
    Color border, back;
}

Texture[BoxProps] boxes;

import utils.drawing;

Texture getBox(Vector2i size, Color border, Color back) {
    BoxProps box;
    box.size = size; box.border = border; box.back = back;
    auto t = box in boxes;
    if (t)
        return *t;
    //create it
    auto surface = globals.framework.createSurface(size, DisplayFormat.Screen,
        Transparency.None);
    auto c = surface.startDraw();
    c.drawFilledRect(Vector2i(0),size,back);
    int radius = 20;
    c.drawFilledRect(Vector2i(0, radius), Vector2i(1, size.y-radius), border);
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
    c.endDraw();
    boxes[box] = surface.createTexture();
    return boxes[box];
}
+/
