module gui.test;
import gui.container;
import gui.console;
import gui.wm;
import gui.widget;
import gui.button;
import gui.boxcontainer;
import gui.edit;
import gui.tablecontainer;
import gui.label;
import gui.list;
import gui.mousescroller;
import gui.scrollbar;
import gui.scrollwindow;
import gui.loader;
import common.common;
import common.task;
import common.visual;
import framework.framework;
import framework.font;
import framework.commandline : CommandBucket, Command;
import utils.mybox;
import utils.output;
import utils.time;
import utils.array;
import utils.rect2;
import utils.vector2;
import str = std.string;

import gui.window;

class TestFrame : SimpleContainer {
    private Button[] mButtons;

    private void foo(Button sender) {
        globals.defaultOut.writefln("button: %s", arraySearch(mButtons, sender));
    }

    this() {
        void put(int nr, int x, int y) {
            auto label = new Button();
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

class TestFrame2 : SimpleContainer {
    this() {
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

        auto vbox = new BoxContainer(false, false, 0);
        WidgetLayout w;
        w.expand[1] = false;
        add(vbox, w);

        foreach (BoxTest bt; stuff) {
            auto hbox = new BoxContainer(true, bt.hom, 0);
            w = WidgetLayout.init;
            w.expand[0] = true;
            vbox.add(hbox, w);
            foreach (char[] t; texts) {
                WidgetLayout wl;
                wl.expand[0] = bt.exp;
                wl.fill[0] = bt.fill ? 1.0 : 0;
                auto label = new Label();
                label.text = t;
                hbox.add(label, wl);
            }
        }
        //end -> http://developer.gnome.org/doc/GGAD/figures/allpack.png
    }
}

class TestFrame3 : Container {
    this() {
        auto wind = new ScrollWindow();
        auto scroll = new MouseScroller();
        wind.setScrollArea(scroll);
        auto label = new Label();
        scroll.add(label);
        label.text = "MouseScroller huhuh!";
        label.font = getFramework.fontManager.loadFont("test");
        addChild(wind);
    }
}

class TestFrame4 : Container {
    class Bla : Widget {
        override protected Vector2i layoutSizeRequest() {
            return Vector2i(500, 500);
        }
        override  void onDraw(Canvas canvas) {
            auto rc = canvas.getVisible();
            rc.extendBorder(-Vector2i(5));
            canvas.drawFilledRect(rc.p1, rc.p2, Color(1,0,0));
            auto x1 = Vector2i(0), x2 = size-Vector2i(1);
            canvas.drawRect(x1, x2, Color(0));
            canvas.drawLine(x1, x2, Color(0));
            canvas.drawLine(x2.Y, x2.X, Color(0));
        }
    }
    this() {
        auto wind = new ScrollWindow();
        auto label = new Label();
        wind.area.add(new Bla());
        addChild(wind);
    }
}

class TestFrame5 : Container {
    this() {
        auto list = new StringListWidget();
        list.checkWidth = true;
        list.setContents([
            "entry 1",
            "blablabla",
            "entry 3",
            "when i was in alabama",
            "my turtle ate a banana",
            "entry 6",
            "even",
            "more",
            "stupid",
            "text"
        ]);
        auto wind = new ScrollWindow(list, [false, true]);
        addChild(wind);
    }
}

class TestFrame6 : Container {
    this() {
        auto cons = new GuiConsole;
        cons.output.writefln("list commands with /help");
        cons.cmdline.registerCommand("say", &cmdSay, "hullo!",
            ["text...:what you say"]);
        cons.cmdline.setPrefix("/", "say");
        addChild(cons);
    }

    void cmdSay(MyBox[] args, Output write) {
        write.writefln("you said: '%s'", args[0].unbox!(char[]));
    }
}

//just to show the testframe
class TestTask : Task {
    //private Widget mWindow;

    this(TaskManager tm) {
        super(tm);

        //xxx move to WindowFrame
        void createWindow(char[] name, Widget client) {
            gWindowManager.createWindow(this, client, name);
        }

        createWindow("TestFrame", new TestFrame);
        createWindow("TestFrame2", new TestFrame2);
        createWindow("TestFrame3", new TestFrame3);
        createWindow("Visibility Test", new TestFrame4);
        createWindow("List", new TestFrame5);
        auto editl = new EditLine;
        editl.prompt = "> ";
        createWindow("EditLine", editl);
        createWindow("Console", new TestFrame6);

        auto k = new Button();
        k.text = "Kill!!!1";
        k.onClick = &onKill;
        createWindow("hihi", k);

        //test loading GUIs from file
        auto loader = new LoadGui(globals.loadConfig("test_gui"));
        loader.load();
        createWindow("Test5", loader.lookup("root"));

        //two scrollbars
        auto bar1 = new ScrollBar(false);
        bar1.maxValue = 100;
        createWindow("Test6", bar1);
        auto bar2 = new ScrollBar(true);
        bar2.maxValue = 100;
        bar2.pageSize = 30;
        createWindow("Test6", bar2);

//        getFramework.clearColor = Color(1,1,1);
    }

    private void onKill(Button b) {
        terminate();
    }

    override protected void onKill() {
        //mWindow.remove();
    }

    static this() {
        TaskFactory.register!(typeof(this))("testtask");
    }
}

class TestTask2 : Task {
    const cBorder = Vector2i(10);

    class FontTest : Widget {
        FontProperties font;
        Color clear;
        Font f;

        this() {
            f = gFramework.getFont("");
        }

        override protected void layoutSizeAllocation() {
            updateFont();
        }

        void updateFont() {
            //font size isn't in pixels, but in "points"
            //no idea how to convert these
            font.size = size.y-cBorder.y*4;
            auto oldf = f;
            f = f.clone(font);
            oldf.free();
        }

        override void onDraw(Canvas c) {
            c.drawFilledRect(Vector2i(0), size, clear);
            f.drawText(c, cBorder, "Ab");
        }
    }

    class BoxTest : Widget {
        BoxProperties box;
        Color clear;

        override void onDraw(Canvas c) {
            c.drawFilledRect(Vector2i(0), size, clear);
            auto rc = widgetBounds;
            rc.extendBorder(-cBorder);
            drawBox(c, rc, box);
        }
    }

    FontTest mFont;
    BoxTest mBox;
    ScrollBar[3] mBars;

    void onScrollbar(ScrollBar sender) {
        float getcolor(int n) {
            return mBars[n].curValue/255.0f;
        }
        mFont.font.fore.a = getcolor(0);
        mFont.font.back.a = getcolor(1);
        mFont.updateFont();
        mBox.box.back.a = getcolor(0);
        mBox.box.border.a = getcolor(1);
        Color clear = Color(getcolor(2),1,1);
        mFont.clear = clear;
        mBox.clear = clear;

        gFramework.releaseCaches();
    }

    this(TaskManager tm) {
        super(tm);

        mFont = new FontTest();
        mBox = new BoxTest();

        auto gui = new BoxContainer(false, false, 3);
        auto cnt = new BoxContainer(true);
        cnt.add(mFont);
        cnt.add(mBox);
        gui.add(cnt);

        auto scr = new TableContainer(2, 3, Vector2i(15, 1));
        char[][] labels = ["foreground/border alpha", "background alpha",
            "container red"];
        int[] values = [128, 128, 0];

        for (int n = 0; n < mBars.length; n++) {
            auto la = new Label();
            la.font = gFramework.getFont("normal");
            la.text = labels[n];
            la.drawBorder = false;
            scr.add(la, 0, n, WidgetLayout.Aligned(-1,0));

            auto bar = new ScrollBar(true);
            mBars[n] = bar;
            bar.maxValue = 255;
            bar.curValue = values[n];
            bar.onValueChange = &onScrollbar;
            scr.add(bar, 1, n, WidgetLayout.Border(Vector2i(3)));
        }

        auto sp = new Spacer();
        sp.minSize = Vector2i(0,2);
        sp.color = Color(0);
        gui.add(sp, WidgetLayout.Expand(true));

        gui.add(scr, WidgetLayout.Expand(true));

        onScrollbar(null); //update

        gWindowManager.createWindow(this, gui, "Alpha test",
            Vector2i(450, 300));
    }

    static this() {
        TaskFactory.register!(typeof(this))("alphatest");
    }
}
