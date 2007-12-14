module game.gui.preview;

import framework.framework;
import framework.i18n;
import common.task;
import common.common;
import gui.widget;
import gui.container;
import gui.button;
import gui.boxcontainer;
import gui.label;
import gui.tablecontainer;
import gui.wm;
import game.gametask;
import levelgen.generator;
import levelgen.level;
import utils.vector2;
import utils.rect2;

private class LevelSelector : SimpleContainer {
    private {
        const cCols = 2;
        const cPrevHeight = 70;

        const Color cColSky = {0.5, 0.5, 1.0};
        const Color cColLand = {0.8, 0.4, 0.0};
        const Color cColSolid = {0.0, 0.0, 0.0};

        int rowCount;
        Button[] mShowBitmap;
        LevelInfo[] mLevel;

        LevelGenerator mGenerator;
        Label mLblInfo;
    }

    struct LevelInfo {
        LevelGeometry geo;
        LevelTemplate templ;

        static LevelInfo opCall(LevelGeometry geo, LevelTemplate templ) {
            LevelInfo res;
            res.geo = geo;
            res.templ = templ;
            return res;
        }
    }

    void delegate(LevelInfo selected) onAccept;

    this() {
        mGenerator = new LevelGenerator();

        //create enough rows to fit all templates
        rowCount = (mGenerator.templates.length+1)/2;
        //grid layout for buttons+description
        TableContainer buttons_layout = new TableContainer(2, rowCount,
            Vector2i(10, 20));

        auto templ_trans = Translator.ByNamespace("templates");
        templ_trans.errorString = false;

        foreach (int i, LevelTemplate t; mGenerator.templates) {
            //prepare button
            auto sb = new Button();
            sb.onClick = &accept;
            sb.onRightClick = &generate;
            mShowBitmap ~= sb;
            //insert info structure (matched by index)
            mLevel ~= LevelInfo(null, t);
            doGenerate(i);
            //add a description label below
            auto l = new Label(gFramework.getFont("normal"));
            l.text = templ_trans(t.description);
            //this box holds button+label, fixed size
            auto boxc = new BoxContainer(false, false, 2);
            boxc.add(sb, WidgetLayout.Noexpand);
            boxc.add(l, WidgetLayout.Noexpand);
            buttons_layout.add(boxc, i % cCols, i / cCols);
        }

        //special: aligned to top, but whitespace expanded below
        WidgetLayout lblLay;
        lblLay.expand[0] = false;
        lblLay.fill[1] = false;
        lblLay.alignment[1] = 0.0f;
        mLblInfo = new Label();
        mLblInfo.drawBorder = false;
        mLblInfo.text = _("levelselect.infotext");

        auto layout = new BoxContainer(false, false, 10);

        layout.add(mLblInfo, lblLay);
        layout.add(buttons_layout);

        add(layout);
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
        auto templ = mLevel[idx].templ;
        mLevel[idx].geo = templ.generate();
        //scale down (?)
        auto sz = Vector2i((cPrevHeight*templ.size.x)/templ.size.y, cPrevHeight);
        mShowBitmap[idx].image = mGenerator.renderPreview(mLevel[idx].geo,
            sz, cColLand, cColSolid, cColSky)
            .createTexture();
        mShowBitmap[idx].needRelayout();
    }

    private void accept(Button sender) {
        int idx = getIdx(sender);
        if (onAccept)
            onAccept(mLevel[idx]);
    }
}

//this is considered debug code until we have a proper game settings dialog
class LevelPreviewTask : Task {
    private {
        LevelSelector mSelector;
        Window mWMWindow;
        Task mGame;
    }

    this(TaskManager tm) {
        super(tm);
        mSelector = new LevelSelector();
        mSelector.onAccept = &lvlAccept;
        mWMWindow = gWindowManager.createWindow(this, mSelector,
            _("levelselect.caption"));
    }

    void lvlAccept(LevelSelector.LevelInfo lvl) {
        //generate level
        //big xxx: locks up the game on slow PCs without displaying anything
        //         (besides using private generator instance)
        auto level = generateAndSaveLevel(mSelector.mGenerator, lvl.templ,
            lvl.geo, null);
        //start game
        play(level);
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
