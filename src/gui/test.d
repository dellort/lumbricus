module gui.test;
import gui.container;
import gui.gui;
import gui.widget;
import gui.button;
import game.common;
import framework.commandline : CommandBucket, Command;
import utils.mybox;
import utils.output;
import utils.time;
import utils.array;
import utils.vector2;
import str = std.string;

class TestFrame : SimpleContainer {
    private GuiButton[] mButtons;

    private void foo(GuiButton sender) {
        globals.cmdLine.console.writefln("button: %s", arraySearch(mButtons, sender));
    }

    this() {
        super();

        void put(int nr, int x, int y) {
            auto label = new GuiButton();
            label.onClick = &foo;
            label.text = str.format("Label %s", nr);
            add(label, WidgetLayout.Aligned(x, y, Vector2i(10, 40)));
            mButtons ~= label;
        }

        put(0, -1, -1); //0
        put(1,  0, -1);
        put(2, +1, -1); //2
        put(3, -1,  0);
        put(4,  0,  0); //4
        put(5, +1,  0);
        put(6, -1, +1); //6
        put(7,  0, +1);
        put(8, +1, +1); //8
    }
}
