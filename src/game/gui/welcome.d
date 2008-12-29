module game.gui.welcome;

import framework.framework;
import framework.i18n;
import common.task;
import common.common;
import gui.widget;
import gui.container;
import gui.button;
import gui.boxcontainer;
import gui.label;
import gui.tablecontainer;
import gui.wm;
import gui.loader;
import gui.list;
import game.gamepublic;
import game.gametask;
import game.gui.preview;
import game.gui.leveledit;
import game.setup;

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
    }

    this(TaskManager tm) {
        super(tm);
        auto loader = new LoadGui(gFramework.loadConfig("welcome_gui"));
        loader.load();

        mWelcome = loader.lookup("welcome_root");
        mWindow = gWindowManager.createWindow(this, mWelcome,
            _("welcomescreen.caption"));
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
    }

    this(TaskManager tm) {
        super(tm);
        char[][] saves = listAvailableSavegames();
        if (saves.length > 0) {
            auto loader = new LoadGui(gFramework.loadConfig("loadgame_gui"));
            loader.load();

            //load savegame dialog
            mLoadGame = loader.lookup("loadgame_root");
            loader.lookup!(Button)("ok").onClick = &loadOK;
            loader.lookup!(Button)("cancel").onClick = &loadCancel;
            mLoadList = loader.lookup!(StringListWidget)("loadlist");

            mLoadList.setContents(saves);
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
        GameConfig cfg;
        if (loadSavegame(mLoadList.contents[mLoadList.selectedIndex],cfg)) {
            //xxx see above
            new GameTask(manager, cfg);
            mLoadWindow.destroy;
        }
    }

    void loadCancel(Button sender) {
        kill();
    }

    static this() {
        TaskFactory.register!(typeof(this))("loadgame");
    }
}
