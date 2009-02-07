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
import gui.boxcontainer;
import utils.configfile;

//import std.thread;
import str = stdx.string;

class LocalGameSetupTask : Task {
    private {
        Widget mSetup, mWaiting;
        Window mWindow;
        DropDownList mSavedLevels;
        DropDownList mTemplates;
        Button mLevelBtn, mGoBtn, mLevelSaveBtn;
        BoxContainer mLevelDDBox;

        LevelGeneratorShared mGenerator;
        LevelGenerator mCurrentLevel;
        TeamEditorTask mTeameditTask;
        StringListWidget mAllTeamsList, mActiveTeamsList;

        const cMaxPower = 200;

        //holds team info specific to current game (not saved in teams.conf)
        struct TeamDef {
            //percentage of global power value this team gets
            float handicap = 1.0f;

            void saveTo(ConfigNode node) {
                node.setIntValue("power", cast(int)(cMaxPower*handicap));
            }
        }

        ConfigNode mTeams;       //as loaded from teams.conf
        //list of team ids for the game
        //note that it might contain invalid (deleted) teams
        TeamDef[char[]] mActiveTeams;

        Window mLevelWindow;
        LevelSelector mSelector;  //8-level window, created once and reused then

        //background level rendering thread *g*
        //LvlGenThread mThread;
        //bool mThWaiting = false;
        Task mGame;

        const cSavedLevelsPath = "storedlevels/";
        const cLastlevelConf = "lastlevel";
    }

    this(TaskManager tm, char[] args = "") {
        super(tm);

        mGenerator = new LevelGeneratorShared();

        auto config = gFramework.loadConfig("localgamesetup_gui");
        auto loader = new LoadGui(config);
        loader.load();
        loader.lookup!(Button)("cancel").onClick = &cancelClick;
        mGoBtn = loader.lookup!(Button)("go");
        mGoBtn.onClick = &goClick;
        loader.lookup!(Button)("editteams").onClick = &editteamsClick;

        mLevelBtn = loader.lookup!(Button)("btn_level");
        mLevelBtn.onClick = &levelClick;
        mLevelBtn.onRightClick = &levelRightClick;

        mSavedLevels = loader.lookup!(DropDownList)("dd_level");
        readSavedLevels();
        mSavedLevels.selection = _("gamesetup.lastplayed");
        mSavedLevels.onSelect = &levelSelect;
        mSavedLevels.onEditStart = &levelEditStart;
        mSavedLevels.onEditEnd = &levelEditEnd;
        mSavedLevels.edit.onChange = &levelEditChange;

        mLevelSaveBtn = loader.lookup!(Button)("btn_savelevel");
        mLevelSaveBtn.onClick = &saveLevelClick;
        mLevelSaveBtn.remove();

        mLevelDDBox = loader.lookup!(BoxContainer)("box_leveldd");

        mTemplates = loader.lookup!(DropDownList)("dd_templates");
        mTemplates.selection = "TODO";

        mAllTeamsList = loader.lookup!(StringListWidget)("list_allteams");
        mAllTeamsList.onSelect = &allteamsSelect;
        mActiveTeamsList = loader.lookup!(StringListWidget)("list_activeteams");
        mActiveTeamsList.onSelect = &activeteamsSelect;

        mSetup = loader.lookup("gamesetup_root");
        mWaiting = loader.lookup("waiting_root");
        mWindow = gWindowManager.createWindow(this, mSetup,
            _("gamesetup.caption_local"));

        loadLastPlayedLevel();
        if (!mCurrentLevel)
            levelClick(mLevelBtn);
        loadTeams();
    }

    private void readSavedLevels() {
        char[][] storedlevels;
        storedlevels ~= _("gamesetup.lastplayed");
        gFramework.fs.listdir(cSavedLevelsPath, "*.conf", false, (char[] fn) {
            storedlevels ~= fn[0..$-5];
            return true;
        });
        mSavedLevels.list.setContents(storedlevels);
    }

    private void setCurrentLevel(LevelGenerator gen) {
        float as = gen.previewAspect();
        if (as != as)
            as = 1;
        auto sz = Vector2i(cast(int)(mLevelBtn.size.y*as), mLevelBtn.size.y);
        mLevelBtn.image = gen.preview(sz);
        mCurrentLevel = gen;
        mSavedLevels.allowEdit = true;
    }

    private void loadLastPlayedLevel() {
        scope level = gFramework.loadConfig(cLastlevelConf, false, true);
        if (level) {
            auto gen = new GenerateFromSaved(mGenerator, level);
            setCurrentLevel(gen);
        }
    }

    private void levelSelect(DropDownList sender) {
        if (sender.list.selectedIndex == 0) {
            loadLastPlayedLevel();
            return;
        }
        scope level = gFramework.loadConfig(cSavedLevelsPath~sender.selection);
        auto gen = new GenerateFromSaved(mGenerator, level);
        setCurrentLevel(gen);
        //level is already saved
        mSavedLevels.allowEdit = false;
    }

    private void levelEditStart(DropDownList sender) {
        sender.edit.text = "";
    }

    private void levelEditChange(EditLine sender) {
        if (sender.text.length > 0) {
            mLevelSaveBtn.remove();
            mLevelDDBox.add(mLevelSaveBtn);
        } else {
            mLevelSaveBtn.remove();
        }
    }

    private void levelEditEnd(DropDownList sender) {
        mLevelSaveBtn.remove();
    }

    private void levelClick(Button sender) {
        auto gen = new GenerateFromTemplate(mGenerator,
            mGenerator.templates.findRandom());
        gen.generate();
        setCurrentLevel(gen);
        mSavedLevels.selection = "";
    }

    private void saveLevelClick(Button sender) {
        if (!mSavedLevels.allowEdit)
            return;
        char[] lname = mSavedLevels.edit.text;
        auto tmpLevel = mCurrentLevel.render(false);
        saveConfig(tmpLevel.saved, cSavedLevelsPath ~ lname ~ ".conf");
        delete tmpLevel;
        readSavedLevels();
        mSavedLevels.allowEdit = false;
        mSavedLevels.selection = lname;
    }

    private void levelRightClick(Button sender) {
        if (!mSelector) {
            mSelector = new LevelSelector();
            mSelector.onAccept = &lvlAccept;
        }
        mSelector.loadLevel(mCurrentLevel);
        mLevelWindow = gWindowManager.createWindow(this, mSelector,
            _("levelselect.caption"));
        mLevelWindow.onClose = &levelWindowClose;
        mSetup.enabled = false;
    }

    private void lvlAccept(LevelGenerator gen) {
        if (gen) {
            setCurrentLevel(gen);
            mSavedLevels.selection = "";
        }
        mLevelWindow.visible = false;
    }

    private bool levelWindowClose(Window sender) {
        //lol, just to prevent killing the task
        return true;
    }

    private void editteamsClick(Button sender) {
        if (!mTeameditTask)
            mTeameditTask = new TeamEditorTask(manager);
    }

    //reload teams from config file and show in dialog
    private void loadTeams() {
        auto conf = gFramework.loadConfig("teams");
        if (!conf)
            return;
        mTeams = conf.getSubNode("teams");
        updateTeams();
    }

    //refresh team display in the dialog without reloading
    private void updateTeams() {
        char[][] teams, actteams;
        foreach (ConfigNode t; mTeams) {
            if (t["id"] in mActiveTeams) {
                actteams ~= t.name;
            } else
                teams ~= t.name;
        }
        teams.sort;
        actteams.sort;
        mGoBtn.enabled = actteams.length>1;
        mAllTeamsList.setContents(teams);
        mActiveTeamsList.setContents(actteams);
    }

    private void allteamsSelect(int index) {
        if (index < 0)
            return;
        //team names are unique, but may change
        auto tNode = mTeams.getSubNode(mAllTeamsList.contents[index]);
        assert(tNode);
        activateTeam(tNode["id"], true);
        updateTeams();
    }

    private void activeteamsSelect(int index) {
        if (index < 0)
            return;
        auto tNode = mTeams.getSubNode(mActiveTeamsList.contents[index]);
        assert(tNode);
        activateTeam(tNode["id"], false);
        updateTeams();
    }

    //mark a team as (in)active, i.e. (not) participating on the game
    //teams are remembered by id, because the name might change
    private void activateTeam(char[] teamId, bool active) {
        if (active) {
            if (!(teamId in mActiveTeams)) {
                mActiveTeams[teamId] = TeamDef();
            }
        } else {
            if (teamId in mActiveTeams)
                mActiveTeams.remove(teamId);
        }
    }

    //write active teams into a ConfigNode the engine can use
    private ConfigNode buildGameTeams() {
        ConfigNode ret = new ConfigNode();
        foreach (ConfigNode t; mTeams) {
            if (t["id"] in mActiveTeams) {
                //write team definition from teams.conf
                auto tNode = ret.getSubNode(t.name);
                tNode.mixinNode(t);
                //write game-specific values from TeamDef
                mActiveTeams[t["id"]].saveTo(tNode);
            }
        }
        return ret;
    }

    private void goClick(Button sender) {
        assert(mCurrentLevel);
        mWindow.acceptSize();
        mWindow.client = mWaiting;

        //mThread = new LvlGenThread(mCurrentLevel);
        //mThread.start();
        //mThWaiting = true;
        auto finalLevel = mCurrentLevel.render();
        play(finalLevel);
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
        gc.teams = buildGameTeams();
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
            }
        }
        if (mLevelWindow) {
            //level selector is open
            if (!mLevelWindow.visible) {
                mLevelWindow = null;
                mSetup.enabled = true;
            }
        }
        /+
        if (mThWaiting) {
            //level is being generated
            if (mThread.getState() != Thread.TS.RUNNING) {
                //level generation finished, now start the game
                mThWaiting = false;
                play(mThread.finalLevel);
                mThread = null;
            }
        }
        +/
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

/+
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
+/
