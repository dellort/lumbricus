module game.gui.preview;

import framework.framework;
import gui.widget;
import gui.container;
import gui.button;
import gui.boxcontainer;
import game.gui.gameframe;
import levelgen.generator;
import utils.vector2;
import utils.rect2;

class BitmapFrame : GuiObjectOwnerDrawn {
    Surface bitmap;

    override Vector2i layoutSizeRequest() {
        return bitmap ? bitmap.size : Vector2i();
    }

    override void draw(Canvas c) {
        if (bitmap) {
            c.draw(bitmap.createTexture, Vector2i());
        }
    }
}

class LevelPreviewer : SimpleContainer {
    private {
        BitmapFrame mShowBitmap;
        LevelGenerator mGenerator;
        LevelGeometry mCurrent;
    }

    this() {
        auto buttons_layout = new BoxContainer(false, false, 5);
        WidgetLayout lay;
        lay.expand[1] = false; //don't expand in Y
        auto bt_next = new GuiButton();
        bt_next.text = "Next Level";
        bt_next.onClick = &next;
        buttons_layout.add(bt_next, lay);
        auto bt_play = new GuiButton();
        bt_play.text = "Play Level";
        bt_play.onClick = &play;
        buttons_layout.add(bt_play, lay);

        auto layout = new BoxContainer(true, false, 10);
        mShowBitmap = new BitmapFrame();
        layout.add(mShowBitmap);
        layout.add(buttons_layout);

        add(layout, WidgetLayout.Aligned(0,0));

        mGenerator = new LevelGenerator();

        next(bt_next);
    }

    private void next(GuiButton sender) {
        auto templ = mGenerator.findRandomTemplate("");
        mCurrent = templ.generate();
        //scale down (?)
        auto sz = toVector2i(toVector2f(templ.size)*0.15);
        mShowBitmap.bitmap = mGenerator.renderPreview(mCurrent,
            sz, Color(1,1,1), Color(0.8,0.8,0.8), Color(0.4,0.4,0.4));
        mShowBitmap.needRelayout();
    }

    private void play(GuiButton sender) {
        auto gf = new GameFrame(mCurrent);
        //xxx replace with the game window, but it'd be nice if you could come back
        gf.parent = this.parent;
        remove();
    }
}

