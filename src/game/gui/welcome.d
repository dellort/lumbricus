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
import game.gametask;  //xxx

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
        static bool cmdregistered;
        char[] mDefaultCommand;
    }

    this(TaskManager tm) {
        super(tm);
        auto config = gFramework.loadConfig("welcome_gui");
        auto loader = new LoadGui(config);
        mDefaultCommand = config["default_command"];
        loader.load();

        mWelcome = loader.lookup("welcome_root");
        auto foo = new Foo();
        foo.add(mWelcome);
        mWindow = gWindowManager.createWindow(this, foo,
            _("welcomescreen.caption"));
        foo.claimFocus();

        if (!cmdregistered) {
            cmdregistered = true;
            globals.cmdLine.registerCommand(Command("game_pseudonet",
                &cmdPseudoNetGame, "start a pseudo networked game"));
        }
    }

    private void cmdPseudoNetGame(MyBox[] args, Output write) {
        new GameTask(manager(), true);
    }

    void executeDefault() {
        globals.cmdLine.execute(mDefaultCommand);
    }

    class Foo : SimpleContainer {
        //xxx this hack steals all enter key presses from all children
        override bool allowInputForChild(Widget child, InputEvent event) {
            if (event.isKeyEvent && event.keyEvent.code == Keycode.RETURN)
                return false;
            return super.allowInputForChild(child, event);
        }

        override void onKeyEvent(KeyInfo info) {
            if (info.isPress() && info.code == Keycode.RETURN)
                executeDefault();
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

    this(TaskManager tm) {
        super(tm);
        mSaves = listAvailableSavegames();
        if (mSaves.length > 0) {
            auto loader = new LoadGui(gFramework.loadConfig("loadgame_gui"));
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
                _("loadgamescreen.caption"));
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
