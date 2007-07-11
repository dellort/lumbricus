module game.gui.preview;

import framework.framework;
import gui.widget;
import gui.container;
import gui.button;
import gui.boxcontainer;
import gui.label;
import game.gui.gameframe;
import levelgen.generator;
import utils.vector2;
import utils.rect2;

class BitmapButton : GuiButton {
    Surface bitmap;
    void delegate(GuiButton sender) onRightClick;

    override Vector2i layoutSizeRequest() {
        return bitmap ? bitmap.size : Vector2i();
    }

    override void draw(Canvas c) {
        if (bitmap) {
            c.draw(bitmap.createTexture, Vector2i());
        }
    }

    override protected bool onKeyUp(char[] bind, KeyInfo key) {
        if (key.code == Keycode.MOUSE_RIGHT) {
            if (onRightClick) {
                onRightClick(this);
            }
            return true;
        }
        return super.onKeyUp(bind, key);
    }
}

class LevelPreviewer : SimpleContainer {
    private {
        const cRows = 3;
        const cCols = 2;
        BitmapButton[cRows*cCols] mShowBitmap;
        LevelGeometry[cRows*cCols] mLevel;
        LevelGenerator mGenerator;
        GuiLabel mLblInfo;
    }

    this() {
        mGenerator = new LevelGenerator();

        BoxContainer[cRows+1] buttons_layout;
        foreach (inout bc; buttons_layout) {
            bc = new BoxContainer(true, false, 10);
        }
        WidgetLayout lay;
        lay.expand[1] = false; //don't expand in Y

        mLblInfo = new GuiLabel();
        mLblInfo.text = "Select level to play, right click to regenerate";

        foreach (int i, inout BitmapButton sb; mShowBitmap) {
            sb = new BitmapButton();
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

    private int getIdx(GuiButton which) {
        foreach (int i, BitmapButton b; mShowBitmap) {
            if (b == which)
                return i;
        }
        assert(false);
    }

    private void generate(GuiButton sender) {
        int idx = getIdx(sender);
        doGenerate(idx);
    }

    private void doGenerate(int idx) {
        auto templ = mGenerator.findRandomTemplate("");
        mLevel[idx] = templ.generate();
        //scale down (?)
        auto sz = toVector2i(toVector2f(templ.size)*0.15);
        mShowBitmap[idx].bitmap = mGenerator.renderPreview(mLevel[idx],
            sz, Color(1,1,1), Color(0.8,0.8,0.8), Color(0.4,0.4,0.4));
        mShowBitmap[idx].needRelayout();
    }

    private void play(GuiButton sender) {
        int idx = getIdx(sender);
        auto gf = new GameFrame(mLevel[idx]);
        //xxx replace with the game window, but it'd be nice if you could come back
        gf.parent = this.parent;
        remove();
    }
}

