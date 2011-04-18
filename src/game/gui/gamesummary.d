module game.gui.gamesummary;

import framework.config;
import framework.i18n;
import gui.loader;
import gui.window;
import gui.widget;
import gui.button;
import gui.label;
import gui.tablecontainer;
import utils.color;
import utils.configfile;
import utils.strparser : ConversionException;

class GameSummary {
    private {
        WindowWidget mWindow;
        Widget mDialog;
        Button mCloseButton;
        Label mGameWinLabel, mRoundWinLabel, mVictoryLabel;
        TableContainer mScoreTable;
        bool mGameOver;
    }

    this(ConfigNode persist) {
        auto config = loadConfig("dialogs/gamesummary_gui.conf");
        auto loader = new LoadGui(config);
        loader.load();

        mCloseButton = loader.lookup!(Button)("btn_close");
        mCloseButton.onClick = &closeClick;

        mGameWinLabel = loader.lookup!(Label)("lbl_gamewinner");
        mRoundWinLabel = loader.lookup!(Label)("lbl_roundwinner");
        mVictoryLabel = loader.lookup!(Label)("lbl_victory");

        mScoreTable = loader.lookup!(TableContainer)("tbl_score");

        mDialog = loader.lookup("gamesummary_root");

/+
        //xxx for debugging, you can do "spawn scores last" and it will show
        //    the last debug dump
        if (args == "last") {
            init(loadConfig("persistence_debug.conf"));
        }
+/

        init(persist);
    }

    private void init(ConfigNode persist) {
        //valid check
        if (!persist || !persist.exists("teams")
            || !persist.exists("round_counter"))
        {
            mGameOver = false;
            return;
        }
        WindowProperties props;
        auto teamsNode = persist.getSubNode("teams");
        props.background = Color(0.2, 0.2, 0.2);
        string bgCol;
        if (persist.exists("winner")) {
            //game is over
            mGameOver = true;
            props.windowTitle =
                translate("gamesummary.caption_end", persist["round_counter"]);
            mCloseButton.textMarkup = `\t(.gui.close)`;
            if (persist["winner"].length > 0) {
                //we have a game winner
                auto tnode = teamsNode.getSubNode(persist["winner"]);
                mGameWinLabel.textMarkup = translate("gamesummary.game_winner",
                    tnode["name"], "team_" ~ tnode["color"]);
                bgCol = tnode["color"];
            } else {
                //game ended draw
                mGameWinLabel.textMarkup = `\t(game_draw)`;
            }
        } else {
            //game will continue
            mGameOver = false;
            props.windowTitle =
                translate("gamesummary.caption_noend", persist["round_counter"]);
            mCloseButton.textMarkup = `\t(continue)`;
            mGameWinLabel.text = "";
            mGameWinLabel.styles.setState("notfinal", true);
        }
        if (persist["round_winner"].length > 0) {
            //xxx code duplication
            auto tnode = teamsNode.getSubNode(persist["round_winner"]);
            mRoundWinLabel.textMarkup = translate("gamesummary.round_winner",
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

        mScoreTable.clear();
        mScoreTable.setSize(2, teamsNode.count);
        int i;
        foreach (ConfigNode tn; teamsNode) {
            auto nameLbl = new Label();
            nameLbl.textMarkup = `\c(team_` ~ tn["color"] ~ ")" ~ tn["name"];
            nameLbl.styles.addClass("score_label");
            mScoreTable.add(nameLbl, 0, i);

            auto scoreLbl = new Label();
            scoreLbl.text = tn["global_wins"];
            scoreLbl.styles.addClass("score_label");
            mScoreTable.add(scoreLbl, 1, i);
            i++;
        }

        mVictoryLabel.text = translate("gamesummary.victory_condition",
            translate("gamesummary.victory." ~ persist["victory_type"],
            persist["victory_count"]));

/+
        mWindow.window.position = gFramework.screenSize/2
            - mWindow.window.size/2;
        mWindow.window.activate();
+/
        mWindow = gWindowFrame.createWindow(mDialog, "");
        mWindow.properties = props;
    }

    bool gameOver() {
        return mGameOver;
    }

    private void closeClick(Button sender) {
        mWindow.remove();
    }

    bool active() {
        return mWindow && !mWindow.wasClosed();
    }

    void remove() {
        if (mWindow)
            mWindow.remove();
    }
}
