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
import utils.misc;

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
        Button mIsCave, mPlaceObjects;
        Button[4] mWalls;
    }

    struct LevelInfo {
        GenerateFromTemplate generator;
    }

    void delegate(LevelGenerator selected) onAccept;

    this() {
        mGenerator = new LevelGeneratorShared();

        //"generating level" label, invisible for now
        mLblWait = new Label();
        mLblWait.text = translate("levelselect.waiting");


        auto conf = loadConfig("dialogs/levelpreview_gui");
        auto loader = new LoadGui(conf);
        loader.registerWidget!(PainterWidget)("painter");
        loader.load();

        mPainter = loader.lookup!(PainterWidget)("painter");
        mPainter.onChange = &painterChange;
        auto lgnode = loadConfig("levelgenerator")
            .getSubNode("preview_colors");
        mPainter.colorsFromNode(lgnode);

        mDdGfx = loader.lookup!(DropDownList)("dd_gfx");
        mDdGfx.onSelect = &gfxSelect;
        char[][] themes = ([translate("levelselect.randomgfx")]
            ~ mGenerator.themes.names());
        themes.sort;
        mDdGfx.list.setContents(themes);
        mDdGfx.selection = themes[0];

        int templCount = conf.getIntValue("template_count", 8);
        mPreviewHeight = conf.getIntValue("preview_height", mPreviewHeight);

        auto templ_trans = localeRoot.bindNamespace("templates");
        templ_trans.errorString = false;

        //generate one button for each level theme
        //xxx this will get too big if >8 templates, scrollbar?
        foreach (int i, LevelTemplate t; mGenerator.templates.all) {
            if (i >= templCount)
                break;
            //prepare button
            auto sb = loader.lookup!(Button)(myformat("level{}", i));
            sb.onClick = &levelClick;
            sb.onRightClick = &generate;
            mShowBitmap ~= sb;
            //insert info structure (matched by index)
            mLevel ~= LevelInfo(new GenerateFromTemplate(mGenerator, t));
            doGenerate(i);
            //add a description label below
            loader.lookup!(Label)(myformat("label{}", i)).text =
                templ_trans(t.description);
        }

        loader.lookup!(Button)("btn_clear").onClick = &clearClick;
        loader.lookup!(Button)("btn_fill").onClick = &fillClick;
        loader.lookup!(Button)("btn_cancel").onClick = &cancelClick;
        loader.lookup!(Button)("btn_ok").onClick = &okClick;
        mIsCave = loader.lookup!(Button)("chk_iscave");
        mIsCave.onClick = &button_painterchange;
        mPlaceObjects = loader.lookup!(Button)("chk_objects");
        mPlaceObjects.onClick = &button_painterchange;

        //xxx: get rid of the code duplication (the handler callbacks as well)
        mChkDrawMode ~= loader.lookup!(Button)("chk_circle");
        mChkDrawMode[$-1].onClick = &chkCircleClick;
        mChkDrawMode ~= loader.lookup!(Button)("chk_square");
        mChkDrawMode[$-1].onClick = &chkSquareClick;
        mChkDrawMode ~= loader.lookup!(Button)("chk_line");
        mChkDrawMode[$-1].onClick = &chkLineClick;
        mChkDrawMode ~= loader.lookup!(Button)("chk_rect");
        mChkDrawMode[$-1].onClick = &chkRectClick;

        foreach (int i, ref b; mWalls) {
            mWalls[i] = loader.lookup!(Button)(
                "chk_" ~ LevelLandscape.cWallNames[i]);
            mWalls[i].onClick = &button_painterchange;
        }

        mLayout = loader.lookup!(Widget)("levelpreview_root");
        add(mLayout);
    }

    void loadLevel(LevelGenerator lvl) {
        if (lvl) {
            LandscapeLexels lex = lvl.renderData();
            if (lex)
                mPainter.setData(lex.levelData, lex.size);
            //get parameters from loaded level
            auto props = lvl.properties();
            mIsCave.checked = props.isCave;
            mPlaceObjects.checked = props.placeObjects;
            foreach (int idx, bool hasWall; props.impenetrable) {
                assert(idx < mWalls.length);
                mWalls[idx].checked = hasWall;
            }
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

    //onClick for several unrelated buttons
    private void button_painterchange(Button sender) {
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
            bool[4] walls;
            for (int i = 0; i < 4; i++) {
                walls[i] = mWalls[i].checked;
            }
            lvl = lex.generator(mGenerator, mIsCave.checked,
                mPlaceObjects.checked, walls);
        }
        auto gen = cast(GenerateFromTemplate)lvl;
        if (gen)
            gen.selectTheme(mGenerator.themes.findRandom(mGfx));
        if (onAccept)
            onAccept(gen);
    }
}
