//independent from GUI (just as renderbox.d)
module gui.rendertext;

import framework.framework;
import framework.font;
import framework.i18n;
import gui.renderbox;
import utils.configfile;
import utils.misc;
import utils.rect2;
import utils.vector2;

import time = utils.time;
import strparser = utils.strparser;
import str = utils.string;
import math = tango.math.Math;

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
        BoxProperties mBorder;
    }

    this() {
        mRootStyle.font = gFontManager.loadFont("default");
        mTranslator = localeRoot();
        mBorder.enabled = false;
    }

    /+void opAssign(char[] txt) {
        setMarkup(txt);
    }+/

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
            auto breaks = str.split2(txt, '\n');
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
            pmsg.style.font = gFontManager.loadFont("txt_error");
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
            } catch (strparser.ConversionException e) {
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

    //like setText(), but build the string with format()
    //if the resulting string is the same as the last string set, no further
    //  work is done (and if the string is small and the format string doesn't
    //  trigger any toString()s, no memory is allocated)
    void setTextFmt(bool as_markup, char[] fmt, ...) {
        setTextFmt_fx(as_markup, fmt, _arguments, _argptr);
    }

    void setTextFmt_fx(bool as_markup, char[] fmt,
        TypeInfo[] arguments, va_list argptr)
    {
        //tries not to change anything if the text to be set is the same

        char[80] buffer = void;
        char[] res = formatfx_s(buffer, fmt, arguments, argptr);
        if (mTextIsFormatted == as_markup && mText == res)
            return;
        //formatfx_s allocates on the heap if buffer isn't big enough
        //so .dup is only needed if res still points to that static buffer
        if (res.ptr is buffer.ptr)
            res = res.dup;
        setText(res, as_markup);
    }

    void getText(out bool as_markup, out char[] data) {
        as_markup = mTextIsFormatted;
        data = mText;
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

        if (mBorder.enabled) {
            //duplicated from widget.d
            int borderw = mBorder.borderWidth + mBorder.cornerRadius/3;
            foreach (ref p; mParts) {
                p.pos += Vector2i(borderw);
            }
            mSize += Vector2i(borderw*2);
        }
    }

    void draw(Canvas c, Vector2i pos) {
        if (mBorder.enabled) {
            drawBox(c, pos, mSize, mBorder);
        }

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
