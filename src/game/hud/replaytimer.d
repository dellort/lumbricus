module game.hud.replaytimer;

import framework.framework;
import framework.i18n;
import game.hud.teaminfo;
import game.gamepublic;
import gui.boxcontainer;
import gui.label;
import gui.widget;
import utils.time;
import utils.misc;

class ReplayTimer : BoxContainer {
    private {
        GameInfo mGame;
        Label mReplayImg, mReplayTimer;
    }

    this(GameInfo game) {
        super(false);
        mGame = game;

        mReplayImg = new Label();
        //mReplayImg.image = globals.guiResources.get!(Surface)("replay_r");
        mReplayImg.text = "R";
        mReplayImg.font = gFramework.fontManager.loadFont("replay_r");
        mReplayImg.visible = false;
        mReplayTimer = new Label();
        mReplayTimer.visible = false;
        mReplayTimer.font = gFramework.fontManager.loadFont("replaytime");
        add(mReplayImg);
        add(mReplayTimer, WidgetLayout.Aligned(0, 0));
    }

    override protected void simulate() {
        if (mGame.replayRemain != Time.Null) {
            mReplayImg.visible = (timeCurrentTime().msecs/500)%2 == 0;
            mReplayTimer.visible = true;
            mReplayTimer.text = myformat("{:f1}s", mGame.replayRemain.secsf);
        } else {
            mReplayImg.visible = false;
            mReplayTimer.visible = false;
        }
    }
}
