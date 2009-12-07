module game.gui.loadingscreen;

import framework.framework;
import framework.i18n;
import gui.boxcontainer;
import gui.container;
import gui.label;
import gui.progress;
import gui.widget;
import utils.time;
import utils.vector2;

class LoadingScreen : Container {
    private {
        int mCurChunk = -1;
        SimpleContainer mSecondaryFrame;
        Foobar mSecondary;
        int mSecondaryPos, mSecondaryCount;
        Label[] mChunkLabels;
        BoxContainer mLabelList;
    }

    this() {
    }

    //fixed amount of chunks; each chunk has an associated message
    //these are used to show what's going on
    void setPrimaryChunks(char[][] stuff) {
        if (mLabelList) {
            mLabelList.remove();
        }

        mLabelList = new BoxContainer(false, false);
        mLabelList.setLayout(WidgetLayout.Aligned(-1,-1,Vector2i(50,50)));
        addChild(mLabelList);

        foreach (char[] chunk; stuff) {
            auto label = new Label();
            mChunkLabels ~= label;
            label.styles.addClass("loadingscreen-label");
            label.text = translate("loading.load", chunk);
            mLabelList.add(label);
        }

        mCurChunk = -1;
    }

    //select a chuck set with setPrimaryChunks()
    void primaryPos(int cur) {
        if (cur <= mCurChunk)
            return;
        //set a next pos => gray out old chunk again
        if (mCurChunk >= 0) {
            mChunkLabels[mCurChunk].styles.setState("highlight", false);
        }
        //and highlight current one
        mCurChunk = cur;
        if (mCurChunk < mChunkLabels.length) {
            mChunkLabels[mCurChunk].styles.setState("highlight", true);
        }
    }

    Vector2i layoutSizeRequest() {
        return Vector2i(0);
    }

    private void updateSecondary() {
        if (mSecondary && mSecondaryCount)
            mSecondary.percent = 1.0f*mSecondaryPos / mSecondaryCount;
    }

    void secondaryPos(int p) {
        mSecondaryPos = p;
        updateSecondary();
    }

    void secondaryCount(int c) {
        mSecondaryCount = c;
        updateSecondary();
    }

    void secondaryActive(bool set) {
        if (set == !!mSecondaryFrame)
            return;

        //create/destroy progressbar-GUI
        if (set) {
            mSecondaryFrame = new SimpleContainer();
            mSecondary = new Foobar();
            updateSecondary();
            mSecondary.zorder = 1;
            mSecondary.fill = Color(0,1.0,0);
            mSecondary.minSize = Vector2i(0, 25); //height of the bar
            mSecondaryFrame.add(mSecondary);
            auto background = new Spacer();
            background.color = Color(0.5);
            mSecondaryFrame.add(background);
            WidgetLayout lay;
            lay.fill[0] = 0.7;
            lay.fill[1] = 0.2;
            lay.alignment[1] = 0.8;
            lay.pad = 20;
            lay.expand[0] = true;
            lay.expand[1] = false;
            mSecondaryFrame.setLayout = lay;
            addChild(mSecondaryFrame);
        } else {
            mSecondaryFrame.remove();
            mSecondaryFrame = null;
            mSecondary = null;
        }
    }
}
