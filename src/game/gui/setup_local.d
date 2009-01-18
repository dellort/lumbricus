module game.gui.setup_local;

import framework.framework;
import framework.i18n;
import common.task;
import common.common;
import common.visual;
import game.gfxset;
import game.gametask;
import game.setup;
import game.levelgen.generator;
import game.levelgen.level;
import game.gui.preview;
import game.gui.teamedit;
import gui.widget;
import gui.edit;
import gui.dropdownlist;
import gui.button;
import gui.wm;
import gui.loader;
import gui.list;
import utils.configfile;

import std.thread;
import str = std.string;

class LocalGameSetupTask : Task {
    private {
        Widget mSetup, mWaiting;
        Window mWindow;
        DropDownList mSavedLevels;
        DropDownList mTemplates;
        Button mLevelBtn;

        LevelGeneratorShared mGenerator;
        LevelGenerator mCurrentLevel;
        TeamEditorTask mTeameditTask;
        StringListWidget mAllTeams;

        Window mLevelWindow;
        LevelSelector mSelector;

        //background level rendering thread *g*
        LvlGenThread mThread;
        bool mThWaiting = false;
        Task mGame;

        const cSavedLevelsPath = "storedlevels/";
        const cLastlevelConf = "lastlevel";
    }

    this(TaskManager tm) {
        super(tm);

        mGenerator = new LevelGeneratorShared();

        auto config = gFramework.loadConfig("localgamesetup_gui");
        auto loader = new LoadGui(config);
        loader.load();
        loader.lookup!(Button)("cancel").onClick = &cancelClick;
        loader.lookup!(Button)("go").onClick = &goClick;
        loader.lookup!(Button)("editteams").onClick = &editteamsClick;

        mLevelBtn = loader.lookup!(Button)("btn_level");
        mLevelBtn.onClick = &levelClick;
        mLevelBtn.onRightClick = &levelRightClick;

        mSavedLevels = loader.lookup!(DropDownList)("dd_level");
        char[][] storedlevels;
        storedlevels ~= _("gamesetup.lastplayed");
        gFramework.fs.listdir(cSavedLevelsPath, "*.conf", false, (char[] fn) {
            storedlevels ~= fn[0..$-5];
            return true;
        });
        mSavedLevels.list.setContents(storedlevels);
        mSavedLevels.selection = _("gamesetup.lastplayed");
        mSavedLevels.onSelect = &levelSelect;

        mTemplates = loader.lookup!(DropDownList)("dd_templates");
        mTemplates.selection = "TODO";

        mAllTeams = loader.lookup!(StringListWidget)("list_allteams");

        mSetup = loader.lookup("gamesetup_root");
        mWaiting = loader.lookup("waiting_root");
        mWindow = gWindowManager.createWindow(this, mSetup,
            _("gamesetup.caption_local"));

        loadLastPlayedLevel();
        loadTeams();
    }

    private void setCurrentLevel(LevelGenerator gen) {
        float as = gen.previewAspect();
        if (as != as)
            as = 1;
        auto sz = Vector2i(cast(int)(mLevelBtn.size.y*as), mLevelBtn.size.y);
        mLevelBtn.image = gen.preview(sz);
        mCurrentLevel = gen;
    }

    private void loadLastPlayedLevel() {
        scope level = gFramework.loadConfig(cLastlevelConf);
        auto gen = new GenerateFromSaved(mGenerator, level);
        setCurrentLevel(gen);
    }

    private void levelSelect(DropDownList sender) {
        if (sender.list.selectedIndex == 0) {
            loadLastPlayedLevel();
            return;
        }
        scope level = gFramework.loadConfig(cSavedLevelsPath~sender.selection);
        auto gen = new GenerateFromSaved(mGenerator, level);
        setCurrentLevel(gen);
    }

    private void levelClick(Button sender) {
        auto gen = new GenerateFromTemplate(mGenerator,
            mGenerator.templates.findRandom());
        gen.generate();
        setCurrentLevel(gen);
        mSavedLevels.selection = "";
    }

    private void levelRightClick(Button sender) {
        if (!mSelector) {
            mSelector = new LevelSelector();
            mSelector.onAccept = &lvlAccept;
        }
        mLevelWindow = gWindowManager.createWindow(this, mSelector,
            _("levelselect.caption"));
        mLevelWindow.onClose = &levelWindowClose;
        mSetup.enabled = false;
    }

    private void lvlAccept(LevelGenerator gen) {
        setCurrentLevel(gen);
        mSavedLevels.selection = "";
        mLevelWindow.visible = false;
    }

    private bool levelWindowClose(Window sender) {
        //lol, just to prevent killing the task
        return true;
    }

    private void editteamsClick(Button sender) {
        mTeameditTask = new TeamEditorTask(manager);
        mSetup.enabled = false;
    }

    private void loadTeams() {
        auto conf = gFramework.loadConfig("teams");
        if (!conf)
            return;
        auto tc = conf.getSubNode("teams");
        char[][] teams;
        foreach (ConfigNode t; tc) {
            teams ~= t.name;
        }
        mAllTeams.setContents(teams);
    }

    private void goClick(Button sender) {
        assert(mCurrentLevel);
        mWindow.acceptSize();
        mWindow.client = mWaiting;

        mThread = new LvlGenThread(mCurrentLevel);
        mThread.start();
        mThWaiting = true;
    }

    private void cancelClick(Button sender) {
        kill();
    }

    //play a level, hide this GUI while doing that, then return
    void play(Level level) {
        mWindow.visible = false;
        //reset preview dialog
        mWindow.client = mSetup;

        assert(!mGame); //hm, no idea
        //create default GameConfig with custom level
        auto gc = loadGameConfig(globals.anyConfig.getSubNode("newgame"), level);
        //xxx: do some task-death-notification or so... (currently: polling)
        //currently, the game can't really return anyway...
        mGame = new GameTask(manager, gc);
        /+auto lbl = new Label();
        lbl.image = (cast(LevelLandscape)level.objects[0]).landscape.image();
        gWindowManager.createWindow(this, lbl, "hurrr");+/
    }

    override protected void onFrame() {
        if (mTeameditTask) {
            //team editor is open
            if (mTeameditTask.reallydead) {
                loadTeams();
                mTeameditTask = null;
                mSetup.enabled = true;
            }
        }
        if (mLevelWindow) {
            //level selector is open
            if (!mLevelWindow.visible) {
                mLevelWindow = null;
                mSetup.enabled = true;
            }
        }
        if (mThWaiting) {
            //level is being generated
            if (mThread.getState() != Thread.TS.RUNNING) {
                //level generation finished, now start the game
                mThWaiting = false;
                play(mThread.finalLevel);
                mThread = null;
            }
        }
        //poll for game death
        if (mGame) {
            if (mGame.reallydead) {
                mGame = null;
                //show GUI again
                mWindow.visible = true;
            }
        }
    }

    static this() {
        TaskFactory.register!(typeof(this))("localgamesetup");
    }
}

class LvlGenThread : Thread {
    private LevelGenerator mLvlGen;
    public Level finalLevel;

    this(LevelGenerator gen) {
        super();
        mLvlGen = gen;
    }

    override int run() {
        finalLevel = mLvlGen.render();
        return 0;
    }
}
