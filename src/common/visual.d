module common.visual;

import framework.framework;
import framework.font;
import utils.configfile : ConfigNode;
import utils.misc;
import utils.rect2;
import utils.vector2;
import time = utils.time;
import strparser = utils.strparser;
import str = utils.string;
import framework.i18n;

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
        auto curTex = tex.sides[0];
        c.draw(curTex, Vector2i(px, p.y + s.y - q.y), Vector2i(0, q.y), w);
        if (bp.p.drawBevel)
            curTex = tex.bevelSides[0];
        c.draw(curTex, Vector2i(px, p.y), Vector2i(0), w);
        px += w.x;
    }

    //along Y-axis, code is symmetric to above => code duplication sry
    int py = p.y + q.y;
    int ey = p.y + s.y - q.y;
    auto sy = tex.sides[1].size.y;
    while (py < ey) {
        auto h = Vector2i(q.x, min(sy, ey - py));
        auto curTex = tex.sides[1];
        c.draw(curTex, Vector2i(p.x + s.x - q.x, py), Vector2i(q.x, 0), h);
        if (bp.p.drawBevel)
            curTex = tex.bevelSides[1];
        c.draw(curTex, Vector2i(p.x, py), Vector2i(0), h);
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
    Color border, back = {1,1,1}, bevel = {0.5,0.5,0.5};
    bool drawBevel = false; //bevel = other color for left/top sides

    void loadFrom(ConfigNode node) {
        border = node.getValue("border", border);
        back = node.getValue("back", back);
        bevel = node.getValue("bevel", bevel);
        borderWidth = node.getIntValue("border_width", borderWidth);
        cornerRadius = node.getIntValue("corner_radius", cornerRadius);
        drawBevel = node.getValue("drawBevel", drawBevel);
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
    Texture createSide(int dir, Color sideFore) {
        int inv = !dir;

        Vector2i size;
        size[dir] = 50; //choose as you like
        size[inv] = q*2;

        bool needAlpha = (props.p.back.a < (1.0f - Color.epsilon))
            || (sideFore.a < (1.0f - Color.epsilon));

        auto surface = gFramework.createSurface(size,
            needAlpha ? Transparency.Alpha : Transparency.None);

        Vector2i p1 = Vector2i(0), p2 = size;
        auto bw = props.p.borderWidth;
        p1[inv] = bw;
        p2[inv] = p2[inv] - bw;

        surface.fill(Rect2i(size), sideFore);
        surface.fill(Rect2i(p1, p2), props.p.back);

        surface.enableCaching = true;
        return surface;
    }

    Texture[2] sides; //will be BoxText.sides
    sides[0] = createSide(0, props.p.border);
    sides[1] = createSide(1, props.p.border);
    Texture[2] bevelSides;
    if (props.p.drawBevel) {
        bevelSides[0] = createSide(0, props.p.bevel);
        bevelSides[1] = createSide(1, props.p.bevel);
    }

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
                    Color fore = props.p.border;
                    if (props.p.drawBevel) {
                        //on beveled drawing, the left/top corners show a
                        //different color than right/bottom, with fadeover
                        float perc = clampRangeC(((x+y)
                            / (4.0f*w) - 0.25f) * 2.0f, 0f, 1f);
                        fore = fore * perc + props.p.bevel * (1.0f - perc);
                    }
                    *line = Color(
                        fore.r*colBuf+props.p.back.r*(1.0f-colBuf),
                        fore.g*colBuf+props.p.back.g*(1.0f-colBuf),
                        fore.b*colBuf+props.p.back.b*(1.0f-colBuf),
                        aBuf*(fore.a*colBuf+props.p.back.a*(1.0f-colBuf)))
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
    boxes[orgprops] = BoxTex(corners, sides, bevelSides);
    return boxes[orgprops];
}

/++
 + Parses a string like
 +  Foo\c(ff0000)Bar\rBlub,
 + stores the result and draws it to a Canvas
 + the string can contain line breaks (then the text has... multiple line)
 + parse errors insert error messages into the rendered text
 + xxx it would be good, if the parser wouldn't need to know about the commands,
 +     right now, to parse "bla\bbla", you obviously need to know that \b is a
 +     command, and that it stops right before the second "bla".
 + xxx slightly duplicated functionality with GUI styles
 + commands:
 +  \c(color-spec)
 +    Text is painted in this color, until something else changes the color
 +    again. For color-spec see Color.parse().
 +  \back(color-spec)
 +    Like \c, but set back color.
 +  \b \i \u
 +    Set bold, italic, underline to true.
 +  \s(size-spec)
 +    Set font size. size-spec is <signed integer> ['%']. % means relative size.
 +    e.g. "\s(16)Text in 16pt. \s(-10%)Now 10% smaller."
 +  \border-width(size-spec)  \border-color(color-spec)
 +    border_width and border_color.
 +  \r
 +    Reset the font to the previous style.
 +    If there was a \{, set style as if you'd do \} (but without poping stack)
 +    If the stack is empty, set to default font.
 +  \{  \}
 +    Push/pop the font style to the stack.
 +    e.g. "\{\c(red)This is red.\}This not."
 +    (oh god, maybe we should just use Tango's XML parser.)
 +    (or use { } directly?)
 +  \\
 +    Output a \
 +  \n
 +    Output a line break. (But the string can contain raw line breaks, too.)
 +  \t(text)
 +    Translate the text using i18n stuff. No parameters yet...
 +    Resulting translation is included literally.
 +  \lit<char>text<char>
 +    Include the text included between the given char as literal.
 +    e.g. "\lit+I'm \bliteral!+" the \b tag isn't parsed.
 +  \blink
 +    Annoy the user.
 + Extension ideas: (not implemented!)
 +  \image(ref)
 +    Include the referenced image (either a resource, or added by the user)
 +  \include(ref)  \literal-include(ref)
 +    User can set external text by ColoredText.setRef(123, "text"), and this
 +    gets parsed (or included literally without parsing.)
 +  Refs for \t, including params, a la \t(ref, ref2, ref3)
 +  Optionally parse translated text with formatting tags.
 +
 + Historical note: we had something like this once here; then I decided to move
 + all text rendering stuff into gui/label.d. Now it's here again, and if \image
 + gets implemented, label.d will be only a wrapper for this... LOL
 +/
public class FormattedText {
    private {
        struct Style {
            Font font;
            bool blink;
        }
        struct Part {
            Style style;
            Vector2i pos, size;
            char[] text;
            bool newline; //this Part starts a new line
        }
        char[] mText;
        bool mTextIsFormatted; //mText; false: setLiteral(), true: setMarkup()
        Translator mTranslator;
        Style mRootStyle; //style at start
        Part[] mParts;
        Vector2i mSize;
        //only during parsing
        Style[] mStyleStack; //[$-1] contains current style, assert(length > 0)
    }

    this() {
        mRootStyle.font = gFramework.fontManager.loadFont("default");
        mTranslator = localeRoot();
    }

    /+void opAssign(char[] txt) {
        setMarkup(txt);
    }+/

    void font(Font f) {
        assert(!!f);
        mRootStyle.font = f;
        update();
    }
    Font font() {
        return mRootStyle.font;
    }

    //clear text
    void clear() {
        setLiteral("");
    }

    //retranslate / restlye / internal reparse
    void update() {
        auto tmp = mText;
        //clear => defeat change detection (although that isn't implemented yet)
        mText = null;
        if (mTextIsFormatted) {
            setMarkup(tmp);
        } else {
            setLiteral(tmp);
        }
    }

    private void doInit() {
        mStyleStack.length = 1;
        mStyleStack[0] = mRootStyle;
        mParts.length = 1;
        mParts[0].style = mStyleStack[0];
        mParts[0].text = null;
    }

    //call this after you change the current style
    //(the current style is in mStylesStack[$-1])
    //also can be used to simply start a new Part
    private void stylechange() {
        mParts.length = mParts.length + 1;
        mParts[$-1].style = mStyleStack[$-1];
    }

    //utf-8 and line breaks
    private void parseLiteral(char[] txt) {
        while (txt.length) {
            char[][] breaks = str.split2(txt, '\n');
            mParts[$-1].text ~= breaks[0];
            txt = null;
            if (breaks[1].length) {
                stylechange();
                mParts[$-1].newline = true;
                txt = breaks[1][1..$];
            }
        }
    }

    //parse a command (without the \), and return all text following it
    private char[] parseCmd(char[] txt) {
        //--- parser helpers

        void error(char[] msg) {
            //hmmm
            Part pmsg;
            pmsg.style.font = gFramework.fontManager.loadFont("txt_error");
            pmsg.text = "[" ~ msg ~ "]";
            mParts ~= pmsg;
            stylechange(); //following text has not error style
        }

        bool tryeat(char[] t) {
            return str.eatStart(txt, t);
        }

        bool readdelim(ref char[] res, char delim) {
            auto stuff = str.split2(txt, delim);
            if (!stuff[1].length) {
                error("'" ~ delim ~ "' not found");
                return false;
            }
            res = stuff[0];
            txt = stuff[1][1..$];
            return true;
        }

        bool readbracket(ref char[] res) {
            if (!tryeat("(")) {
                error("'(' expected");
                return false;
            }
            return readdelim(res, ')');
        }

        //color argument, "(color-spec)"
        bool readcolor(ref Color c) {
            char[] t;
            if (!readbracket(t))
                return false;
            try {
                c = Color.fromString(t, c);
                return true;
            } catch (ConversionException e) {
            }
            error("color");
            return false;
        }

        //size argument, '(' <int> ['%'] ')'
        //if the value is relative (with %), value is used to get the new value
        bool readrelint(ref int value) {
            char[] t;
            if (!readbracket(t))
                return false;
            char[][] stuff = str.split(t);
            if (!stuff.length || stuff.length > 2) {
                error("size expected");
                return false;
            }
            int val;
            try {
                val = strparser.fromStr!(int)(stuff[0]);
            } catch (strparser.ConversionException e) {
                error("size 1");
                return false;
            }
            if (stuff.length == 2) {
                if (stuff[1] != "%") {
                    error("size 2");
                    return false;
                }
                val = cast(int)((100+val)/100.0f * value);
            }
            value = val;
            return true;
        }

        //--- helpers for setting styles

        FontProperties getfont() {
            return mStyleStack[$-1].font.properties;
        }
        void setfont(FontProperties p) {
            mStyleStack[$-1].font = new Font(p);
            stylechange();
        }

        //--- actual parser & "interpreter"

        //(be sure to put longer commands before shorter ones if ambiguous,
        // like "back" - "b")
        if (tryeat("\\")) {
            parseLiteral("\\");
        } else if (tryeat("n")) {
            parseLiteral("\n");
        } else if (tryeat("lit")) {
            if (!txt.length) {
                error("what");
            } else {
                char delim = txt[0];
                txt = txt[1..$];
                char[] x;
                if (readdelim(x, delim))
                    parseLiteral(x);
            }
        } else if (tryeat("r")) {
            Style s = mRootStyle;
            if (mStyleStack.length >= 2)
                s = mStyleStack[$-2];
            mStyleStack[$-1] = s;
            stylechange();
        } else if (tryeat("{")) {
            mStyleStack ~= mStyleStack[$-1];
        } else if (tryeat("}")) {
            //NOTE: removing the last element is not allowed
            if (mStyleStack.length > 1) {
                mStyleStack.length = mStyleStack.length - 1;
                stylechange();
            } else {
                error("stack empty");
            }
        } else if (tryeat("c")) {
            auto f = getfont();
            if (readcolor(f.fore))
                setfont(f);
        } else if (tryeat("back")) {
            auto f = getfont();
            if (readcolor(f.back))
                setfont(f);
        } else if (tryeat("border-color")) {
            auto f = getfont();
            if (readcolor(f.border_color))
                setfont(f);
        } else if (tryeat("border-width")) {
            auto f = getfont();
            if (readrelint(f.border_width))
                setfont(f);
        } else if (tryeat("blink")) {
            mStyleStack[$-1].blink = true;
            stylechange();
        } else if (tryeat("b")) {
            auto f = getfont();
            f.bold = true;
            setfont(f);
        } else if (tryeat("i")) {
            auto f = getfont();
            f.italic = true;
            setfont(f);
        } else if (tryeat("u")) {
            auto f = getfont();
            f.underline = true;
            setfont(f);
        } else if (tryeat("s")) {
            auto f = getfont();
            if (readrelint(f.size))
                setfont(f);
        } else if (tryeat("t")) {
            char[] t;
            if (readbracket(t))
                parseLiteral(mTranslator(t));
        } else {
            error("unknown command");
        }

        return txt;
    }

    //set text, that can contain commands as described in the class doc
    void setMarkup(char[] txt) {
        mText = txt;
        mTextIsFormatted = true;
        doInit();
        while (txt.length > 0) {
            auto stuff = str.split2(txt, '\\');
            txt = null;
            parseLiteral(stuff[0]);
            if (stuff[1].length) {
                txt = parseCmd(stuff[1][1..$]);
            }
        }
        layout();
    }

    //normal text rendering, no parsing at all (just utf8 and raw line breaks)
    void setLiteral(char[] txt) {
        mText = txt;
        mTextIsFormatted = false;
        doInit();
        parseLiteral(txt);
        layout();
    }

    void setText(char[] txt, bool as_markup) {
        if (as_markup) {
            setMarkup(txt);
        } else {
            setLiteral(txt);
        }
    }

    void translator(Translator t) {
        assert(!!t);
        mTranslator = t;
        update();
    }
    Translator translator() {
        return mTranslator;
    }

    //init the Part.pos (and mSize and Part.size) fields for mParts
    //this is done later, because pos.y can't known in advance, if you want to
    //align text with different font sizes nicely
    private void layout() {
        foreach (ref p; mParts) {
            p.size = p.style.font.textSize(p.text);
        }

        Vector2i pos;
        int max_x;

        void layoutLine(Part[] parts) {
            if (!parts.length)
                return;

            //height
            int height = 0;
            foreach (p; parts) {
                height = max(height, p.size.y);
            }
            //actually place
            foreach (ref p; parts) {
                p.pos.x = pos.x;
                p.pos.y = pos.y + height/2 - p.size.y/2;
                pos.x += p.size.x;
            }
            //in first line: if nothing was produced, skip advancing pos.y
            //(needed for label.d when no text is there, only an image)
            if (!pos.y && !pos.x)
                return;
            //prepare next line / end
            max_x = max(max_x, pos.x);
            pos.x = 0;
            pos.y += height;
        }

        //for each range of Parts with Part.newline==false
        int prev = 0;
        foreach (int cur, p; mParts) {
            if (p.newline) {
                layoutLine(mParts[prev..cur]);
                prev = cur;
            }
        }
        layoutLine(mParts[prev..$]);

        mSize = Vector2i(max_x, pos.y);
    }

    void draw(Canvas c, Vector2i pos) {
        bool blinkphase = cast(int)(time.timeCurrentTime.secsf*2)%2 == 0;
        foreach (ref p; mParts) {
            if (p.style.blink && blinkphase)
                continue;
            p.style.font.drawText(c, p.pos + pos, p.text);
        }
    }

    //forceHeight: if empty, still return standard text height
    Vector2i textSize(bool forceHeight = true) {
        if (mSize.y == 0 && forceHeight) {
            //probably broken; should use height of first Part?
            auto f = mRootStyle.font;
            assert(!!f);
            return f.textSize("", true);
        } else {
            return mSize;
        }
    }
    Vector2i size() {
        return textSize();
    }
}
