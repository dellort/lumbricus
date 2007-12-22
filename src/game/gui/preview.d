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
import gui.dropdownlist;
import game.gametask;
import levelgen.generator;
import levelgen.level;
import std.thread;
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
        char[] mGfx;

        LevelGenerator mGenerator;
        Label mLblInfo;
        BoxContainer mLayout;
        Label mLblWait;
        DropDownList mDdGfx;
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

    void delegate(LevelInfo selected, char[] gfx) onAccept;

    this() {
        mGenerator = new LevelGenerator();

        //create enough rows to fit all templates
        rowCount = (mGenerator.templates.length+1)/2;
        //grid layout for buttons+description
        TableContainer buttons_layout = new TableContainer(2, rowCount,
            Vector2i(10, 20));

        auto templ_trans = Translator.ByNamespace("templates");
        templ_trans.errorString = false;

        //generate one button for each level theme
        //xxx this will get too big if >8 templates, scrollbar?
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

        //"please select" label
        //special: aligned to top, but whitespace expanded below
        WidgetLayout lblLay;
        lblLay.expand[0] = false;
        lblLay.fill[1] = false;
        lblLay.alignment[1] = 0.0f;
        mLblInfo = new Label();
        mLblInfo.drawBorder = false;
        mLblInfo.text = _("levelselect.infotext");

        //Gfx theme dropdown
        mDdGfx = new DropDownList();
        mDdGfx.onSelect = &gfxSelect;
        char[][] themes = ([_("levelselect.randomgfx")] ~ mGenerator.gfxThemes);
        mDdGfx.list.setContents(themes);
        mDdGfx.selection = themes[0];

        //Gfx theme info label
        auto lblGfx = new Label();
        lblGfx.drawBorder = false;
        lblGfx.text = _("levelselect.gfxtheme");
        auto gfxbox = new BoxContainer(true, false, 5);
        gfxbox.add(lblGfx, WidgetLayout.Noexpand);
        gfxbox.add(mDdGfx);

        mLayout = new BoxContainer(false, false, 10);
        mLayout.add(mLblInfo, lblLay);
        mLayout.add(gfxbox, WidgetLayout.Expand(true));
        mLayout.add(buttons_layout);

        add(mLayout);

        //"generating level" label, invisible for now
        mLblWait = new Label();
        mLblWait.text = _("levelselect.waiting");
    }

    void gfxSelect(DropDownList list) {
        if (list.list.selectedIndex < 1)
            //first item (random) or nothing was selected
            mGfx = "";
        else
            mGfx = list.selection;
    }

    void waiting(bool w) {
        clear();
        if (w) {
            add(mLblWait, WidgetLayout.Noexpand);
        } else {
            add(mLayout);
        }
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
            onAccept(mLevel[idx], mGfx);
    }
}

class GenThread : Thread {
    private LevelSelector.LevelInfo mLvlConfig;
    private char[] mGfx;
    public Level finalLevel;

    this(LevelSelector.LevelInfo lvl, char[] gfx) {
        super();
        mLvlConfig = lvl;
        mGfx = gfx;
    }

    override int run() {
        scope gen = new LevelGenerator();
        finalLevel = generateAndSaveLevel(gen, mLvlConfig.templ,
            mLvlConfig.geo, gen.findRandomGfx(mGfx));
        return 0;
    }
}

//this is considered debug code until we have a proper game settings dialog
class LevelPreviewTask : Task {
    private {
        LevelSelector mSelector;
        Window mWMWindow;
        Task mGame;
        //background level rendering thread *g*
        GenThread mThread;
        bool mThWaiting = false;
    }

    this(TaskManager tm) {
        super(tm);
        mSelector = new LevelSelector();
        mSelector.onAccept = &lvlAccept;
        mWMWindow = gWindowManager.createWindow(this, mSelector,
            _("levelselect.caption"));
    }

    void lvlAccept(LevelSelector.LevelInfo lvl, char[] gfx) {
        //generate level
        //fix window size and show as waiting
        mWMWindow.acceptSize();
        mSelector.waiting = true;
        //start generation
        mThread = new GenThread(lvl, gfx);
        mThread.start();
        mThWaiting = true;
        //start game
        //play(level);
    }

    //play a level, hide this GUI while doing that, then return
    void play(Level level) {
        mWMWindow.visible = false;
        //reset preview dialog
        mSelector.waiting = false;

        assert(!mGame); //hm, no idea
        //create default GameConfig with custom level
        auto gc = loadGameConfig(globals.anyConfig.getSubNode("newgame"), level);
        //xxx: do some task-death-notification or so... (currently: polling)
        //currently, the game can't really return anyway...
        mGame = new GameTask(manager, gc);
    }

    override protected void onFrame() {
        //poll for game death
        if (mThWaiting) {
            if (mThread.getState() != Thread.TS.RUNNING) {
                //level generation finished, now start the game
                mThWaiting = false;
                play(mThread.finalLevel);
                mThread = null;
            }
        }
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
