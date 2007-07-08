module gui.test;
import gui.frame;
import gui.gui;
import gui.guiobject;
import gui.layout;
import gui.label;
import framework.commandline : CommandBucket, Command;
import utils.mybox;
import utils.output;
import utils.time;
import utils.vector2;
import str = std.string;

class TestFrame : GuiFrame {
    private {
        GuiLayouterAlign mAlign;
    }

    this() {
        mAlign = new GuiLayouterAlign;
        addLayouter(mAlign);

        void put(int nr, int x, int y) {
            auto label = new GuiLabel();
            label.text = str.format("Label %s", nr);
            mAlign.add(label, x, y, Vector2i(10, 40));
        }

        put(0, -1, -1);
        put(1,  0, -1);
        put(2, +1, -1);
        put(3, -1,  0);
        put(4,  0,  0);
        put(5, +1,  0);
        put(6, -1, +1);
        put(7,  0, +1);
        put(8, +1, +1);
    }
}
