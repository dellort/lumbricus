module game.gui.welcome;

import framework.framework;
import framework.commandline;
import framework.i18n;
import common.task;
import common.common;
import common.loadsave;
import gui.widget;
import gui.container;
import gui.button;
import gui.boxcontainer;
import gui.label;
import gui.tablecontainer;
import gui.wm;
import gui.loader;
import gui.list;

//xxx this maybe shouldn't be here
class CommandButton : Button {
    private char[] mCommand;

    override protected void doClick() {
        super.doClick();
        if (mCommand)
            globals.cmdLine.execute(mCommand);
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
class WelcomeTask : Task {
    private {
        Widget mWelcome;
        Window mWindow;
        char[] mDefaultCommand;
    }

    this(TaskManager tm, char[] args = "") {
        super(tm);
        auto config = loadConfig("dialogs/welcome_gui");
        auto loader = new LoadGui(config);
        mDefaultCommand = config["default_command"];
        loader.load();

        mWelcome = loader.lookup("welcome_root");
        auto foo = new Foo();
        foo.add(mWelcome);
        mWindow = gWindowManager.createWindow(this, foo,
            r"\t(welcomescreen.caption)");
        foo.claimFocus();

        //this property is false by default
        //I just didn't want to add a tooltip label to _all_ windows yet...
        mWindow.window.showTooltipLabel = true;
    }

    void executeDefault() {
        globals.cmdLine.execute(mDefaultCommand);
    }

    class Foo : SimpleContainer {
        //xxx this hack steals all enter key presses from all children
        override bool handleChildInput(InputEvent event) {
            if (event.isKeyEvent && event.keyEvent.code == Keycode.RETURN) {
                if (event.keyEvent.isDown())
                    executeDefault();
                return true;
            }
            return super.handleChildInput(event);
        }
    }

    static this() {
        TaskFactory.register!(typeof(this))("welcomescreen");
    }
}

///Shows a list of savegames
class LoadGameTask : Task {
    private {
        Widget mLoadGame;
        Window mLoadWindow;
        StringListWidget mLoadList;
        SavegameData[] mSaves;
    }

    this(TaskManager tm, char[] args = "") {
        super(tm);
        mSaves = listAvailableSavegames();
        if (mSaves.length > 0) {
            auto loader = new LoadGui(loadConfig("dialogs/loadgame_gui"));
            loader.load();

            //load savegame dialog
            mLoadGame = loader.lookup("loadgame_root");
            loader.lookup!(Button)("ok").onClick = &loadOK;
            loader.lookup!(Button)("cancel").onClick = &loadCancel;
            mLoadList = loader.lookup!(StringListWidget)("loadlist");

            char[][] saveNames;
            foreach (ref s; mSaves) {
                saveNames ~= s.toString();
            }
            mLoadList.setContents(saveNames);
            //select the first entry
            mLoadList.selectedIndex = 0;
            mLoadWindow = gWindowManager.createWindow(this, mLoadGame,
                r"\t(loadgamescreen.caption)");
        } else {
            //xxx no savegames, error message?
            kill();
        }
    }

    void loadOK(Button sender) {
        if (mLoadList.selectedIndex < 0)
            return;
        if (mSaves[mLoadList.selectedIndex].load())
            mLoadWindow.destroy;
    }

    void loadCancel(Button sender) {
        kill();
    }

    static this() {
        TaskFactory.register!(typeof(this))("loadgame");
    }
}
