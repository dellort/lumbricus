module gui.edit;

import framework.font;
import framework.framework;
import gui.widget;
import utils.array;
import utils.misc: swap, min, max;
import utils.time;
import utils.timer;
import utils.vector2;

import tango.text.Util : isSpace;
import tango.text.Unicode : isLetterOrDigit;
import utf = stdx.utf;

///simple editline
class EditLine : Widget {
    private {
        char[] mCurline, mPrompt;
        uint mCursor;
        //not necessarily mSelStart >= mSelEnd, can also be backwards
        //if they're equal, there's no selection
        //must always be valid indices into mCurline (or be == mCurline.length)
        uint mSelStart, mSelEnd;
        bool mMouseDown;
        Font mFont, mSelFont;
        bool mCursorVisible = true;
        Timer mCursorTimer;
        //colors for text selection, other font props remain unchanged
        Color mSelFore = Color(1.0, 1.0, 1.0),mSelBack = Color(0.05, 0.15, 0.4);
    }

    ///text line has changed (not called when assigned to text)
    void delegate(EditLine sender) onChange;

    this() {
        font = gFramework.getFont("editline");
        mCursorTimer = new Timer(timeMsecs(500), &onTimer);
    }

    protected bool handleKeyPress(KeyInfo infos) {
        bool ctrl = modifierIsSet(infos.mods, Modifier.Control);
        bool shift = modifierIsSet(infos.mods, Modifier.Shift);
        bool had_sel = mSelStart != mSelEnd;
        uint oldcursor = mCursor;

        void handleSelOnMove() {
            if (shift) {
                mSelEnd = mCursor;
                if (!had_sel)
                    mSelStart = oldcursor;
            } else {
                killSelection();
            }
        }

        if (infos.code == Keycode.RIGHT) {
            if (mCursor < mCurline.length) {
                if (!ctrl) {
                    mCursor = charNext(mCurline, mCursor);
                } else {
                    mCursor = findNextWord(mCurline, mCursor);
                }
            }
            handleSelOnMove();
            return true;
        } else if (infos.code == Keycode.LEFT) {
            if (mCursor > 0) {
                if (!ctrl) {
                    mCursor = charPrev(mCurline, mCursor);
                } else {
                    mCursor = findPrevWord(mCurline, mCursor);
                }
            }
            handleSelOnMove();
            return true;
        } else if (infos.code == Keycode.BACKSPACE) {
            if (had_sel) {
                deleteSelection();
                doOnChange();
            } else if (mCursor > 0) {
                killSelection();
                int del = mCursor - charPrev(mCurline, mCursor);
                mCurline = mCurline[0 .. mCursor-del] ~ mCurline[mCursor .. $];
                mCursor -= del;
                doOnChange();
            }
            return true;
        } else if (infos.code == Keycode.DELETE) {
            if (had_sel) {
                deleteSelection();
                doOnChange();
            } else if (mCursor < mCurline.length) {
                killSelection();
                int del = utf.stride(mCurline, mCursor);
                mCurline = mCurline[0 .. mCursor] ~ mCurline[mCursor+del .. $];
                doOnChange();
            }
            return true;
        } else if (infos.code == Keycode.HOME) {
            mCursor = 0;
            handleSelOnMove();
            return true;
        } else if (infos.code == Keycode.END) {
            mCursor = mCurline.length;
            handleSelOnMove();
            return true;
        } else if (infos.isPrintable()) {
            char[] append;
            if (!utf.isValidDchar(infos.unicode)) {
                append = "?";
            } else {
                append = utf.toUTF8([infos.unicode]);
            }
            deleteSelection();
            mCurline = mCurline[0 .. mCursor] ~ append ~ mCurline[mCursor .. $];
            mCursor += utf.stride(mCurline, mCursor);
            doOnChange();
            return true;
        }
        return false;
    }

    private void doOnChange() {
        if (onChange)
            onChange(this);
    }

    ///deselect
    void killSelection() {
        mSelStart = mSelEnd = 0;
    }

    //deselect and remove selected text + fixup cursor
    //private because it doesn't call doOnChange() (this is done later)
    private void deleteSelection() {
        auto sstart = min(mSelStart, mSelEnd);
        auto ssend = max(mSelStart, mSelEnd);
        mCurline = mCurline[0..sstart] ~ mCurline[ssend..$];
        if (mCursor >= sstart) {
            mCursor = mCursor < ssend ? sstart : mCursor - (ssend - sstart);
        }
        mSelEnd = mSelStart = 0;
    }

    ///byteindex into text at pixel pos x
    uint indexAtX(int x) {
        return mFont.findIndex(mCurline, x - mFont.textSize(mPrompt).x);
    }

    override void onKeyEvent(KeyInfo info) {
        if (info.isPress && handleKeyPress(info)) {
            //make cursor visible when a keypress was handled
            mCursorVisible = true;
            mCursorTimer.reset();
            return;
        }
        if (info.isMouseButton) { //take focus when clicked
            if (!info.isPress && info.code == Keycode.MOUSE_LEFT) {
                mMouseDown = info.isDown;
                if (mMouseDown) {
                    //set cursor pos according to click
                    mCursor = indexAtX(mousePos.x);
                    mSelStart = mSelEnd = mCursor;
                    //make cursor visible
                    mCursorVisible = true;
                    mCursorTimer.reset();
                }
            }
            claimFocus();
            return;
        }
    }

    override void onMouseMove(MouseInfo info) {
        if (mMouseDown) {
            mSelEnd = indexAtX(mousePos.x);
            mCursor = mSelEnd;
        }
    }

    override Vector2i layoutSizeRequest() {
        return mFont.textSize("hallo");
    }

    override bool canHaveFocus() {
        return true;
    }

    override void onDraw(Canvas c) {
        auto pos = mFont.drawText(c, Vector2i(0), mPrompt);
        auto promptsize = pos.x;

        auto sstart = min(mSelStart, mSelEnd);
        auto ssend = max(mSelStart, mSelEnd);
        pos = mFont.drawText(c, pos, mCurline[0..sstart]);
        pos = mSelFont.drawText(c, pos, mCurline[sstart..ssend]);
        pos = mFont.drawText(c, pos, mCurline[ssend..$]);

        if (focused) {
            mCursorTimer.enabled = true;
            if (mCursorVisible && !mMouseDown) {
                auto offs = mFont.textSize(mCurline[0..mCursor]);
                offs.x += promptsize;
                c.drawFilledRect(offs.X, offs + Vector2i(1, 0),
                    mFont.properties.fore);
            }
            mCursorTimer.update();
        } else {
            mCursorVisible = true;
            mCursorTimer.enabled = false;
        }
    }

    private void onTimer(Timer sender) {
        mCursorVisible = !mCursorVisible;
    }

    public char[] text() {
        return mCurline;
    }
    public void text(char[] newtext) {
        debug utf.validate(newtext); //only valid utf plz
        mCurline = newtext.dup;
        mCursor = 0;
        mSelStart = mSelEnd = 0;
    }

    public char[] prompt() {
        return mPrompt;
    }
    public void prompt(char[] newprompt) {
        mPrompt = newprompt;
    }

    public uint cursorPos() {
        return mCursor;
    }
    public void cursorPos(uint newPos) {
        mCursor = newPos;
        if (mCursor > mCurline.length)
            mCursor = mCurline.length;
    }

    Font font() {
        return mFont;
    }
    void font(Font nfont) {
        assert(!!nfont);
        mFont = nfont;

        //selected-text font; only the colors can be changed
        auto props = mFont.properties;
        props.fore = mSelFore;
        props.back = mSelBack;
        mSelFont = new Font(props);

        needResize(true);
    }

    override void loadFrom(GuiLoader loader) {
        auto node = loader.node;

        auto fnt = gFramework.fontManager.loadFont(
            node.getStringValue("font"), false);
        if (fnt)
            font = fnt;

        mCurline = loader.locale()(node.getStringValue("text", mCurline));
        mPrompt = node.getStringValue("prompt", mPrompt);

        super.loadFrom(loader);
    }

    static this() {
        WidgetFactory.register!(typeof(this))("editline");
    }
}

private:

//a word is anything for which isUniAlpha() is true
//the functions jump over sequences of words and not-words
//if there are spaces, the cursor is positioned at the start of the sequence
//both are just helpers and require "pos" not to be at the end resp. beginning

uint findNextWord(char[] str, uint pos) {
    bool what = isWord(str, pos);
    while (pos < str.length) {
        pos = charNext(str, pos);
        if (isWord(str, pos) != what || isSpaceAt(str, pos))
            break;
    }
    //but overjump spaces, if any
    while (pos < str.length && isSpaceAt(str, pos))
        pos = charNext(str, pos);
    return pos;
}

uint findPrevWord(char[] str, uint pos) {
    pos = charPrev(str, pos);
    //overjump spaces, if any
    while (pos > 0 && isSpaceAt(str, pos))
        pos = charPrev(str, pos);
    bool what = isWord(str, pos);
    while (pos > 0) {
        auto npos = charPrev(str, pos);
        if (isWord(str, npos) != what || isSpaceAt(str, npos))
            break;
        pos = npos;
    }
    return pos;
}

//little helpers
bool isSpaceAt(char[] s, size_t pos) {
    return isSpace(utf.decode(s, pos));
}
bool isWord(char[] s, size_t pos) {
    return isLetterOrDigit(utf.decode(s, pos));
}
