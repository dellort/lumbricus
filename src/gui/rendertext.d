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

struct TextRange {
    //start and end indices
    int start, end;

    TextRange ordered() {
        auto sstart = min(start, end);
        auto ssend = max(start, end);
        return TextRange(sstart, ssend);
    }
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
 +    If there was a \[, set style as if you'd do \] (but without poping stack).
 +    If the stack is empty, set to default font.
 +  \[  \]
 +    Push/pop the font style to the stack.
 +    e.g. "\[\c(red)This is red.\]This not."
 +    (oh god, maybe we should just use Tango's XML parser.)
 +  \\
 +    Output a \
 +  \n
 +    Output a line break. (But the string can contain raw line breaks, too.)
 +  \tab
 +    Advance output position to next tab-stop.
 +    (A raw \t as in string literal escape does the same thing.)
 +  \t(text)
 +    Translate the text using i18n stuff. No parameters yet...
 +    Resulting translation is included literally.
 +  \lit<char>text<char>
 +    Include the text included between the given char as literal.
 +    e.g. "\lit+I'm \bliteral!+" the \b tag isn't parsed.
 +  \litx(count,text)
 +    Include the text as literal like \lit, where the text is exact count bytes
 +    long. This means text can contain any characters, and thus is safer than
 +    \lit. The trailing ')' doesn't have any meaning and is just for symmetry
 +    (the parser still raises an error if it's missing).
 +    Example: \litx(6,blä\n)) outputs 'blä\n)'. ('ä' is two bytes in utf-8.)
 +  \blink
 +    Annoy the user.
 +  \imgref(index)
 +    Use the image as set by setImage(index, image).
 +    The image is layouted as if it was a text glyph.
 +  \imgres(name)
 +    Same as \imgref, but load the image with
 +    FormattedText.resources.get!(Surface)(name).
 +  \nop
 +    No operation; for testing (e.g. split parts to see if shrinking or
 +    word-wrapping still works).
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
            Part* next;
            PartType type;
            Style style;
            Vector2i pos, size;
            bool nowrap; //hack for wrap arrow
            bool startline; //hack for indexFromPosFuzzy()
            //validity depends from PartType
            char[] text;
            int text_start = -1; //if >=0, start index into mText
            Surface image;
        }
        //NOTE: the memory for mText is always owned by us
        char[] mText;
        bool mTextIsFormatted; //mText; false: setLiteral(), true: setMarkup()
        Translator mTranslator;
        ResourceSet mResources;
        Surface[] mImages;
        Style mRootStyle; //style at start
        Part* mParts;
        Part* mPartsAlloc; //freelist
        StyleRange*[] mStyles;
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

    //put a part of a text under a specific style, for addStyleRange()
    struct StyleRange {
        Style style;
        TextRange range;
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

    //force a given range of text to a specific style
    //this overrides any style commands when markup is used
    //xxx GTK's Pango has a better way:
    //  - for each style attribute, there's a separate attribute "class"
    //  - e.g. you can instantiate a PangoAttribute to set the foreground
    //    color to pango_attr_foreground_new(), and this attribute is applied
    //    to a range of text (start and end index)
    //  - selection probably works by adding an additional attribute for
    //    foreground/background colors
    //  - it probably doesn't conflict with other styles, because later added
    //    attributes (such as the text selection color) take priority over the
    //    text formatting itself
    //  - because for each style aspect there's separate style instances, it
    //    can't happen that text selection destroys attributes such as the font
    //    size of the original text
    //so, Pango has much better ideas, but they also require you to have
    //  separate attribute classes/instances and so on for each styling aspect,
    //  which would inflate the code; plus we don't really need this feature
    //  (lol), so I'm not doing this
    //xxx 2: if markup is used, some ranges of text may not be styled (e.g.
    //  \lit or text translated by \t()); look for parseLiteral(..., -1) calls
    StyleRange* addStyleRange(TextRange range, Font f) {
        StyleRange* res = new StyleRange;
        res.range = range;
        res.style.font = f;
        mStyles ~= res;
        update();
        return res;
    }

    //remove a style range added by addStyleRange()
    //the text will then look as if that specific addStyleRange was never called
    //style must have been added (though sr is null is allowed)
    void removeStyleRange(StyleRange* sr) {
        if (!sr)
            return;
        marray.arrayRemove(mStyles, sr);
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
        if (mShrink != ShrinkMode.none)
            update();
    }

    //clear text
    void clear() {
        setLiteral("");
    }

    private void doInit() {
        mStyleStack.length = 1;
        mStyleStack[0] = mRootStyle;
        while (mParts) {
            Part* cur = mParts;
            mParts = mParts.next;
            freepart(cur);
        }
        mParts = null;
    }

    //allocate default initialized Part
    private Part* allocpart() {
        if (!mPartsAlloc) {
            //get some (new'ing each one separately would be too simple)
            auto some = new Part[4];
            mPartsAlloc = &some[0];
            for (uint n = 0; n < some.length - 1; n++) {
                some[n].next = &some[n+1];
            }
        }
        assert(mPartsAlloc);
        auto cur = mPartsAlloc;
        mPartsAlloc = cur.next;
        cur.next = null;
        return cur;
    }

    private void freepart(Part* p) {
        if (!p)
            return;
        *p = Part.init;
        p.next = mPartsAlloc;
        mPartsAlloc = p;
    }

    //alloc a part, init with the current style, and append to mParts
    private Part* addpart(PartType type) {
        Part* p = allocpart();
        p.type = type;
        p.style = mStyleStack[$-1];
        //append to end of singly linked list
        //xxx slow if part count high (but usually, it's very low)
        Part** cur = &mParts;
        while (*cur) {
            cur = &(*cur).next;
        }
        *cur = p;
        return p;
    }

    //utf-8 and line breaks
    //the start_index is the offset of txt into mText, use -1 for invalid
    //  (only pass a valid index if txt has not been modified etc.)
    private void parseLiteral(char[] txt, int start_index) {
        //assumes that t is a slice of txt, and that nothing of txt is skipped
        Part* add(PartType type, int stop) {
            char[] t = txt[0..stop];
            if (t.length == 0)
                return null;
            Part* p = addpart(type);
            p.text_start = start_index;
            p.text = t;
            if (start_index >= 0) {
                assert(mText[start_index..start_index+p.text.length] == p.text);
                start_index += t.length;
            }
            txt = txt[t.length..$];
            return p;
        }

        //split text on \n or other escape sequences
        outerloop: while (txt.length) {
            foreach (int idx, char c; txt) {
                if (c == '\n') {
                    add(PartType.Text, idx);
                    add(PartType.Newline, 1);
                    continue outerloop;
                } else if (c == '\t') {
                    add(PartType.Text, idx);
                    auto p = add(PartType.Space, 1);
                    continue outerloop;
                }
            }
            add(PartType.Text, txt.length);
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

        //like tryeat, but output error if unsuccessful
        bool eat(char[] t) {
            bool res = tryeat(t);
            if (!res)
                error("'" ~ t ~ "' expected");
            return res;
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
        //syntax documentation see comment near top of this file

        //(be sure to put longer commands before shorter ones if ambiguous,
        // like "back" - "b")
        if (tryeat("\\")) {
            parseLiteral("\\", -1);
        } else if (tryeat("nop")) {
            //no operation
        } else if (tryeat("n")) {
            parseLiteral("\n", -1);
        } else if (tryeat("tab")) { //\t is already the translate command
            parseLiteral("\t", -1);
        } else if (tryeat("litx")) {
            char[] t;
            uint len;
            if (eat("(") && readdelim(t, ',') && tryparse(t, len)) {
                if (len < txt.length) {
                    char[] lit = txt[0..len];
                    txt = txt[len..$];
                    parseLiteral(lit, -1);
                    eat(")");
                } else {
                    error("\\litx length value out of bounds");
                }
            }
        } else if (tryeat("lit")) {
            if (!txt.length) {
                error("\\lit on end of string");
            } else {
                char delim = txt[0];
                txt = txt[1..$];
                char[] x;
                if (readdelim(x, delim))
                    parseLiteral(x, -1);
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
                parseLiteral(mTranslator(t), -1);
        } else {
            error("unknown command");
        }

        return txt;
    }

    //retranslate / restlye / internal reparse
    final void update() {
        doInit();
        if (!mTextIsFormatted) {
            parseLiteral(mText, 0);
        } else {
            char[] txt = mText;
            int idx = 0;
            while (txt.length > 0) {
                auto stuff = str.split2(txt, '\\');
                txt = null;
                parseLiteral(stuff[0], idx);
                idx += stuff[0].length;
                if (stuff[1].length) {
                    idx += 1;
                    char[] next = stuff[1][1..$];
                    txt = parseCmd(next);
                    //find out how much text was eaten
                    idx += next.length - txt.length;
                }
            }
        }
        applyStyles();
        layout();
    }

    private TextRange part_range(Part* p) {
        return TextRange(p.text_start, p.text_start + p.text.length);
    }

    //apply mStyles on mParts
    //mParts already contain styling (from markup), but mStyles overrides it
    //works destructively on mParts (if mStyles is not empty)
    private void applyStyles() {
        //note that style-ranges can overlap, and that later added style-ranges
        //  override earlier ones
        foreach (StyleRange* style; mStyles) {
            TextRange r = style.range;
            if (r.start >= r.end)
                continue;
            for (Part* cur = mParts; !!cur; cur = cur.next) {
                if (cur.type != PartType.Text || cur.text_start < 0)
                    continue;
                //split off a part from cur, and add it after cur
                void split(int at) {
                    assert(at > 0 && at < cur.text.length);
                    Part* n = allocpart();
                    *n = *cur;
                    cur.next = n;
                    cur.text = cur.text[0..at];
                    n.text = n.text[at..$];
                    n.text_start += at;
                }
                //note that each Part can be split up into 3 parts (iteratively)
                TextRange p = part_range(cur);
                if (r.start > p.start && r.start < p.end) {
                    //"unaffected" part is first, set styling in next iteration
                    split(r.start - p.start);
                } else if (p.start >= r.start && p.start < r.end) {
                    //style first part; possibly split "unaffected" second part
                    if (r.end < p.end) {
                        split(r.end - p.start);
                    }
                    cur.style = style.style;
                }
            }
        }
    }

    //set text, that can contain commands as described in the class doc
    bool setMarkup(char[] txt) {
        return setText(true, txt);
    }

    //normal text rendering, no parsing at all (just utf8 and raw line breaks)
    bool setLiteral(char[] txt) {
        return setText(false, txt);
    }

    //return if text was actually changed (or if it was the same)
    bool setText(bool as_markup, char[] txt) {
        if (mTextIsFormatted == as_markup && mText == txt)
            return false;
        mTextIsFormatted = as_markup;
        //copy the text instead of doing txt.dup to prevent memory re-allocation
        //known places that use setText() with txt pointing to temp memory:
        //- scripting (Lua wrapper only copies strings for property-sets)
        //- setTextFmt[_fx]()
        //all those should actually call setTextCopy()
        mText.length = txt.length;
        mText[] = txt;
        update();
        return true;
    }

    //this means the caller may make txt invalid (e.g. by deallocating it) after
    //  the function has returned; this function will always copy it
    //  => can avoid unneeded memory allocations
    //the actual reason for providing this separate function is:
    //- you somehow need to pass a hint to the Lua demarshaller/binding code,
    //  that it doesn't need to copy the Lua string => use a marker type
    //- D doesn't allow implicitly converting char[] -> TempString, so setText
    //  has to stay, even though it does exactly the same
    bool setTextCopy(bool as_markup, TempString txt) {
        return setText(as_markup, txt.raw);
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
        char[] res = myformat_s_fx(buffer, fmt, arguments, argptr);
        bool r = setTextCopy(as_markup, TempString(res));
        //formatfx_s allocates on the heap if buffer isn't big enough
        //delete the buffer if it was heap-allocated
        if (res.ptr !is buffer.ptr)
            delete res;
        return r;
    }

    void getText(out bool as_markup, out char[] data) {
        as_markup = mTextIsFormatted;
        //text is copied because mText may change on next set-text
        data = mText.dup;
    }

    //return pointer to internal text string
    //this string may change arbitrarily as setText* is called
    char[] volatileText() {
        return mText;
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

    //find the position of the first char after the last whitespace
    //e.g. find_after_ws_pos("a  b cd") == 5
    //return -1 if no white space found
    private static int find_after_ws_pos(char[] s) {
        int at = -1;
        foreach (uint idx, dchar c; s) {
            if (str.iswhite(c)) {
                at = idx;
            }
        }
        if (at >= 0)
            at += str.stride(s, at);
        return at;
    }

    //handle: break on newlines, text part positions, alignment, shrinking
    //the way it works on mParts is destructive (shrinking...)
    private void layout() {
        for (Part* p = mParts; !!p; p = p.next) {
            if (p.type == PartType.Text) {
                p.size = p.style.font.textSize(p.text);
            }
        }

        Vector2i pos;
        int max_x;
        int max_w = (mShrink != ShrinkMode.none && mAreaValid)
            ? mArea.x : int.max;

        //list of parts produced by layoutLine()
        Part* newparts;
        Part** pnewparts = &newparts;

        //p_start = first Part of the line (may be null => empty line); it is a
        //  singly linked list, terminated before the next line break
        //line_style = fallback style for lines with no parts
        //if this function splits off a new line, it returns the pointer to
        //  the first part of it
        Part* layoutLine(Part* p_start, Style line_style) {
            //place x coords
            Part* spc_prev;
            for (Part* p = p_start; !!p; p = p.next) {
                p.pos.x = pos.x;
                if (p.type == PartType.Space && p.text == "\t") {
                    //it's a tab! tabs jump to the next tab-stop
                    //tabstopw = distance between tabstops
                    int tabstopw = max(mRootStyle.font.textSize("xxxx").x, 1);
                    int tw = p.pos.x / tabstopw;
                    p.size.x = (tw+1)*tabstopw - p.pos.x;
                }
                pos.x += p.size.x;
                if (spc_prev)
                    pos.x += parts_spacing(spc_prev, p);
                spc_prev = p;

                assert(p.type != PartType.Newline);
            }

            //if text gets cut with "shrink", point to the first part that's not
            //  visible anymore; the range first_invisible..p_end is the cut
            //  part (won't include the second part of the split text)
            Part* first_invisible;

            //if the text gets wrapped, the remaining parts will be formatted
            //  as a new line
            Part* split_new_line;

            //shrinking: if text too wide, break with "..." before overflow
            if (mShrink == ShrinkMode.shrink && pos.x > max_w) {
                bool toowide = false;
                //iterate backwards from end-of-list .. p_start
                //includes p_start
                Part* cur = null;
                for (;;) {
                    //find element before cur; messy because cur may be null
                    //in this case, null=end of the list => return last item
                    Part* nextcur = p_start;
                    while (nextcur) {
                        if (nextcur.next is cur)
                            break;
                        nextcur = nextcur.next;
                    }
                    cur = nextcur;
                    if (!cur)
                        break;
                    Part* p = cur;
                    if (p.pos.x + p.size.x > max_w)
                        toowide = true;
                    if (!toowide || p.pos.x >= max_w)
                        continue;
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
                    if (at == 0) {
                        if (cur !is p_start) {
                            continue;
                        } else {
                            //but if it's the first Part, not breaking would
                            //  also look stupid, so cut it down to 1 char
                            if (p.text.length) {
                                at = str.stride(p.text, 0);
                            }
                        }
                    }
                    p.text = p.text[0..at];
                    p.size = f.textSize(p.text);
                    //move the trailing parts of the line to first_invisible
                    first_invisible = p.next;
                    p.next = null;
                    //append "..."
                    Part* pdots = allocpart();
                    pdots.type = PartType.Text;
                    pdots.style = p.style;
                    pdots.text = cDotDot;
                    pdots.size = s;
                    pdots.pos = p.pos+Vector2i(p.size.x,0);
                    p.next = pdots;
                    break;
                }
            }

            //or wrapping: text too wide => split into a new line
            if (mShrink == ShrinkMode.wrap && pos.x > max_w && p_start) {
                //scan for the last part that might be wrapable
                Part* last_white; //Part that is/contains whitespace
                Part* last = p_start; //Part that is cut by the right border
                for (Part* p = p_start; !!p; p = p.next) {
                    if (p.pos.x > max_w)
                        break;
                    last = p;
                    if (p.nowrap)
                        continue;
                    if (p.type == PartType.Text) {
                        if (find_after_ws_pos(p.text) >= 0) {
                            //see if the white space position fits into max_w
                            if (p.pos.x + p.size.x <= max_w
                                || p.style.font.textFit(p.text,
                                    max_w - p.pos.x, true, true) > 0)
                            {
                                last_white = p;
                            }
                        }
                    } else {
                        //all parts other than text can be considered to
                        //  contain whitespace (images, spaces)
                        last_white = p;
                    }
                }
                assert(!!last);
                //skip to first no-wrap
                while (last.next && last.nowrap)
                    last = last.next;
                //non-null afterwards if a new line was created; points to
                //  first part of the new line
                Part* wrapped = null;
                Part* break_on = last_white ? last_white : last;
                bool toowide = break_on.pos.x + break_on.size.x > max_w;
                if (break_on.type == PartType.Text) {
                    //text part, do word wrapping
                    Font f = break_on.style.font;
                    uint at;
                    if (toowide) {
                        //break on width
                        at = f.textFit(break_on.text,
                            max_w - break_on.pos.x, true);
                    } else {
                        //break on last whitespace
                        int p = find_after_ws_pos(break_on.text);
                        at = p >= 0 ? p : break_on.text.length;
                    }
                    if (at == 0) {
                        //meh, leave at least one char on the line
                        //else there may be an infinite loop on small max_w's
                        if (break_on.text.length)
                            at = str.stride(break_on.text, 0);
                    }
                    if (at == 0 || at == break_on.text.length) {
                        //special cases for empty text or no-text-wrapped
                        //xxx: not sure when they happen, but don't split off a
                        //  new line to be safe from infinite recursions etc.
                        //oookay.... if there's a text part of whitespace only
                        //  before a non-breakable part, last_white will be the
                        //  white-space only part, and find_after_ws_pos above
                        //  will return the length of the string
                        //but you really want to break here
                        if (at == break_on.text.length
                            && break_on is last_white)
                        {
                            wrapped = break_on.next;
                            break_on.next = null;
                        }
                    } else {
                        //split part into trailling text + new line text
                        //pos will be set with next layoutLine()
                        Part* pNext = allocpart();
                        *pNext = *break_on;
                        pNext.text = str.stripl(pNext.text[at..$]);
                        pNext.size = f.textSize(pNext.text);
                        if (pNext.text_start >= 0)
                            pNext.text_start += at;
                        //cut off current text
                        break_on.text = break_on.text[0..at];
                        break_on.size = f.textSize(break_on.text);
                        break_on.next = null;
                        wrapped = pNext;
                    }
                } else {
                    //non-splittable part, insert newline
                    //in both cases, must consider nowrap
                    if (break_on.nowrap) {
                        //don't do anything (danger of infinite loops)
                    } else if (toowide) {
                        //move break_on to next line
                        if (break_on !is p_start) {
                            //find prev to remove break_on from p_start list
                            Part* prev = p_start;
                            while (prev && prev.next !is break_on)
                                prev = prev.next;
                            if (prev && !prev.nowrap) {
                                prev.next = null;
                                wrapped = break_on;
                            }
                        }
                    } else {
                        //move stuff after break_on to next line
                        if (!break_on.nowrap) {
                            wrapped = break_on.next;
                            break_on.next = null;
                        }
                    }
                }
                if (wrapped) {
                    //insert "wrapping arrow"
                    Part* pWrap = allocpart();
                    pWrap.type = PartType.Text;
                    pWrap.style = mRootStyle;
                    pWrap.text = cWrapSymbol;
                    pWrap.nowrap = true;
                    //pos will be set with next layoutLine()
                    pWrap.size = pWrap.style.font.textSize(pWrap.text);
                    pWrap.next = wrapped;
                    split_new_line = pWrap;
                }
            }

            //height of the line
            int height = 0;
            //visible text
            for (Part* p = p_start; !!p; p = p.next) {
                assert(p.type != PartType.Newline);
                height = max(height, p.size.y);
            }
            //consider the cut/invisible text when ShrinkMode.shrink
            for (Part* p = first_invisible; !!p; p = p.next) {
                assert(p.type != PartType.Newline);
                height = max(height, p.size.y);
            }

            //empty line => apply v-spacing
            if (height == 0) {
                height = line_style.font.textSize("", true).y;
            }

            //actually place (y)
            for (Part* p = p_start; !!p; p = p.next) {
                p.pos.y = pos.y + doalign(p.style.align_y, height, p.size.y);
            }

            //re-add visible parts to global list
            if (p_start) {
                p_start.startline = true;
            }
            *pnewparts = p_start;
            while (*pnewparts)
                pnewparts = &(*pnewparts).next;

            //prepare next line / end
            max_x = max(max_x, pos.x);
            pos.x = 0;
            pos.y += height;

            return split_new_line;
        }

        //break at newlines
        //if forceHeight is true, at least force layout of an empty line
        Part* cur = mParts;
        mParts = null; //parts get re-added in layoutLine()
        bool force_next = forceHeight;
        Style line_style = mRootStyle;
        while (cur || force_next) {
            force_next = false;
            //cut off the list before next line break (simplifies layoutLine())
            //after the following loop:
            //  tail = everything after the newline (or null)
            //  cur = list from old cur until (excluding) the newline
            //if cur is the newline, it gets set to null
            Part* tail = null;
            Part* newline = null;
            Part** pprev = &cur;
            while (*pprev) {
                if ((*pprev).type == PartType.Newline) {
                    newline = *pprev;
                    *pprev = null;
                    tail = newline.next;
                    force_next = true; //don't swallow trailing \n
                    line_style = newline.style;
                    break;
                }
                pprev = &(*pprev).next;
            }
            //do a single logical line and all physical lines produced by
            //  wrapping (i.e. do the remainder returned by layoutLine())
            for (;;) {
                Part* tail2 = layoutLine(cur, line_style);
                if (!tail2)
                    break;
                cur = tail2;
            }
            cur = tail;
        }

        mParts = newparts;

        mSize = Vector2i(max_x, pos.y);

        if (mBorder.enabled) {
            auto borderw = Vector2i(mBorder.effectiveBorderWidth);
            for (Part* p = mParts; !!p; p = p.next) {
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
        for (Part* p = mParts; !!p; p = p.next) {
            if (p.style.blink && blinkphase)
                continue;
            PartType t = p.type;
            //c.drawRect(Rect2i.Span(p.pos+pos, p.size), Color(0,1,0));
            if (t == PartType.Text) {
                //if (p.debug_mark)
                //    c.drawRect(Rect2i.Span(p.pos+pos, p.size), Color(1,0,0));
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

    //return the bounds of the glyph at the given index
    //index = byte index into the text
    //fuzzy = if true, return the right border (width==0) of the last valid (as
    //  in references actual text) glyph
    //you'll have to add whatever you've passed to draw() to the result to get
    //  the rect in your drawing coordinate system
    //Rect2i.Abnormal() is returned on error (e.g. index out of bounds, or
    //  points into formatting commands)
    Rect2i getGlyphRect(int index, bool fuzzy) {
        //assumes that parts have the same order as the referenced text
        //(valid Part.text_start values monotonically increase)
        Part* last;
        for (Part* p = mParts; !!p; p = p.next) {
            if (p.type != PartType.Text || p.text_start < 0)
                continue;
            if (index >= p.text_start && index < p.text_start + p.text.length) {
                index -= p.text_start;
                assert(index >= 0 && index < p.text.length);
                //it's in p; position inside string...
                Font f = p.style.font;
                Rect2i rc;
                rc.p1 = innerOffset() + p.pos;
                Vector2i pre = f.textSize(p.text[0..index]);
                rc.p1.x += pre.x;
                rc.p2 = rc.p1
                    + f.textSize(str.utf8_get_first(p.text[index..$]));
                return rc;
            }
            //no match yet => if parts are sorted, there won't be any matches
            if (fuzzy && last && p.text_start > index) {
                Rect2i rc;
                rc.p1 = last.pos + Vector2i(last.size.x, 0);
                rc.p2 = rc.p1 + Vector2i(0, last.size.y);
                return rc;
            }
            last = p;
        }
        return Rect2i.Abnormal();
    }
    //similar to getGlyphRect(), but has some handling for nasty special cases:
    //- if index points at the end of the string, the right side of the last
    //  char is returned (just a line, width 0)
    //- if text has length 0, return a line (width 0) at the beginning in the
    //  default style
    Rect2i getCursorPos(int index) {
        Rect2i rc = Rect2i.Abnormal();
        bool rightline = false;
        if (index >= mText.length && mText.length > 0) {
            rc = getGlyphRect(str.charPrev(mText, mText.length), true);
            if (rc.isNormal()) {
                //right line
                rc.p1.x = rc.p2.x;
                return rc;
            }
        }
        rc = getGlyphRect(index, true);
        if (rc.isNormal()) {
            return rc;
        }
        //fallback: where the first char would be if there were text
        int h = mRootStyle.font.textSize("W").y;
        rc.p1 = Vector2i(0);
        rc.p2 = Vector2i(0, h);
        rc += innerOffset(); //xxx border? alignment?
        return rc;
    }

    //find the text index for the given point (range [0, text.length] )
    //to get the correct pos, don't forget to add whatever you pass to draw()
    //the "Fuzzy" means it returns the nearest match, even if not exact
    int indexFromPosFuzzy(Vector2i pos) {
        pos -= innerOffset();
        int def = 0;
        int def_x = int.max;
        Part* first, last;
        for (Part* p = mParts; !!p; p = p.next) {
            if (p.startline)
                def_x = int.max;
            if (p.type != PartType.Text || p.text_start < 0)
                continue;
            int x1 = p.pos.x, x2 = p.pos.x + p.size.x;
            //the y part is slightly annoying (if y is out of bounds, you'd
            //  want it to select text on the first/last line), but for now it's
            //  needed for multiline stuff
            if (pos.x >= x1 && pos.x < x2
                && pos.y >= p.pos.y && pos.y <= p.pos.y + p.size.y)
            {
                return p.text_start + p.style.font.findIndex(p.text,
                    pos.x - x1);
            }
            //handling when clicking "beside" the text (if no exact hit)
            //nearest part (in correct directon) wins
            int d1 = x1 - pos.x, d2 = pos.x - x2;
            if (d1 >= 0 && d1 < def_x) {
                def = p.text_start;
                def_x = d1;
            } else if (d2 >= 0 && d2 < def_x) {
                def = p.text_start + p.text.length;
                def_x = d2;
            }
        }
        //not-exact hit; return best result
        return def;
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
