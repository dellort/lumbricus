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

///First thing the user sees, shows a selection of possible actions
///Also contains a dialog to show a list of savegames
class WelcomeTask : Task {
    private {
        Widget mWelcome, mLoadGame;
        Window mWindow, mLoadWindow;
        StringListWidget mLoadList;
    }

    this(TaskManager tm) {
        super(tm);
        auto loader = new LoadGui(gFramework.loadConfig("welcome_gui"));
        loader.load();

        //main window
        mWelcome = loader.lookup("welcome_root");
        loader.lookup!(Button)("quickgame").onClick = &quickGame;
        loader.lookup!(Button)("setupgame").onClick = &setupGame;
        loader.lookup!(Button)("loadgame").onClick = &loadGame;
        loader.lookup!(Button)("leveleditor").onClick = &levelEditor;
        loader.lookup!(Button)("quit").onClick = &quitGame;

        //load savegame dialog
        mLoadGame = loader.lookup("loadgame_root");
        loader.lookup!(Button)("ok").onClick = &loadOK;
        loader.lookup!(Button)("cancel").onClick = &loadCancel;
        mLoadList = loader.lookup!(StringListWidget)("loadlist");

        mWindow = gWindowManager.createWindow(this, mWelcome,
            _("welcomescreen.caption"));
    }

    //--------------------------------------------------------------------
    //WelcomeScreen event handlers

    //start a game with default settings, no more questions
    void quickGame(Button sender) {
        //xxx prevent multiple instances
        new GameTask(manager);
    }

    //show the game setup dialog
    void setupGame(Button sender) {
        //xxx lol, this is all we got
        new LevelPreviewTask(manager);
    }

    //show the savegame dialog
    void loadGame(Button sender) {
        char[][] saves = listAvailableSavegames();
        if (saves.length > 0) {
            mLoadList.setContents(saves);
            //select the first entry
            mLoadList.selectedIndex = 0;
            mLoadWindow = gWindowManager.createWindow(this, mLoadGame,
                _("welcomescreen.loadcaption"));
            mLoadWindow.onClose = &loadOnClose;
        } else {
            //xxx no savegames, error message?
        }
    }

    //start level editor
    void levelEditor(Button sender) {
        new LevelEditor(manager);
    }

    void quitGame(Button sender) {
        gFramework.terminate();
    }

    //--------------------------------------------------------------------
    //Load savegame dialog event handlers

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
        mLoadWindow.destroy;
    }

    //just to prevent the task from closing
    bool loadOnClose(Window sender) {
        return true;
    }

    //--------------------------------------------------------------------

    static this() {
        TaskFactory.register!(typeof(this))("welcomescreen");
    }
}

