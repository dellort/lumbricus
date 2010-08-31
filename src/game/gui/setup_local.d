module game.gui.setup_local;

import framework.framework;
import framework.i18n;
import common.task;
import common.common;
import game.gametask;
import game.setup;
import game.levelgen.generator;
import game.levelgen.level;
import game.gui.preview;
import game.gui.teamedit;
import game.gui.gamesummary;
import gui.widget;
import gui.edit;
import gui.dropdownlist;
import gui.button;
import gui.window;
import gui.loader;
import gui.list;
import gui.boxcontainer;
import gui.container;
import gui.global;
import utils.configfile;
import utils.misc;
import utils.path;
import utils.random;

import tango.util.Convert : to;

class LevelWidget : SimpleContainer {
    private {
        DropDownList mSavedLevels;
        LevelGenerator mCurrentLevel;
        ImageButton mLevelBtn;
        Button mLevelSaveBtn;
        ImageButton[8] mLvlQuickGen;
        BoxContainer mLevelDDBox;
        LevelGeneratorShared mGenerator;

        WindowWidget mLevelWindow;
        LevelSelector mSelector;  //8-level window, created once and reused then

        const cSavedLevelsPath = "storedlevels/";
        const cLastlevelConf = "lastlevel";
    }

    void delegate(bool busy) onSetBusy;

    this() {
        mGenerator = new LevelGeneratorShared();

        auto config = loadConfig("dialogs/gamesetupshared_gui");
        auto loader = new LoadGui(config);
        loader.load();

        mLevelBtn = loader.lookup!(ImageButton)("btn_level");
        mLevelBtn.onClick = &levelClick;
        mLevelBtn.onRightClick = &levelRightClick;

        mSavedLevels = loader.lookup!(DropDownList)("dd_level");
        readSavedLevels();
        mSavedLevels.selection = translate("gamesetup.lastplayed");
        mSavedLevels.onSelect = &levelSelect;
        mSavedLevels.onEditStart = &levelEditStart;
        mSavedLevels.onEditEnd = &levelEditEnd;
        mSavedLevels.edit.onChange = &levelEditChange;

        mLevelSaveBtn = loader.lookup!(Button)("btn_savelevel");
        mLevelSaveBtn.onClick = &saveLevelClick;
        mLevelSaveBtn.remove();

        mLevelDDBox = loader.lookup!(BoxContainer)("box_leveldd");

        auto allTemplates = mGenerator.templates.all;
        foreach (int idx, ref btn; mLvlQuickGen) {
            //template names are 1-based
            btn = loader.lookup!(ImageButton)(myformat("btn_quickgen{}", idx+1));
            //xxx template description used as an id (like in game.gui.preview)
            btn.image = gGuiResources.get!(Surface)("tmpl_thumb_"
                ~ allTemplates[idx].description);
            btn.onClick = &quickGenClick;
            assert(idx < allTemplates.length);
        }

        add(loader.lookup("levelwidget_root"));
    }

    LevelGenerator currentLevel() {
        return mCurrentLevel;
    }

    private void readSavedLevels() {
        char[][] storedlevels;
        storedlevels ~= translate("gamesetup.lastplayed");
        gFS.listdir(cSavedLevelsPath, "*.conf", false, (char[] fn) {
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
        auto level = loadConfig(cLastlevelConf, false, true);
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
        auto level = loadConfig(cSavedLevelsPath~sender.selection);
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
        auto tmpLevel = mCurrentLevel.render(true);
        //remove illegal chars
        auto p = VFSPath(cSavedLevelsPath ~ lname ~ ".conf", true);
        saveConfig(tmpLevel.saved, p.get());
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
        mLevelWindow = gWindowFrame.createWindow(mSelector,
            r"\t(levelselect.caption)");
        if (onSetBusy)
            onSetBusy(true);
    }

    private void quickGenClick(Button sender) {
        int i = -1;
        foreach (int idx, ref btn; mLvlQuickGen) {
            if (sender is btn) {
                i = idx;
                break;
            }
        }
        assert(i >= 0);
        auto gen = new GenerateFromTemplate(mGenerator,
            mGenerator.templates.all[i]);
        gen.generate();
        setCurrentLevel(gen);
        mSavedLevels.selection = "";
    }

    private void lvlAccept(LevelGenerator gen) {
        if (gen) {
            setCurrentLevel(gen);
            mSavedLevels.selection = "";
        }
        mLevelWindow.remove();
    }

    override void simulate() {
        if (!mCurrentLevel) {
            loadLastPlayedLevel();
            if (!mCurrentLevel)
                levelClick(mLevelBtn);
        }
        if (mLevelWindow) {
            //level selector is open
            if (mLevelWindow.wasClosed) {
                mLevelWindow = null;
                if (onSetBusy)
                    onSetBusy(false);
            }
        }
    }
}

class LocalGameSetupTask {
    private {
        Widget mSetup, mWaiting;
        WindowWidget mWindow;
        DropDownList mTemplates;
        Button mGoBtn, mEditTeamsBtn;

        TeamEditorTask mTeameditTask;
        StringListWidget mAllTeamsList, mActiveTeamsList;
        LevelWidget mLevelSelector;

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

        GameTask mGame;
        ConfigNode mGamePersist;

        bool mDead;
    }

    this() {
        auto config = loadConfig("dialogs/localgamesetup_gui");
        auto loader = new LoadGui(config);

        mLevelSelector = new LevelWidget();
        loader.addNamedWidget(mLevelSelector, "levelwidget");
        mLevelSelector.onSetBusy = &levelBusy;

        loader.load();

        loader.lookup!(Button)("cancel").onClick = &cancelClick;
        mGoBtn = loader.lookup!(Button)("go");
        mGoBtn.onClick = &goClick;
        mEditTeamsBtn = loader.lookup!(Button)("editteams");
        mEditTeamsBtn.onClick = &editteamsClick;

        mTemplates = loader.lookup!(DropDownList)("dd_templates");
        mTemplates.selection = "TODO";

        mAllTeamsList = loader.lookup!(StringListWidget)("list_allteams");
        mAllTeamsList.onSelect = &allteamsSelect;
        mActiveTeamsList = loader.lookup!(StringListWidget)("list_activeteams");
        mActiveTeamsList.onSelect = &activeteamsSelect;

        mSetup = loader.lookup("gamesetup_root");
        mWaiting = loader.lookup("waiting_root");
        mWindow = gWindowFrame.createWindow(mSetup,
            r"\t(gamesetup.caption_local)");

        loadTeams();

        addTask(&onFrame);
    }

    private void levelBusy(bool busy) {
        mSetup.enabled = !busy;
    }

    private void editteamsClick(Button sender) {
        if (!mTeameditTask)
            mTeameditTask = new TeamEditorTask();
    }

    //reload teams from config file and show in dialog
    private void loadTeams() {
        auto conf = loadConfig("teams");
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
                char[] tname = t.name;
                if (mGamePersist) {
                    //xxx just for debugging, until game summary dialog is done
                    auto n = mGamePersist.getSubNode("teams").getSubNode(
                        t["net_id"] ~ "." ~ t["id"]);
                    tname ~= " (" ~ n["global_wins"] ~ ")";
                }
                actteams ~= tname;
            } else
                teams ~= t.name;
        }
        teams.sort;
        actteams.sort;
        mGoBtn.enabled = actteams.length>1;
        mAllTeamsList.setContents(teams);
        mActiveTeamsList.setContents(actteams);

        mAllTeamsList.visible = !mGamePersist;
        mEditTeamsBtn.visible = !mGamePersist;
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
        assert(mLevelSelector.currentLevel);
        mWindow.acceptSize();
        mWindow.client = mWaiting;

        //mThread = new LvlGenThread(mCurrentLevel);
        //mThread.start();
        //mThWaiting = true;
        auto finalLevel = mLevelSelector.currentLevel.render();
        play(finalLevel);
    }

    private void cancelClick(Button sender) {
        mDead = true;
    }

    //play a level, hide this GUI while doing that, then return
    void play(Level level) {
        mWindow.remove();
        //reset preview dialog
        mWindow.client = mSetup;

        assert(!mGame); //hm, no idea
        //create default GameConfig with custom level
        auto gc = loadGameConfig(loadConfig("newgame"), level, true,
            mGamePersist);
        gc.teams = buildGameTeams();
        gc.randomSeed = to!(char[])(generateRandomSeed());
        //xxx: do some task-death-notification or so... (currently: polling)
        //currently, the game can't really return anyway...
        mGame = new GameTask(gc);
    }

    private bool onFrame() {
        if (!mGame && mWindow.wasClosed())
            mDead = true;

        if (mDead) {
            mWindow.remove();
            return false;
        }

        if (mTeameditTask) {
            //team editor is open
            if (!mTeameditTask.active) {
                loadTeams();
                mTeameditTask = null;
            }
        }
        //poll for game death
        if (mGame) {
            if (!mGame.active) {
                //show GUI again
                gWindowFrame.addWindow(mWindow);

                mGamePersist = mGame.gamePersist;
                if (mGamePersist) {
                    auto gs = new GameSummary(mGamePersist);
                    if (gs.gameOver)
                        mGamePersist = null;
                }

                mGame = null;
                updateTeams();
            }
        }

        return true;
    }

    static this() {
        registerTaskClass!(typeof(this))("localgamesetup");
    }
}
