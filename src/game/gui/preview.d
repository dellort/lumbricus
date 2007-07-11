module gui.preview;

import framework.framework;
import gui.guiobject;
import gui.frame;
import gui.button;
import gui.layout;
import gui.preview;
import gui.gameframe;
import levelgen.generator;
import utils.vector2;
import utils.rect2;

class BitmapFrame : GuiObjectOwnerDrawn {
    Surface bitmap;

    override void getLayoutConstraints(out LayoutConstraints lc) {
        if (bitmap) {
            lc.minSize = bitmap.size;
        }
    }

    override void draw(Canvas c) {
        if (bitmap) {
            c.draw(bitmap.createTexture, bounds.p1);
        }
    }
}

class LevelPreviewer : GuiFrame {
    private {
        BitmapFrame mShowBitmap;
        LevelGenerator mGenerator;
        LevelGeometry mCurrent;
    }

    this() {
        auto buttons_layout = new GuiLayouterRow(false, false);
        auto buttons = new GuiFrame();
        buttons_layout.frame = buttons;
        buttons_layout.spacing = Vector2i(2, 3);
        buttons.virtualFrame = true;
        buttons.addLayouter(buttons_layout);
        auto bt_next = new GuiButton();
        bt_next.text = "Next Level";
        bt_next.onClick = &next;
        buttons_layout.add(bt_next);
        auto bt_play = new GuiButton();
        bt_play.text = "Play Level";
        bt_play.onClick = &play;
        buttons_layout.add(bt_play);

        //global layout: like a scalable vector graphic for now
        auto layout = new GuiLayouterAlign();
        layout.frame = this;
        layout.add(buttons, Rect2f(0.7, 0.3, 0.9, 0.7));
        mShowBitmap = new BitmapFrame();
        layout.add(mShowBitmap, Rect2f(0.2, 0.3, 0.6, 0.7));

        addLayouter(layout);

        mGenerator = new LevelGenerator();

        next();
    }

    private void next() {
        auto templ = mGenerator.findRandomTemplate("");
        mCurrent = templ.generate();
        //scale down (?)
        auto sz = toVector2i(toVector2f(templ.size)*0.15);
        mShowBitmap.bitmap = mGenerator.renderPreview(mCurrent,
            sz, Color(1,1,1), Color(0.8,0.8,0.8), Color(0.4,0.4,0.4));
    }

    private void play() {
        auto gf = new GameFrame(mCurrent);
        //xxx replace with the game window, but it'd be nice if you could come back
        gf.parent = this.parent;
        remove();
    }
}
