//independent from GUI (just as renderbox.d)
module gui.rendertext;

import common.resset;
import framework.framework;
import framework.font;
import framework.i18n;
import gui.global;
import gui.renderbox;
import utils.configfile;
import utils.misc;
import utils.rect2;
import utils.vector2;

import time = utils.time;
import strparser = utils.strparser;
import str = utils.string;
import math = tango.math.Math;
import marray = utils.array;

//line breaking mode for FormattedText
enum ShrinkMode {
    none,     //don't care
    shrink,   //add "..." at the end of too long lines
    wrap,     //break long lines at word boundaries
}

/++
 + Parses a string like
 +  Black\c(ff0000)Red\rBlack,
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
 +  \shadow-color(color-spec)
 +    Like \c, but set shadow color. (Don't forget \shadow-offset)
 +  \b \i \u
 +    Set bold, italic, underline to true.
 +  \s(size-spec)
 +    Set font size. size-spec is <signed integer> ['%']. % means relative size.
 +    e.g. "\s(16)Text in 16pt. \s(-10%)Now 10% smaller."
 +  \border-width(size-spec)  \border-color(color-spec)
 +    border_width and border_color.
 +  \shadow-offset(pixels)
 +    Set shadow offset in pixels (0 means shadows disabled).
 +    If a relative size is specified (e.g. "10%"), the base value is the font
 +    size (note that the font size is in points, not pixels).
 +  \space(pixels)
 +    Insert horizontal spacing in pixels; if a relative size is specified, base
 +    value is the font size (font size is in points, not pixels).
 +  \align_y(i)
 +    i is an int; it defines the vertical text/image alignment:
 +      i==0 center, i<0 top, i>0 bottom
 +  \r
 +    Reset the font to the previous style.
 +    If there was a \{, set style as if you'd do \} (but without poping stack).
 +    If the stack is empty, set to default font.
 +  \[  \]
 +    Push/pop the font style to the stack.
 +    e.g. "\[\c(red)This is red.\]This not."
 +    (oh god, maybe we should just use Tango's XML parser.)
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
 +  \imgref(index)
 +    Use the image as set by setImage(index, image).
 +    The image is layouted as if it was a text glyph.
 +  \imgres(name)
 +    Same as \imgref, but load the image with
 +    FormattedText.resources.get!(Surface)(name).
 + Extension ideas: (not implemented!)
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
            int align_y;
            int img_spacing = 3;
        }
        enum PartType {
            Text,
            Newline,
            Space,
            Image,
        }
        struct Part {
            PartType type;
            Style style;
            Vector2i pos, size;
            //validity depends from PartType
            char[] text;
            Surface image;
        }
        //NOTE: the memory for mText is always owned by us
        char[] mText;
        bool mTextIsFormatted; //mText; false: setLiteral(), true: setMarkup()
        Translator mTranslator;
        ResourceSet mResources;
        Surface[] mImages;
        Style mRootStyle; //style at start
        Part[] mParts;
        Vector2i mSize;
        BoxProperties mBorder;
        ShrinkMode mShrink = ShrinkMode.shrink;
        bool mForceHeight = true;
        bool mAreaValid;
        Vector2i mArea;
        int[2] mAlign;
        //only during parsing
        Style[] mStyleStack; //[$-1] contains current style, assert(length > 0)

        //text used to break overlong text (with shrink option)
        const char[] cDotDot = "...";
        //inserted at the beginning of a wrapped line (right arrow with hook)
        const char[] cWrapSymbol = "\u21aa ";
    }

    this(Font f = null) {
        mRootStyle.font = f ? f : gFontManager.loadFont("default");
        mTranslator = localeRoot();
        mResources = gGuiResources;
        mBorder.enabled = false;
    }

    void translator(Translator t) {
        assert(!!t);
        mTranslator = t;
        update();
    }
    Translator translator() {
        return mTranslator;
    }

    void resources(ResourceSet s) {
        assert(!!s);
        mResources = s;
        update();
    }
    ResourceSet resources() {
        return mResources;
    }

    void font(Font f) {
        assert(!!f);
        if (mRootStyle.font is f)
            return;
        mRootStyle.font = f;
        update();
    }
    Font font() {
        return mRootStyle.font;
    }

    //set an image reference for \imgref
    void setImage(int idx, Surface s) {
        assert(idx >= 0);
        if (mImages.length <= idx)
            mImages.length = idx + 1;
        if (mImages[idx] is s)
            return;
        mImages[idx] = s;
        update();
    }

    //if true, cut too wide text with "..." (needs setArea())
    void shrink(ShrinkMode s) {
        if (mShrink == s)
            return;
        mShrink = s;
        if (mAreaValid)
            update();
    }
    ShrinkMode shrink() {
        return mShrink;
    }

    //if true, make text at least one line high (if the text is empty)
    void forceHeight(bool h) {
        if (mForceHeight == h)
            return;
        mForceHeight = h;
        update();
    }
    bool forceHeight() {
        return mForceHeight;
    }

    //set area rectangle for text (defined by (0,0)-size)
    //align_x/y work like \align_y() (but it affects the text box, not the text)
    //this feature is most useful if shrink is enabled
    void setArea(Vector2i size, int align_x = 0, int align_y = 0) {
        mAlign[0] = align_x;
        mAlign[1] = align_y;
        mArea = size;
        mAreaValid = true;
        if (mShrink)
            update();
    }

    //clear text
    void clear() {
        setLiteral("");
    }

    private void doInit() {
        mStyleStack.length = 1;
        mStyleStack[0] = mRootStyle;
        mParts.length = 0;
    }

    private Part* addpart(PartType type) {
        mParts.length = mParts.length + 1;
        Part* pres = &mParts[$-1];
        pres.type = type;
        pres.style = mStyleStack[$-1];
        return pres;
    }

    //utf-8 and line breaks
    private void parseLiteral(char[] txt) {
        while (txt.length) {
            auto breaks = str.split2(txt, '\n');
            if (breaks[0].length) {
                Part* p = addpart(PartType.Text);
                p.text = breaks[0];
            }
            txt = null;
            if (breaks[1].length) {
                addpart(PartType.Newline);
                txt = breaks[1][1..$];
            }
        }
    }

    private void adderror(char[] msg) {
        //note that only this part has error style (following parts won't)
        Part* pmsg = addpart(PartType.Text);
        Style s;
        s.font = gFontManager.loadFont("txt_error");
        pmsg.style = s;
        pmsg.text = "[" ~ msg ~ "]";
    }

    private bool tryparse(T)(char[] t, ref T res, char[] error = "") {
        try {
            res = strparser.fromStr!(T)(str.strip(t));
            return true;
        } catch (strparser.ConversionException e) {
            adderror(error.length ? error : "expected "~T.stringof);
            return false;
        }
    }

    //parse a command (without the \), and return all text following it
    private char[] parseCmd(char[] txt) {
        //--- parser helpers

        void error(char[] msg) {
            adderror(msg);
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
            } catch (strparser.ConversionException e) {
            }
            error("expected color");
            return false;
        }

        //read pure int
        bool readint(ref int value) {
            char[] t;
            if (!readbracket(t))
                return false;
            return tryparse(t, value);
        }

        //size argument, '(' <int> ['%'] ')'
        //if the value is relative (with %), value is used to get the new value
        bool readrelint(ref int value) {
            char[] t;
            if (!readbracket(t))
                return false;
            t = str.strip(t);
            if (str.eatEnd(t, "%")) {
                float rel;
                if (!tryparse(t, rel))
                    return false;
                if (rel != rel)
                    return true; //user specified nan? what?
                value = cast(int)((100+rel)/100.0f * value);
                return true;
            } else {
                return tryparse(t, value);
            }
        }

        //--- helpers for setting styles

        FontProperties getfont() {
            return mStyleStack[$-1].font.properties;
        }
        void setfont(FontProperties p) {
            mStyleStack[$-1].font = gFontManager.create(p);
        }

        void insert_image(Surface s) {
            assert(!!s);
            Part* p = addpart(PartType.Image);
            p.image = s;
            p.size = s.size;
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
                error("\\lit on end of string");
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
        } else if (tryeat("[")) {
            mStyleStack ~= mStyleStack[$-1];
        } else if (tryeat("]")) {
            //NOTE: removing the last element is not allowed
            if (mStyleStack.length > 1) {
                mStyleStack.length = mStyleStack.length - 1;
            } else {
                error("stack empty");
            }
        } else if (tryeat("c")) {
            auto f = getfont();
            if (readcolor(f.fore_color))
                setfont(f);
        } else if (tryeat("back")) {
            auto f = getfont();
            if (readcolor(f.back_color))
                setfont(f);
        } else if (tryeat("border-color")) {
            auto f = getfont();
            if (readcolor(f.border_color))
                setfont(f);
        } else if (tryeat("border-width")) {
            auto f = getfont();
            if (readrelint(f.border_width))
                setfont(f);
        } else if (tryeat("shadow-color")) {
            auto f = getfont();
            if (readcolor(f.shadow_color))
                setfont(f);
        } else if (tryeat("shadow-offset")) {
            auto f = getfont();
            int s = f.size;
            if (readrelint(s)) {
                f.shadow_offset = s;
                setfont(f);
            }
        } else if (tryeat("blink")) {
            mStyleStack[$-1].blink = true;
        } else if (tryeat("imgref")) {
            int refidx;
            if (readint(refidx)) {
                if (refidx >= 0 && refidx < mImages.length && mImages[refidx]) {
                    insert_image(mImages[refidx]);
                } else {
                    error("invalid image index");
                }
            }
        } else if (tryeat("imgres")) {
            char[] t;
            if (readbracket(t)) {
                Surface s = resources.get!(Surface)(t, true);
                if (s) {
                    insert_image(s);
                } else {
                    error("image resource invalid");
                }
            }
        } else if (tryeat("space")) {
            int s = getfont().size;
            if (readrelint(s)) {
                Part* p = addpart(PartType.Space);
                p.size = Vector2i(s, 0);
            }
        } else if (tryeat("align_y")) {
            int a;
            if (readint(a))
                mStyleStack[$-1].align_y = a;
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

    //retranslate / restlye / internal reparse
    final void update() {
        doInit();
        if (!mTextIsFormatted) {
            parseLiteral(mText);
        } else {
            char[] txt = mText;
            while (txt.length > 0) {
                auto stuff = str.split2(txt, '\\');
                txt = null;
                parseLiteral(stuff[0]);
                if (stuff[1].length) {
                    txt = parseCmd(stuff[1][1..$]);
                }
            }
        }
        layout();
    }

    //set text, that can contain commands as described in the class doc
    void setMarkup(char[] txt) {
        setText(true, txt);
    }

    //normal text rendering, no parsing at all (just utf8 and raw line breaks)
    void setLiteral(char[] txt) {
        setText(false, txt);
    }

    void setText(bool as_markup, char[] txt) {
        mTextIsFormatted = as_markup;
        //copy the text instead of doing txt.dup to prevent memory re-allocation
        mText.length = txt.length;
        mText[] = txt;
        update();
    }

    //like setText(), but build the string with format()
    //if the resulting string is the same as the last string set, no further
    //  work is done (and if the string is small and the format string doesn't
    //  trigger any toString()s, no memory is allocated)
    //returns if the text was changed (if not, the text was the same)
    bool setTextFmt(bool as_markup, char[] fmt, ...) {
        return setTextFmt_fx(as_markup, fmt, _arguments, _argptr);
    }

    bool setTextFmt_fx(bool as_markup, char[] fmt,
        TypeInfo[] arguments, va_list argptr)
    {
        //tries not to change anything if the text to be set is the same

        char[80] buffer = void;
        char[] res = formatfx_s(buffer, fmt, arguments, argptr);
        if (mTextIsFormatted == as_markup && mText == res)
            return false;
        setText(as_markup, res);
        //formatfx_s allocates on the heap if buffer isn't big enough
        //delete the buffer if it was heap-allocated
        if (res.ptr !is buffer.ptr)
            delete res;
        return true;
    }

    void getText(out bool as_markup, out char[] data) {
        as_markup = mTextIsFormatted;
        //text is copied because mText may change on next set-text
        data = mText.dup;
    }

    private static int doalign(int a, int container, int element) {
        if (a > 0) {
            return container - element; //bottom
        } else if (a < 0) {
            return 0;                   //top
        }
        //center
        //if too wide, align to one side (at least needed when Label has centerX
        //  and shrink set, when text is cut due to shrinking)
        if (element > container)
            return 0;
        return container/2 - element/2;
    }

    //determine additional spacing between two parts
    private static int parts_spacing(Part* a, Part* b) {
        Style style = b.style;
        //only between images or text and image
        if (b.type == PartType.Image)
            swap(a, b);
        if (a.type == PartType.Image &&
            (b.type == PartType.Image || b.type == PartType.Text))
            return style.img_spacing;
        return 0;
    }

    //handle: break on newlines, text part positions, alignment, shrinking
    //the way it works on mParts is destructive (shrinking...)
    private void layout() {
        foreach (ref p; mParts) {
            if (p.type == PartType.Text) {
                p.size = p.style.font.textSize(p.text);
            }
        }

        Vector2i pos;
        int max_x;
        int max_w = mShrink && mAreaValid ? mArea.x : int.max;

        //return height
        int layoutLine(uint p_start, ref uint p_end) {
            Part[] parts = mParts[p_start..p_end];

            //height
            int height = 0;
            foreach (p; parts) {
                assert(p.type != PartType.Newline);
                height = max(height, p.size.y);
            }

            //actually place
            Part* prev;
            foreach (ref p; parts) {
                p.pos.x = pos.x;
                p.pos.y = pos.y + doalign(p.style.align_y, height, p.size.y);
                pos.x += p.size.x;
                if (prev)
                    pos.x += parts_spacing(prev, &p);
                prev = &p;
            }

            //shrinking: if text too wide, break with "..." before overflow
            if (pos.x > max_w) {
                bool toowide = false;
                foreach_reverse (uint index, ref p; parts) {
                    if (p.pos.x + p.size.x > max_w)
                        toowide = true;
                    if (!toowide || p.pos.x >= max_w)
                        continue;
                    uint tail = p_start + index + 1;
                    if (mShrink == ShrinkMode.shrink) {
                        //if there's an image and it is too wide, it will be
                        //  removed, and the text before it will have ... even
                        //  if the text fits (that's how it's supposed to work)
                        if (p.type != PartType.Text)
                            continue;
                        Font f = p.style.font;
                        Vector2i s = f.textSize(cDotDot);
                        uint at = f.textFit(p.text, max_w - s.x - p.pos.x);
                        //breaking here may look stupid ("..." in different
                        //  style)
                        if (at == 0)
                            continue;
                        p.text = p.text[0..at];
                        p.size = f.textSize(p.text);
                        //remove the tailing parts for this line
                        int cnt = p_end - tail;
                        assert(cnt >= 0);
                        marray.arrayRemoveN(mParts, tail, cnt);
                        p_end -= cnt;
                        //insert "..."
                        marray.arrayInsertN(mParts, tail, 1);
                        p_end += 1;
                        Part* pdots = &mParts[tail];
                        *pdots = Part.init;
                        pdots.type = PartType.Text;
                        pdots.style = p.style;
                        pdots.text = cDotDot;
                        pdots.size = s;
                        pdots.pos = p.pos+Vector2i(p.size.x,0);
                    } else {
                        assert(mShrink == ShrinkMode.wrap);
                        //true afterwards if a new line was created;
                        //  p_end will point to the newline part
                        bool wrapped = false;
                        switch (p.type) {
                            case PartType.Space:
                                //space at the border, replace by newline
                                if (index != parts.length-1) {
                                    p = Part.init;
                                    p.type = PartType.Newline;
                                    p_end = tail - 1;
                                    wrapped = true;
                                }
                                break;
                            case PartType.Text:
                                //text part, do word wrapping
                                Font f = p.style.font;
                                uint at = f.textFit(p.text, max_w - p.pos.x,
                                    true);
                                if (at == p.text.length) {
                                    //xxx can this happen?
                                    //text fits entirely, although code above
                                    //detected a splitpoint -> newline after
                                    if (index == parts.length-1) {
                                        //no part after current, abort
                                        break;
                                    }
                                    tail++;
                                    //switch fall-through
                                } else if (at > 0) {
                                    //insert newline and text for next line
                                    marray.arrayInsertN(mParts, tail, 2);
                                    mParts[tail] = Part.init;
                                    mParts[tail].type = PartType.Newline;
                                    //init next part with wrapped text
                                    Part* pNext = &mParts[tail + 1];
                                    *pNext = Part.init;
                                    pNext.type = PartType.Text;
                                    pNext.style = p.style;
                                    pNext.text = p.text[at..$];
                                    //pos will be set with next layoutLine()
                                    pNext.size = f.textSize(pNext.text);
                                    //cur off current text
                                    Part* pCur = &mParts[tail-1];
                                    pCur.text = p.text[0..at];
                                    pCur.size = f.textSize(p.text);
                                    p_end = tail;
                                    wrapped = true;
                                    break;
                                }
                                //fall-through for "at" special cases
                            default:
                                //non-splittable part, insert newline before
                                tail--;
                                marray.arrayInsertN(mParts, tail, 1);
                                Part* pNL = &mParts[tail];
                                *pNL = Part.init;
                                pNL.type = PartType.Newline;
                                p_end = tail;
                                wrapped = true;
                        }
                        if (wrapped) {
                            //insert "wrapping arrow"
                            marray.arrayInsertN(mParts, p_end+1, 1);
                            Part* pWrap = &mParts[p_end+1];
                            *pWrap = Part.init;
                            pWrap.type = PartType.Text;
                            pWrap.style = mRootStyle;
                            pWrap.text = cWrapSymbol;
                            //pos will be set with next layoutLine()
                            pWrap.size = mRootStyle.font.textSize(pWrap.text);
                        }
                    }
                    //just make sure...
                    parts = mParts[p_start..p_end];
                    break;
                }
                //xxx would need to redo height and placement here, because
                //    line contents changed; although in the "shrink" case,
                //    it may be intentional to keep the old height
            }

            //prepare next line / end
            max_x = max(max_x, pos.x);
            pos.x = 0;
            return height;
        }

        //break at newlines
        uint prev = 0;
        uint cur = 0;
        for (;;) {
            bool end = cur == mParts.length;
            if (end || mParts[cur].type == PartType.Newline) {
                uint old = cur;
                int height = layoutLine(prev, cur);
                if (height == 0 && !end) {
                    //spacing for empty lines
                    height = mParts[old].style.font.textSize("", true).y;
                }
                pos.y += height;
                prev = cur + 1;
            }
            cur++;
            if (cur > mParts.length)
                break;
        }

        if (forceHeight && pos.y == 0) {
            //probably broken; should use height of first or last Part?
            pos.y = mRootStyle.font.textSize("", true).y;
        }

        mSize = Vector2i(max_x, pos.y);

        if (mBorder.enabled) {
            auto borderw = Vector2i(mBorder.effectiveBorderWidth);
            foreach (ref p; mParts) {
                p.pos += borderw;
            }
            mSize += borderw*2;
        }
    }

    //offset added to Part.pos for global alignment
    //not done in layout, so resizing the global box is free in most situations
    private Vector2i innerOffset() {
        Vector2i base;
        if (mAreaValid) {
            base.x += doalign(mAlign[0], mArea.x, mSize.x);
            base.y += doalign(mAlign[1], mArea.y, mSize.y);
        }
        return base;
    }

    void draw(Canvas c, Vector2i pos) {
        pos += innerOffset();

        if (mBorder.enabled) {
            if (mAreaValid) {
                drawBox(c, pos, mArea, mBorder);
            } else {
                drawBox(c, pos, mSize, mBorder);
            }
        }

        bool blinkphase = cast(int)(time.timeCurrentTime.secsf*2)%2 == 0;
        foreach (ref p; mParts) {
            if (p.style.blink && blinkphase)
                continue;
            PartType t = p.type;
            if (t == PartType.Text) {
                p.style.font.drawText(c, p.pos + pos, p.text);
            } else if (t == PartType.Image) {
                c.draw(p.image, p.pos + pos);
            }
        }
    }

    Vector2i textSize() {
        return mSize;
    }
    Vector2i size() {
        return mAreaValid ? mArea : textSize();
    }

    BoxProperties border() {
        return mBorder;
    }
    void setBorder(BoxProperties b) {
        if (mBorder == b)
            return;
        mBorder = b;
        update();
    }
}
