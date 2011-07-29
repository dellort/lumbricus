//host the global console widget
//right now, there are two global consoles, one here and one in toplevel.d
//the one in toplevel.d should probably be removed (?)
module common.globalconsole;

import framework.commandline;
import framework.i18n;
import gui.console;
import gui.chatbox;
import gui.widget;
import gui.window;
import utils.log;
import utils.misc;
import utils.mybox;
import utils.output;
import utils.vector2;

//global list of commands (variable is read only, object is read/write)
CommandBucket gCommands;

alias void delegate(string) InputDelegate;

enum string cConsoleTagTS = "console.inputmodes";

private {
    LogBackend gLogBackendGui;
    Chatbox gConsoleWidget;
    //a "tag" that tells the current input mode (see setConsoleMode())
    string gModeCurrent;
    //delegate for the current mode where all input is delivered to
    InputDelegate gModeInput;
    //tab completion handler for the current mode
    TabCompleteDelegate gModeTabHandler;
}

static this() {
    gCommands = new CommandBucket();
    gCommands.onGetSubCommands = toDelegate(&onGetWindowCommands);
    gLogBackendGui = new LogBackend("gui", LogPriority.Notice, null);
}

//this is a bit silly and only needed because in D global functions can't be
//  easily turned into delegates
//not using utils.output because that is legacy crap
struct ConsoleOutput {
    void writef(T...)(cstring fmt, T args) {
        writef_ind(fmt, args);
    }
    void writefln(T...)(cstring fmt, T args) {
        writef_ind(fmt, args);
        writef("\n");
    }
    void writeString(cstring text) {
        writef("%s", text);
    }

    private void writef_ind(T...)(cstring fmt, T args) {
        if (gConsoleWidget) {
            gConsoleWidget.output.writef_ind(false, fmt, args);
        } else {
            //does this happen at all? (but it's easy to support)
            gLog.notice("console output: %s",
                myformat(fmt, args));
        }
    }
}

//e.g. gConsoleOut.writefln("hello"); -> appears on the console
//be aware that this will interpret format tags as described in gui.rendertext
ConsoleOutput gConsoleOut;

//call once to create the global console
//(taking a MainFrame as argument => don't need to import gui_init)
//xxx: zorder is a hack
void initConsole(MainFrame mf, int zorder) {
    assert(!gConsoleWidget);

    gConsoleWidget = new Chatbox();
    gCommands.registerCommand("activate_chatbox", toDelegate(&onActivate), "");
    auto cmds = gConsoleWidget.cmdline.commands;
    cmds.addSub(gCommands);
    cmds.registerCommand("input", toDelegate(&onExecConsole), "text goes here",
        ["text..."]);
    gConsoleWidget.cmdline.setPrefix("/", "input");
    gConsoleWidget.setTabCompletion(toDelegate(&onTabComplete));
    gConsoleWidget.zorder = zorder;
    mf.add(gConsoleWidget, WidgetLayout.Aligned(-1, -1, Vector2i(5, 5)));

    gLogBackendGui.sink = toDelegate(&logGui);
}

//xxx don't use
CommandLine getCommandLine() {
    assert(!!gConsoleWidget);
    return gConsoleWidget.cmdline;
}

//set how console input should be handled (if the user inputs something
//  starting with '/', it's alway taken as "command line" input)
//tag = symbolic tag that will be translated via the cConsoleTagTS namespace
//on_input = delegate the input is delivered to
//after this, you may want to call setConsoleTabHandler() to enable auto
//  completion with the tab key
//when the thing the delegate refers to is destroyed, disableConsoleMode
//  should be used to unset the mode!
void setConsoleMode(string tag, InputDelegate on_input) {
    auto old_mode = gModeCurrent;

    //remove old one
    disableConsoleMode(gModeInput);

    //install new one
    gModeCurrent = tag;
    gModeInput = on_input;

    //user notification
    if (old_mode != gModeCurrent)
        gConsoleOut.writefln(r"\i%s", translate("console.switch_input_mode",
            translate(cConsoleTagTS ~ "." ~ gModeCurrent)));
}

void activateConsole() {
    if (gConsoleWidget)
        gConsoleWidget.activate();
}

//unset a mode installed via setConsoleMode()
//if on_input is not the current mode handler, nothing happens
void disableConsoleMode(InputDelegate on_input) {
    if (on_input !is gModeInput)
        return;

    gModeCurrent = "";
    gModeInput = null;
    gModeTabHandler = null;
}

//enable tab completion for the current input mode
void setConsoleTabHandler(TabCompleteDelegate on_tab) {
    gModeTabHandler = on_tab;
}

//some code needs this, I'd consider this mostly legacy crap
void executeGlobalCommand(cstring cmd) {
    if (gConsoleWidget) {
        gConsoleWidget.cmdline.execute(("/" ~ cmd).idup);
    } else {
        //no GUI and no cmdline in early initialization
        gLog.error("Can't execute command at this stage: %s", cmd);
    }
}

private void onExecConsole(MyBox[] args, Output output) {
    string text = args[0].unbox!(string)();
    if (gModeInput) {
        gModeInput(text);
    } else {
        gLog.error("No input mode set, don't know what this is: '%s'", text);
    }
}

private void onActivate(MyBox[] args, Output output) {
    activateConsole();
}

private void onTabComplete(cstring line, size_t cursor1, size_t cursor2,
    EditDelegate edit)
{
    //xxx: somehow should call CommandLine tabhandler if the line starts with
    //  '/' in order to properly auto-complete these
    if (gModeTabHandler)
        gModeTabHandler(line, cursor1, cursor2, edit);
}

private void logGui(LogEntry e) {
    writeColoredLogEntry(&gConsoleOut.writeString, e, false);
}

private CommandBucket onGetWindowCommands() {
    if (!gWindowFrame)
        return null;
    auto window = gWindowFrame.activeWindow();
    if (!window)
        return null;
    return window.commands;
}
