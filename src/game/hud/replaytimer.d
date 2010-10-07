module game.hud.replaytimer;

import game.hud.teaminfo;
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
        mReplayImg.styles.addClass("replaydisplay");
        mReplayImg.visible = false;
        mReplayTimer = new Label();
        mReplayTimer.visible = false;
        mReplayTimer.styles.addClass("replaytime");
        add(mReplayImg);
        add(mReplayTimer, WidgetLayout.Aligned(0, 0));
    }

    override protected void simulate() {
        if (mGame.shell.replayRemain != Time.Null) {
            mReplayImg.visible = (timeCurrentTime().msecs/500)%2 == 0;
            mReplayTimer.visible = true;
            mReplayTimer.text = myformat("{:f1}s",
                mGame.shell.replayRemain.secsf);
        } else {
            mReplayImg.visible = false;
            mReplayTimer.visible = false;
        }
    }
}
