module gui.console;

import framework.commandline;
import framework.event;
import framework.font;
import gui.boxcontainer;
import gui.container;
import gui.edit;
import gui.label;
import gui.logwindow;
import gui.widget;
import gui.styles;
import utils.output;
import utils.time;
import utils.interpolate;
import utils.vector2;

//need to make this available to derived classes
class ConsoleEditLine : EditLine {
    private {
        CommandLineInstance mCmdline;
        LogWindow mLogWindow;
    }

    //if this is set, the framework.commandline tab completion is disabled
    //instead, hitting a tab character will call this delegate
    //the caller can output text or change the input line by accessing this
    //  edit widget and accessing the parent GuiConsole
    void delegate() customTabCompletion;

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
            if (customTabCompletion) {
                customTabCompletion();
            } else {
                mCmdline.tabCompletion(text, cursorPos, &editText);
            }
        } else if (infos.code == Keycode.UP) {
            selHistory(-1);
        } else if (infos.code == Keycode.DOWN) {
            selHistory(+1);
        } else if (infos.code == Keycode.PAGEUP) {
            mLogWindow.scrollBack(+1);
        } else if (infos.code == Keycode.PAGEDOWN) {
            mLogWindow.scrollBack(-1);
        } else if (infos.code == Keycode.RETURN) {
            execute();
            text = null;
        } else {
            return super.handleKeyPress(infos);
        }
        return true;
    }

    protected void execute() {
        mCmdline.execute(text);
    }
}

//Replace the text between start and end by text
//operation: newline = line[0..start] ~ text ~ line[end..$];
alias void delegate(int start, int end, string text) EditDelegate;

//line is the current line, cursor1+cursor2 are the selection/cursor-
//  position, and edit can be used to change the text
alias void delegate(string line, int cursor1, int cursor2, EditDelegate edit)
    TabCompleteDelegate;

//a generic console (basically just a LogWindow over an EditLine)
class GuiConsole : VBoxContainer {
    private {
        CommandLine mRealCmdline;
    }
    protected {
        CommandLineInstance mCmdline;
        LogWindow mLogWindow;
        ConsoleEditLine mEdit;
        Label mPrompt;
        TabCompleteDelegate mCustomTabComplete;
    }

    //cmdline: use that cmdline, if null create a new one
    this(CommandLine cmdline = null) {
        mLogWindow = new LogWindow();

        mRealCmdline = cmdline ? cmdline : new CommandLine(mLogWindow);
        mCmdline = new CommandLineInstance(mRealCmdline, mLogWindow);

        mEdit = createEdit();
        mEdit.styles.addClass("console-edit");
        add(mLogWindow);
        auto hbox = new HBoxContainer();
        mPrompt = new Label();
        mPrompt.text = "> ";
        mPrompt.styles.addClass("console-prompt");
        hbox.add(mPrompt, WidgetLayout.Noexpand());
        hbox.add(mEdit, WidgetLayout.Expand(true));
        add(hbox, WidgetLayout.Expand(true));
    }

    //if this is set, normal command tab completion is disabled
    void setTabCompletion(TabCompleteDelegate dg) {
        assert(!!dg);
        mCustomTabComplete = dg;
        mEdit.customTabCompletion = &onTabComplete;
    }

    private void onTabComplete() {
        if (!mCustomTabComplete)
            return;
        auto selection = mEdit.selection();
        mCustomTabComplete(mEdit.text, selection.start, selection.end,
            &mEdit.editText);
    }

    //needed by chatbox (whatever)
    bool editVisible() {
        return mEdit.visible;
    }
    void editVisible(bool s) {
        mEdit.visible = s;
        mPrompt.visible = s;
    }

    protected ConsoleEditLine createEdit() {
        return new ConsoleEditLine(mCmdline, mLogWindow);
    }

    final Output output() {
        return mLogWindow;
    }
    //"compatibility"
    alias output console;
    final CommandLine cmdline() {
        return mRealCmdline;
    }

    void clear() {
        mLogWindow.clear();
    }

    override void readStyles() {
        super.readStyles();
        auto newFont = styles.get!(Font)("text-font");
        mLogWindow.font = newFont;
        mLogWindow.fadeDelay = styles.get!(Time)("fade-delay");
    }

    static this() {
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
        mEdit.styles.addClass("s-console-edit");
        mPrompt.styles.addClass("s-console-prompt");

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
