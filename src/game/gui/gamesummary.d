module game.gui.gamesummary;

import common.common;
import common.task;
import framework.framework;
import framework.i18n;
import game.gfxset;
import gui.loader;
import gui.wm;
import gui.widget;
import gui.button;
import gui.label;
import gui.tablecontainer;
import utils.configfile;
import utils.strparser : ConversionException;

class GameSummary : Task {
    private {
        Window mWindow;
        Widget mDialog;
        Button mCloseButton;
        Label mGameWinLabel, mRoundWinLabel, mVictoryLabel;
        TableContainer mScoreTable;
        bool mGameOver;
    }

    this(TaskManager tm, char[] args = "") {
        super(tm);

        auto config = loadConfig("dialogs/gamesummary_gui");
        auto loader = new LoadGui(config);
        loader.load();

        mCloseButton = loader.lookup!(Button)("btn_close");
        mCloseButton.onClick = &closeClick;

        mGameWinLabel = loader.lookup!(Label)("lbl_gamewinner");
        mRoundWinLabel = loader.lookup!(Label)("lbl_roundwinner");
        mVictoryLabel = loader.lookup!(Label)("lbl_victory");

        mScoreTable = loader.lookup!(TableContainer)("tbl_score");

        mDialog = loader.lookup("gamesummary_root");
        mWindow = gWindowManager.createWindow(this, mDialog, "");

        //xxx for debugging, you can do "spawn scores last" and it will show
        //    the last debug dump
        if (args == "last") {
            init(loadConfig("persistence_debug"));
        }
    }

    void init(ConfigNode persist) {
        //valid check
        if (!persist || !persist.exists("teams")
            || !persist.exists("round_counter"))
        {
            mGameOver = false;
            kill();
            return;
        }
        auto props = mWindow.properties;
        auto teamsNode = persist.getSubNode("teams");
        props.background = Color(0.2, 0.2, 0.2);
        char[] bgCol;
        if (persist.exists("winner")) {
            //game is over
            mGameOver = true;
            props.windowTitle =
                _("gamesummary.caption_end", persist["round_counter"]);
            mCloseButton.textMarkup = `\t(.gui.close)`;
            if (persist["winner"].length > 0) {
                //we have a game winner
                auto tnode = teamsNode.getSubNode(persist["winner"]);
                mGameWinLabel.textMarkup = _("gamesummary.game_winner",
                    tnode["name"], "team_" ~ tnode["color"]);
                bgCol = tnode["color"];
            } else {
                //game ended draw
                mGameWinLabel.textMarkup = `\t(game_draw)`;
            }
            mGameWinLabel.font = gFramework.fontManager.loadFont("game_win",
                false);
        } else {
            //game will continue
            mGameOver = false;
            props.windowTitle =
                _("gamesummary.caption_noend", persist["round_counter"]);
            mCloseButton.textMarkup = `\t(continue)`;
            mGameWinLabel.text = "";
            mGameWinLabel.font = gFramework.fontManager.loadFont("tiny", false);
        }
        if (persist["round_winner"].length > 0) {
            //xxx code duplication
            auto tnode = teamsNode.getSubNode(persist["round_winner"]);
            mRoundWinLabel.textMarkup = _("gamesummary.round_winner",
                tnode["name"], "team_" ~ tnode["color"]);
            if (bgCol.length == 0 && !mGameOver)
                bgCol = tnode["color"];
        } else {
            //round ended draw
            mRoundWinLabel.textMarkup = `\t(round_draw)`;
        }
        if (bgCol.length > 0) {
            try {
                props.background = Color.fromString(bgCol);
                props.background *= 0.2;
                props.background.a = 1.0f;
            } catch (ConversionException e) {
            }
        }
        mWindow.properties = props;

        mScoreTable.clear();
        mScoreTable.setSize(2, teamsNode.count);
        int i;
        foreach (ConfigNode tn; teamsNode) {
            auto nameLbl = new Label();
            nameLbl.textMarkup = `\c(team_` ~ tn["color"] ~ ")" ~ tn["name"];
            nameLbl.font = gFramework.fontManager.loadFont("scores", false);
            mScoreTable.add(nameLbl, 0, i);

            auto scoreLbl = new Label();
            scoreLbl.text = tn["global_wins"];
            scoreLbl.font = gFramework.fontManager.loadFont("scores", false);
            mScoreTable.add(scoreLbl, 1, i);
            i++;
        }

        mVictoryLabel.text = _("gamesummary.victory_condition",
            _("gamesummary.victory." ~ persist["victory_type"],
            persist["victory_count"]));

        mWindow.window.position = gFramework.screenSize/2
            - mWindow.window.size/2;
        mWindow.window.activate();
    }

    bool gameOver() {
        return mGameOver;
    }

    private void closeClick(Button sender) {
        kill();
    }

    //debug only, normally you would not need this
    static this() {
        TaskFactory.register!(typeof(this))("scores");
    }
}
