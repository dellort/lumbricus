module game.hud.network;

import framework.font;
import framework.i18n;
import game.hud.teaminfo;
import gui.container;
import gui.boxcontainer;
import gui.label;
import gui.button;
import gui.widget;
import utils.time;
import utils.misc;
import utils.vector2;

class NetworkHud : SimpleContainer {
    private {
        GameInfo mGame;
        SimpleContainer mErrorFrame;
        Time mLastServerFrame;
        Label mLagLabel;
        BoxContainer mCloseBox;
        //time when lagging until "waiting for server" is shown
        enum cAcceptedLag = timeSecs(1);
    }

    this(GameInfo game) {
        mGame = game;
        if (!mGame.connection)
            return;

        mErrorFrame = new SimpleContainer();
        mErrorFrame.styles.addClass("neterrorbox");
        mErrorFrame.visible = false;

        //centered "waiting for server"
        mLagLabel = new Label();
        mLagLabel.styles.addClass("netlaglabel");
        mLagLabel.text = translate("nethud.waitingforserver");
        mErrorFrame.add(mLagLabel, WidgetLayout.Aligned(0, 0));

        //centered box with disconnected message and close button
        mCloseBox = new BoxContainer(false, false, 10);
        mCloseBox.styles.addClass("netclosebox");
        auto cl = new Label();
        cl.text = translate("nethud.connectionlost");
        mCloseBox.add(cl, WidgetLayout.Aligned(0, 0));
        auto cbtn = new Button();
        cbtn.text = translate("nethud.exitgame");
        cbtn.onClick = &closeClick;
        auto lay = WidgetLayout.Aligned(0, 0);
        lay.pad = 5;
        mCloseBox.add(cbtn, lay);
        mErrorFrame.add(mCloseBox, WidgetLayout.Aligned(0, 0));

        add(mErrorFrame);
    }

    private void closeClick(Button sender) {
        if (!mCloseBox.visible)
            return;
        mGame.connection.close();
    }

    override protected void simulate() {
        if (!mGame.connection)
            return;

        Time cur = timeCurrentTime();
        if (!mGame.connection.waitingForServer)
            mLastServerFrame = cur;

        //xxx mErrorFrame does not block input from the game; imo this is ok,
        //    this way you can still scroll around etc. when waiting
        if (!mGame.connection.connected) {
            mErrorFrame.visible = true;
            mCloseBox.visible = true;
        } else if (cur - mLastServerFrame > cAcceptedLag) {
            mErrorFrame.visible = true;
            mLagLabel.visible = true;
        } else {
            mErrorFrame.visible = false;
            mLagLabel.visible = false;
            mCloseBox.visible = false;
        }
    }
}
