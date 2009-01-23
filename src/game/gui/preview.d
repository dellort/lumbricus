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
import gui.loader;
import game.levelgen.generator;
import game.levelgen.level;
import game.levelgen.landscape;
import game.gui.levelpaint;
import utils.vector2;
import utils.rect2;

import str = stdx.string;

class LevelSelector : SimpleContainer {
    private {
        int mPreviewHeight = 70;

        int rowCount;
        Button[] mShowBitmap;
        LevelInfo[] mLevel;
        char[] mGfx;

        LevelGeneratorShared mGenerator;
        Label mLblInfo;
        Widget mLayout;
        Label mLblWait;
        DropDownList mDdGfx;
        PainterWidget mPainter;
        Button[] mChkDrawMode;
        //last selected level, null if the level has been modified
        LevelGenerator mLastLevel;
        bool mIsCave = false, mPlaceObjects = true;
    }

    struct LevelInfo {
        GenerateFromTemplate generator;
    }

    void delegate(LevelGenerator selected) onAccept;

    this() {
        mGenerator = new LevelGeneratorShared();

        //"generating level" label, invisible for now
        mLblWait = new Label();
        mLblWait.text = _("levelselect.waiting");


        auto conf = gFramework.loadConfig("levelpreview_gui");
        auto loader = new LoadGui(conf);
        loader.registerWidget!(PainterWidget)("painter");
        loader.load();

        mPainter = loader.lookup!(PainterWidget)("painter");
        mPainter.onChange = &painterChange;

        mDdGfx = loader.lookup!(DropDownList)("dd_gfx");
        mDdGfx.onSelect = &gfxSelect;
        char[][] themes = ([_("levelselect.randomgfx")]
            ~ mGenerator.themes.names());
        themes.sort;
        mDdGfx.list.setContents(themes);
        mDdGfx.selection = themes[0];

        int templCount = conf.getIntValue("template_count", 8);
        mPreviewHeight = conf.getIntValue("preview_height", mPreviewHeight);

        auto templ_trans = Translator.ByNamespace("templates");
        templ_trans.errorString = false;

        //generate one button for each level theme
        //xxx this will get too big if >8 templates, scrollbar?
        foreach (int i, LevelTemplate t; mGenerator.templates.all) {
            if (i >= templCount)
                break;
            //prepare button
            auto sb = loader.lookup!(Button)("level"~str.toString(i));
            sb.onClick = &levelClick;
            sb.onRightClick = &generate;
            mShowBitmap ~= sb;
            //insert info structure (matched by index)
            mLevel ~= LevelInfo(new GenerateFromTemplate(mGenerator, t));
            doGenerate(i);
            //add a description label below
            loader.lookup!(Label)("label"~str.toString(i)).text =
                templ_trans(t.description);
        }

        loader.lookup!(Button)("btn_clear").onClick = &clearClick;
        loader.lookup!(Button)("btn_fill").onClick = &fillClick;
        loader.lookup!(Button)("btn_cancel").onClick = &cancelClick;
        loader.lookup!(Button)("btn_ok").onClick = &okClick;
        loader.lookup!(Button)("chk_iscave").onClick = &chkIsCaveClick;
        loader.lookup!(Button)("chk_objects").onClick = &chkObjectsClick;

        mChkDrawMode ~= loader.lookup!(Button)("chk_circle");
        mChkDrawMode[$-1].onClick = &chkCircleClick;
        mChkDrawMode ~= loader.lookup!(Button)("chk_square");
        mChkDrawMode[$-1].onClick = &chkSquareClick;
        mChkDrawMode ~= loader.lookup!(Button)("chk_line");
        mChkDrawMode[$-1].onClick = &chkLineClick;
        mChkDrawMode ~= loader.lookup!(Button)("chk_rect");
        mChkDrawMode[$-1].onClick = &chkRectClick;

        mLayout = loader.lookup!(Widget)("levelpreview_root");
        add(mLayout);
    }

    void loadLevel(LevelGenerator lvl) {
        if (lvl) {
            LandscapeLexels lex = lvl.renderData();
            if (lex)
                mPainter.setData(lex.levelData, lex.size);
            mLastLevel = lvl;
        }
    }

    private void clearClick(Button sender) {
        mPainter.clear();
    }

    private void fillClick(Button sender) {
        mPainter.fillSolidSoft();
    }

    private void chkCircleClick(Button sender) {
        foreach (b; mChkDrawMode) {
            if (b != sender)
                b.checked = false;
        }
        mPainter.setDrawMode(DrawMode.circle);
    }

    private void chkSquareClick(Button sender) {
        foreach (b; mChkDrawMode) {
            if (b != sender)
                b.checked = false;
        }
        mPainter.setDrawMode(DrawMode.square);
    }

    private void chkLineClick(Button sender) {
        foreach (b; mChkDrawMode) {
            if (b != sender)
                b.checked = false;
        }
        mPainter.setDrawMode(DrawMode.line);
    }

    private void chkRectClick(Button sender) {
        foreach (b; mChkDrawMode) {
            if (b != sender)
                b.checked = false;
        }
        mPainter.setDrawMode(DrawMode.rect);
    }

    private void chkIsCaveClick(Button sender) {
        mIsCave = sender.checked;
        painterChange(mPainter);
    }

    private void chkObjectsClick(Button sender) {
        mPlaceObjects = sender.checked;
        painterChange(mPainter);
    }

    private void painterChange(PainterWidget sender) {
        mLastLevel = null;
    }

    private void gfxSelect(DropDownList list) {
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
        auto gen = mLevel[idx].generator;
        gen.generate();
        float as = gen.previewAspect();
        if (as != as)
            as = 1;
        auto sz = Vector2i(cast(int)(mPreviewHeight*as), mPreviewHeight);
        mShowBitmap[idx].image = gen.preview(sz);
    }

    private void levelClick(Button sender) {
        int idx = getIdx(sender);
        loadLevel(mLevel[idx].generator);
    }

    private void cancelClick(Button sender) {
        if (onAccept)
            onAccept(null);
    }

    private void okClick(Button sender) {
        LevelGenerator lvl = mLastLevel;
        if (!lvl) {
            LandscapeLexels lex = new LandscapeLexels();
            lex.levelData = mPainter.levelData;
            lex.size = mPainter.levelSize;
            lvl = lex.generator(mGenerator, mIsCave, mPlaceObjects);
        }
        auto gen = cast(GenerateFromTemplate)lvl;
        if (gen)
            gen.selectTheme(mGenerator.themes.findRandom(mGfx));
        if (onAccept)
            onAccept(gen);
    }
}
