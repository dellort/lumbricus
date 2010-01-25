module gui.console;

import framework.commandline;
import framework.framework;
import framework.font;
import framework.event;
import gui.boxcontainer;
import gui.container;
import gui.edit;
import gui.logwindow;
import gui.widget;
import gui.styles;
import utils.output;
import utils.time;
import utils.interpolate;

//need to make this available to derived classes
class ConsoleEditLine : EditLine {
    private {
        CommandLineInstance mCmdline;
        LogWindow mLogWindow;
    }

    this(CommandLineInstance cmd, LogWindow logWin) {
        mCmdline = cmd;
        mLogWindow = logWin;
    }

    private void selHistory(int dir) {
        text = mCmdline.selectHistory(text, dir);
        cursorPos = text.length;
    }

    override protected bool handleKeyPress(KeyInfo infos) {
        if (infos.code == Keycode.TAB) {
            auto txt = text.dup;
            mCmdline.tabCompletion(txt, cursorPos,
                (int start, int end, char[] ins) {
                    txt = txt[0..start] ~ ins ~ txt[end..$];
                    //set text and put cursor at end of completion
                    text = txt;
                    cursorPos = start + ins.length;
                }
            );
        } else if (infos.code == Keycode.UP) {
            selHistory(-1);
        } else if (infos.code == Keycode.DOWN) {
            selHistory(+1);
        } else if (infos.code == Keycode.PAGEUP) {
            mLogWindow.scrollBack(+1);
        } else if (infos.code == Keycode.PAGEDOWN) {
            mLogWindow.scrollBack(-1);
        } else if (infos.code == Keycode.RETURN) {
            mCmdline.execute(text);
            text = null;
        } else {
            return super.handleKeyPress(infos);
        }
        return true;
    }
}

//a generic console (basically just a LogWindow over an EditLine)
class GuiConsole : BoxContainer {
    private {
        CommandLine mRealCmdline;
    }
    protected {
        CommandLineInstance mCmdline;
        LogWindow mLogWindow;
        EditLine mEdit;
    }

    //cmdline: use that cmdline, if null create a new one
    this(CommandLine cmdline = null) {
        super(false);

        mLogWindow = new LogWindow();

        mRealCmdline = cmdline ? cmdline : new CommandLine(mLogWindow);
        mCmdline = new CommandLineInstance(mRealCmdline, mLogWindow);

        mEdit = createEdit();
        add(mLogWindow);
        add(mEdit, WidgetLayout.Expand(true));
    }

    protected EditLine createEdit() {
        auto ret = new ConsoleEditLine(mCmdline, mLogWindow);
        ret.prompt = "> ";
        return ret;
    }

    final Output output() {
        return mLogWindow;
    }
    //"compatibility"
    alias output console;
    final CommandLine cmdline() {
        return mRealCmdline;
    }

    override void readStyles() {
        super.readStyles();
        auto props = styles.get!(FontProperties)("text-font");
        auto newFont = gFontManager.create(props);
        mLogWindow.font = newFont;
        mEdit.font = newFont;
        mLogWindow.fadeDelay = styles.get!(Time)("fade-delay");
    }

    static this() {
        styleRegisterTime("fade-delay");
        WidgetFactory.register!(typeof(this))("console");
    }
}

//the global console: can be slided away to the top, and will claim
//  and release focus according to visibility
class SystemConsole : GuiConsole {
    private {
        InterpolateExp!(float) mPosInterp;
    }

    //cmdline: use that cmdline, if null create a new one
    this(CommandLine cmdline = null) {
        super(cmdline);
        styles.addClass("systemconsole");

        consoleVisible = false; //system console hidden by default
    }

    private void changeHeight() {
        int edge = findParentBorderDistance(0, -1, true);
        setAddToPos(Vector2i(0, -cast(int)(mPosInterp.value*edge)));
    }

    override void simulate() {
        changeHeight();

        //make a global console go away if unfocused
        if (!subFocused() && consoleVisible())
            toggle(); //consoleVisible = false;

        super.simulate();
    }

    ///show console
    public void show() {
        mPosInterp.setParams(1.0f, 0);
        updateVisible();
    }

    ///hide console
    public void hide() {
        mPosInterp.setParams(0, 1.0f);
        updateVisible();
    }

    ///toggle display of console
    public void toggle() {
        mPosInterp.revert();
        updateVisible();
    }

    public bool consoleVisible() {
        return mPosInterp.target == 0;
    }

    ///force toggle/visibility state
    void consoleVisible(bool set) {
        mPosInterp.init_done(timeSecs(0.4), set ? 1 : 0, set ? 0 : 1);
        changeHeight();
        updateVisible();
    }

    //called when visibility changes
    private void updateVisible() {
        //disable to let mouse-clicks through
        enabled = consoleVisible();
        mEdit.pollFocusState();
        if (consoleVisible()) {
            mEdit.claimFocus();
        }
    }

    //no focus to edit when console is hidden
    override bool allowSubFocus() {
        return consoleVisible();
    }
}
