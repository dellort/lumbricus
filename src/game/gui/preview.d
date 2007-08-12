module game.gui.preview;

import framework.framework;
import common.task;
import common.common;
import gui.widget;
import gui.container;
import gui.button;
import gui.boxcontainer;
import gui.label;
import gui.wm;
import game.gametask;
import levelgen.generator;
import levelgen.level;
import utils.vector2;
import utils.rect2;

private class LevelPreviewer : SimpleContainer {
    private {
        const cRows = 3;
        const cCols = 2;
        Button[cRows*cCols] mShowBitmap;

        struct LevelInfo {
            LevelGeometry geo;
            LevelTemplate templ;
        }

        LevelInfo[cRows*cCols] mLevel;
        LevelGenerator mGenerator;
        Label mLblInfo;

        LevelPreviewTask mTask;
    }

    this(LevelPreviewTask bla) {
        mTask = bla;
        mGenerator = new LevelGenerator();

        BoxContainer[cRows+1] buttons_layout;
        foreach (inout bc; buttons_layout) {
            bc = new BoxContainer(true, false, 10);
        }
        WidgetLayout lay;
        lay.expand[1] = false; //don't expand in Y

        mLblInfo = new Label();
        mLblInfo.text = "Select level to play, right click to regenerate";

        foreach (int i, inout Button sb; mShowBitmap) {
            sb = new Button();
            sb.onClick = &play;
            sb.onRightClick = &generate;
            doGenerate(i);
            buttons_layout[i/cCols+1].add(sb, lay);
        }

        buttons_layout[0].add(mLblInfo, lay);

        auto layout = new BoxContainer(false, false, 50);
        foreach (inout bc; buttons_layout) {
            layout.add(bc);
        }

        add(layout, WidgetLayout.Aligned(0,0));
    }

    private int getIdx(Button which) {
        foreach (int i, Button b; mShowBitmap) {
            if (b == which)
                return i;
        }
        assert(false);
    }

    private void generate(Button sender) {
        int idx = getIdx(sender);
        doGenerate(idx);
    }

    private void doGenerate(int idx) {
        auto templ = mGenerator.findRandomTemplate("");
        mLevel[idx].geo = templ.generate();
        mLevel[idx].templ = templ;
        //scale down (?)
        auto sz = toVector2i(toVector2f(templ.size)*0.15);
        mShowBitmap[idx].image = mGenerator.renderPreview(mLevel[idx].geo,
            sz, Color(1,1,1), Color(0.8,0.8,0.8), Color(0.4,0.4,0.4))
            .createTexture();
        mShowBitmap[idx].needRelayout();
    }

    private void play(Button sender) {
        int idx = getIdx(sender);
        //generate level
        auto level = generateAndSaveLevel(mGenerator, mLevel[idx].templ,
            mLevel[idx].geo, null);
        //start game
        mTask.play(level);
    }
}

class LevelPreviewTask : Task {
    private {
        LevelPreviewer mWindow;
        Window mWMWindow;
        Task mGame;
    }

    this(TaskManager tm) {
        super(tm);
        mWindow = new LevelPreviewer(this);
        mWMWindow = gWindowManager.createWindow(this, mWindow, "Level Preview");
    }

    //play a level, hide this GUI while doing that, then return
    void play(Level level) {
        mWMWindow.visible = false;

        assert(!mGame); //hm, no idea
        //create default GameConfig with custom level
        auto gc = loadGameConfig(globals.anyConfig.getSubNode("newgame"), level);
        //xxx: do some task-death-notification or so... (currently: polling)
        //currently, the game can't really return anyway...
        mGame = new GameTask(manager, gc);
    }

    override protected void onFrame() {
        //poll for game death
        if (mGame) {
            if (mGame.reallydead) {
                mGame = null;
                //show GUI again
                mWMWindow.visible = true;
            }
        }
    }

    static this() {
        TaskFactory.register!(typeof(this))("levelpreview");
    }
}
