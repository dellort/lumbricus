module game.gui.welcome;

import framework.framework;
import framework.commandline;
import framework.i18n;
import common.task;
import common.common;
import gui.widget;
import gui.container;
import gui.button;
import gui.boxcontainer;
import gui.label;
import gui.tablecontainer;
import gui.window;
import gui.loader;
import gui.list;

//xxx this maybe shouldn't be here
class CommandButton : Button {
    private char[] mCommand;

    override protected void doClick() {
        super.doClick();
        if (mCommand)
            globals.real_cmdLine.execute(mCommand);
    }

    override void loadFrom(GuiLoader loader) {
        super.loadFrom(loader);
        mCommand = loader.node["command"];
    }

    static this() {
        WidgetFactory.register!(typeof(this))("commandbutton");
    }
}

///First thing the user sees, shows a selection of possible actions
///Just a list of buttons that run console commands
class WelcomeTask {
    private {
        Widget mWelcome;
        WindowWidget mWindow;
        char[] mDefaultCommand;
    }

    this(char[] args = "") {
        auto config = loadConfig("dialogs/welcome_gui.conf");
        auto loader = new LoadGui(config);
        mDefaultCommand = config["default_command"];
        loader.load();

        mWelcome = loader.lookup("welcome_root");
        mWindow = gWindowFrame.createWindow(mWelcome,
            r"\t(welcomescreen.caption)");
        mWelcome.claimFocus();

        //this property is false by default
        //I just didn't want to add a tooltip label to _all_ windows yet...
        mWindow.showTooltipLabel = true;
    }

    static this() {
        registerTaskClass!(typeof(this))("welcomescreen");
    }
}
