module gui.test;
import gui.container;
import gui.gui;
import gui.widget;
import gui.button;
import gui.boxcontainer;
import common.common;
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

        //start -> http://developer.gnome.org/doc/GGAD/figures/allpack.png
        struct BoxTest {
            bool hom, exp, fill;
        }
        char[][] texts = ["Small", "Large Child", "Even Larger Child"];
        BoxTest[] stuff = [
            BoxTest(false, false, false),
            BoxTest(false, true, false),
            BoxTest(false, true, true),
            BoxTest(true, false, false),
            //different to GTK: require expand to be set too
            //and I even don't know why!?
            BoxTest(true, true, true),
        ];

        static class ExtendContainer : SimpleContainer {
            Vector2i layoutSizeRequest() {
                return /+super.layoutSizeRequest() + +/Vector2i(600, 500);
            }
        }

        auto cont = new ExtendContainer();
        add(cont, WidgetLayout.Aligned(0, 0));

        auto vbox = new BoxContainer(false, false, 0);
        WidgetLayout w;
        w.expand[1] = false;
        cont.add(vbox, w);

        foreach (BoxTest bt; stuff) {
            auto hbox = new BoxContainer(true, bt.hom, 0);
            w = WidgetLayout.init;
            w.expand[0] = true;
            vbox.add(hbox, w);
            foreach (char[] t; texts) {
                WidgetLayout wl;
                wl.expand[0] = bt.exp;
                wl.fill[0] = bt.fill ? 1.0 : 0;
                auto label = new GuiButton();
                label.text = t;
                hbox.add(label, wl);
            }
        }
        //end -> http://developer.gnome.org/doc/GGAD/figures/allpack.png
    }
}
