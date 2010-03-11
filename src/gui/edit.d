module gui.edit;

import framework.font;
import framework.framework;
import framework.clipboard;
import gui.global;
import gui.rendertext;
import gui.widget;
import utils.array;
import utils.misc: swap, min, max;
import utils.time;
import utils.timer;
import utils.vector2;

import tango.text.Util : isSpace;
import tango.text.Unicode : isLetterOrDigit;
import str = utils.string;

///simple editline
class EditLine : Widget {
    private {
        char[] mCurline;
        uint mCursor;
        FormattedText mRender;
        FormattedText.StyleRange* mRenderSel; //render text selection
        //not necessarily mSelStart >= mSelEnd, can also be backwards
        //if they're equal, there's no selection
        //must always be valid indices into mCurline (or be == mCurline.length)
        uint mSelStart, mSelEnd;
        bool mMouseDown;
        Font mSelFont;
        bool mCursorVisible = true;
        Timer mCursorTimer;
    }

    ///text line has changed (not called when assigned to text)
    void delegate(EditLine sender) onChange;

    this() {
        mRender = new FormattedText();
        mCursorTimer = new Timer(timeMsecs(500), &onTimer);
        focusable = true;
    }

    override bool greedyFocus() { return true; }

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
                updateSelection();
            } else {
                killSelection();
            }
        }

        if (infos.code == Keycode.RIGHT) {
            if (mCursor < mCurline.length) {
                if (!ctrl) {
                    mCursor = str.charNext(mCurline, mCursor);
                } else {
                    mCursor = findNextWord(mCurline, mCursor);
                }
            }
            handleSelOnMove();
            return true;
        } else if (infos.code == Keycode.LEFT) {
            if (mCursor > 0) {
                if (!ctrl) {
                    mCursor = str.charPrev(mCurline, mCursor);
                } else {
                    mCursor = findPrevWord(mCurline, mCursor);
                }
            }
            handleSelOnMove();
            return true;
        } else if ((ctrl && infos.code == Keycode.C)   //xxx hardcoded keybinds
            || (ctrl && infos.code == Keycode.INSERT))
        {
            //copy
            clipCopy(true);
        } else if ((ctrl && infos.code == Keycode.V)
            || (shift && infos.code == Keycode.INSERT))
        {
            //paste
            clipPaste(true);
            doOnChange();
        } else if ((ctrl && infos.code == Keycode.X)
            || (shift && infos.code == Keycode.DELETE))
        {
            //cut
            clipCopy(true);
            deleteSelection();
            doOnChange();
        } else if (infos.code == Keycode.BACKSPACE) {
            if (had_sel) {
                deleteSelection();
                doOnChange();
            } else if (mCursor > 0) {
                int del = mCursor - str.charPrev(mCurline, mCursor);
                editText(mCursor - del, mCursor, "");
                doOnChange();
            }
            return true;
        } else if (infos.code == Keycode.DELETE) {
            if (had_sel) {
                deleteSelection();
                doOnChange();
            } else if (mCursor < mCurline.length) {
                int del = str.stride(mCurline, mCursor);
                editText(mCursor, mCursor + del, "");
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
            insertEvent(infos.unicode);
            return true;
        }
        return false;
    }

    protected void doOnChange() {
        if (onChange)
            onChange(this);
    }

    protected void clipCopy(bool clipboard) {
        char[] sel = selectedText();
        //don't overwrite if no selection
        if (sel.length) {
            Clipboard.copyText(clipboard, sel);
        }
    }

    protected void clipPaste(bool clipboard) {
        Clipboard.pasteText(clipboard, &onPaste);
    }

    //make sure paste events are denied after this is called (until the next
    //  time clipPaste() is called)
    //not really needed; just some robustness against asynchronous pasting
    //e.g. some app hangs -> press middle mouse button -> nothing happens
    //  -> after some time, app unhangs for some reason -> text gets pasted,
    //  although user is already doing something else
    //if clipCancel() gets called as soon as it is recognized that the user
    //  does "something else", the paste event will be ignored in this case
    protected void clipCancel() {
        Clipboard.pasteCancel(&onPaste);
    }

    private void onPaste(char[] txt) {
        //sanity checks?
        if (visible && isLinked) {
            clipInsertPaste(txt);
        }
    }

    protected void clipInsertPaste(char[] text) {
        //only text to first newline by default
        char[] txt = str.split2(text, '\n')[0];
        insertEvent(txt);
    }

    //sets mCurline[start...end-start] to replace
    //if mCursor was between start and end, it's set to end; if mCursor was
    //  after end, its value is fixed
    //onChange is not emitted
    void editText(int start, int end, char[] replace) {
        assert(start >= 0 && start <= end && end <= mCurline.length);
        debug str.validate(replace);
        killSelection();
        //xxx could be changed to inplace editing to waste less memory
        //  (but then, EditLine.text() should return a copy)
        mCurline = mCurline[0..start] ~ replace ~ mCurline[end..$];
        if (mCursor >= start) {
            mCursor = mCursor < end ? start : mCursor - (end - start);
        }
        mRender.setLiteral(mCurline);
    }

    //do everything what's typically done when text is entered by the user
    void insertEvent(char[] text) {
        deleteSelection();
        editText(mCursor, mCursor, text);
        mCursor += text.length;
        doOnChange();
    }

    ///deselect
    void killSelection() {
        if (mSelStart == 0 && mSelEnd == mSelStart)
            return;
        mSelStart = mSelEnd = 0;
        updateSelection();
    }

    //mSelStart can be higher than mSelEnd for backwards selection
    //return properly ordered selection indices
    TextRange orderedSelection() {
        auto sstart = min(mSelStart, mSelEnd);
        auto ssend = max(mSelStart, mSelEnd);
        return TextRange(sstart, ssend);
    }

    //call whenever mSelStart/mSelEnd change to update the display
    private void updateSelection() {
        //create/destroy/recreate mRenderSel as necessary
        auto sel = orderedSelection();
        bool want_sel = sel.start != sel.end;
        bool sel_ok = mRenderSel && mRenderSel.range == sel;
        if (!sel_ok || (mRenderSel && !want_sel)) {
            mRender.removeStyleRange(mRenderSel);
            mRenderSel = null;
        }
        if (!sel_ok && want_sel) {
            mRenderSel = mRender.addStyleRange(sel, mSelFont);
        }

        clipCancel();
    }

    //deselect and remove selected text + fixup cursor
    //private because it doesn't call doOnChange() (this is done later)
    private void deleteSelection() {
        auto sel = orderedSelection();
        editText(sel.start, sel.end, "");
        killSelection();
    }

    char[] selectedText() {
        auto sel = orderedSelection();
        return mCurline[sel.start..sel.end];
    }

    ///byteindex into text at the given pixel pos
    private uint indexAt(Vector2i pos) {
        return mRender.indexFromPosFuzzy(pos);
    }

    override bool onKeyDown(KeyInfo info) {
        if (handleKeyPress(info)) {
            //make cursor visible when a keypress was handled
            mCursorVisible = true;
            mCursorTimer.reset();
            return true;
        }
        if (info.code == Keycode.MOUSE_LEFT) {
            mMouseDown = true;
            //set cursor pos according to click
            mCursor = indexAt(mousePos);
            mSelStart = mSelEnd = mCursor;
            updateSelection();
            //make cursor visible
            mCursorVisible = true;
            mCursorTimer.reset();
            return true;
        }
        if (info.code == Keycode.MOUSE_MIDDLE) {
            //X11 style mouse pasting
            mCursor = indexAt(mousePos);
            mSelStart = mSelEnd = mCursor;
            updateSelection();
            clipPaste(false);
        }
        return false;
    }

    override void onKeyUp(KeyInfo info) {
        if (info.isMouseButton)
            mMouseDown = false;
    }

    override void onMouseMove(MouseInfo info) {
        if (mMouseDown) {
            mSelEnd = indexAt(mousePos);
            mCursor = mSelEnd;
            updateSelection();
            //X11-style mouse selection clipboard
            clipCopy(false);
        }
    }

    override Vector2i layoutSizeRequest() {
        //return Vector2i(0, mRender.textSize().y);
        return Vector2i(0, mRender.font.textSize("W").y);
    }

    override void layoutSizeAllocation() {
        super.layoutSizeAllocation();
        mRender.setArea(size, -1, -1);
    }

    override void onDraw(Canvas c) {
        mRender.draw(c, Vector2i(0));

        if (focused) {
            mCursorTimer.enabled = true;
            if (mCursorVisible && !mMouseDown) {
                Rect2i rc = mRender.getCursorPos(mCursor);
                c.drawFilledRect(rc.p1, Vector2i(rc.p1.x+1, rc.p2.y),
                    mRender.font.properties.fore_color);
            }
            mCursorTimer.update();
        } else {
            mCursorVisible = true;
            mCursorTimer.enabled = false;
        }
    }

    override void onDrawFocus(Canvas c) {
        //don't draw anything; there's the blinking cursor to show focus
    }

    private void onTimer(Timer sender) {
        mCursorVisible = !mCursorVisible;
    }

    public char[] text() {
        return mCurline;
    }
    public void text(char[] newtext) {
        editText(0, mCurline.length, newtext);
    }

    public uint cursorPos() {
        return mCursor;
    }
    public void cursorPos(uint newPos) {
        mCursor = newPos;
        if (mCursor > mCurline.length)
            mCursor = mCurline.length;
    }

    override void readStyles() {
        super.readStyles();

        mRender.font = styles.get!(Font)("text-font");

        //selected-text font; only the colors can be changed
        auto props = mRender.font.properties;
        props.fore_color = styles.get!(Color)("selection-foreground");
        props.back_color = styles.get!(Color)("selection-background");
        mSelFont = gFontManager.create(props);
    }

    override void loadFrom(GuiLoader loader) {
        auto node = loader.node;

        text = loader.locale()(node.getStringValue("text", mCurline));

        super.loadFrom(loader);
    }

    static this() {
        WidgetFactory.register!(typeof(this))("editline");
    }
}

//xxx this should actually do scrolling or something
class MultilineEdit : EditLine {
    this() {
        //just for fun
        mRender.shrink = ShrinkMode.wrap;
    }

    override void clipInsertPaste(char[] text) {
        //no need to remove newlines in multiline mode
        insertEvent(text);
    }

    override bool handleKeyPress(KeyInfo infos) {
        if (infos.code == Keycode.RETURN) {
            insertEvent("\n");
            return true;
        }
        return super.handleKeyPress(infos);
    }
}

private:

//a word is anything for which isUniAlpha() is true
//the functions jump over sequences of words and not-words
//if there are spaces, the cursor is positioned at the start of the sequence
//both are just helpers and require "pos" not to be at the end resp. beginning

uint findNextWord(char[] astr, uint pos) {
    bool what = isWord(astr, pos);
    while (pos < astr.length) {
        pos = str.charNext(astr, pos);
        if (pos >= astr.length)
            break;
        if (isWord(astr, pos) != what || isSpaceAt(astr, pos))
            break;
    }
    //but overjump spaces, if any
    while (pos < astr.length && isSpaceAt(astr, pos))
        pos = str.charNext(astr, pos);
    return pos;
}

uint findPrevWord(char[] astr, uint pos) {
    pos = str.charPrev(astr, pos);
    //overjump spaces, if any
    while (pos > 0 && isSpaceAt(astr, pos))
        pos = str.charPrev(astr, pos);
    bool what = isWord(astr, pos);
    while (pos > 0) {
        auto npos = str.charPrev(astr, pos);
        if (isWord(astr, npos) != what || isSpaceAt(astr, npos))
            break;
        pos = npos;
    }
    return pos;
}

//little helpers
bool isSpaceAt(char[] s, size_t pos) {
    return isSpace(str.decode(s, pos));
}
bool isWord(char[] s, size_t pos) {
    return isLetterOrDigit(str.decode(s, pos));
}
