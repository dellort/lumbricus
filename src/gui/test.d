module gui.test;
import gui.container;
import gui.console;
import gui.wm;
import gui.widget;
import gui.button;
import gui.boxcontainer;
import gui.dropdownlist;
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
import utils.perf;
import utils.time;
import utils.array;
import utils.log;
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
        label.font = gFramework.fontManager.loadFont("test");
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

//popup test
class TestFrame7 : Container {
    Button mCreate;
    Vector2i mGravity;
    CheckBoxGroup mChk;
    Window mActivePopup;
    Widget mPopup;
    ScrollBar mAlign, mLength;
    Button mVolatile, mInside;

    this() {
        auto tc = new TableContainer(3, 3, Vector2i(10));
        Button[4] chk;
        foreach (inout b; chk) {
            b = new Button();
            b.onClick = &onChk;
            b.isCheckbox = true;
            mChk.add(b);
        }
        tc.add(chk[0], 0, 1);
        tc.add(chk[1], 1, 0);
        tc.add(chk[2], 2, 1);
        tc.add(chk[3], 1, 2);
        auto inner = new BoxContainer(false);
        mCreate = new Button();
        mCreate.text = "Create Popup";
        mCreate.onClick = &onCreate;
        inner.add(mCreate);
        mAlign = new ScrollBar(true);
        mAlign.maxValue = 99;
        mAlign.minValue = 0;
        mAlign.onValueChange = &onAlign;
        inner.add(mAlign);
        mLength = new ScrollBar(true);
        mLength.maxValue = 30;
        mLength.minValue = 1;
        mLength.onValueChange = &onAlign;
        inner.add(mLength);
        mVolatile = new Button();
        mVolatile.isCheckbox = true;
        mVolatile.text = "Volatile";
        inner.add(mVolatile);
        mInside = new Button;
        mInside.isCheckbox = true;
        mInside.text = "Inside Wnd.";
        inner.add(mInside);
        tc.add(inner, 1, 1);
        addChild(tc);
        Label p = new Label();
        p.text = "Hi! I'm a popup or so!";
        mPopup = p;
    }

    void onChk(Button b) {
        mChk.check(b);
        update();
    }

    void onAlign(ScrollBar b) {
        update();
    }

    void onCreate(Button b) {
        if (mActivePopup)
            mActivePopup.destroy();
        mActivePopup = gWindowManager.createPopup(mPopup, this,
            Vector2i(0), Vector2i(0), false);
        update();
        mActivePopup.visible = true;
    }

    void update() {
        if (!mActivePopup)
            return;
        WindowInitialPlacement p;
        Widget w = mInside;
        p.relative = mInside.checked ? w : findWindowForWidget(this).window;
        p.place = WindowInitialPlacement.Placement.gravity;
        Vector2i sel(int idx) {
            switch (idx) {
                case 0: return Vector2i(-1, 0);
                case 1: return Vector2i(0, -1);
                case 2: return Vector2i(+1, 0);
                default /+3+/: return Vector2i(0, +1);
            }
        }
        p.gravity = sel(mChk.checkedIndex())*mLength.curValue;
        p.gravityAlign = 1.0f*mAlign.curValue/(mAlign.maxValue+1);
        mActivePopup.isFocusVolatile = mVolatile.checked;
        mActivePopup.initialPlacement = p;
        mActivePopup.updatePlacement();
    }
}

class TestFrame8 : Container {
    DropDownList mList;
    Label mInfo;
    int mSelCount;

    void select(DropDownList list) {
        mInfo.text = str.format("sel %d: '%s'", mSelCount, list.selection);
        mSelCount++;
    }

    this() {
        mList = new DropDownList();
        mList.onSelect = &select;
        mList.list.setContents(["hallo", "blablabla", "123...", "foo", "end"]);
        mInfo = new Label();
        auto box = new BoxContainer(false);
        box.add(mList);
        box.add(mInfo);
        addChild(box);
    }
}

//not really GUI related
class TestGradient : Container {
    Button mChk;
    class Draw : Widget {
        override void onDraw(Canvas c) {
            auto rc = widgetBounds();
            rc.extendBorder(Vector2i(-20));
            if (mChk.checked) {
                c.drawVGradient(rc, Color(1,0,0), Color(0,1,0));
            } else {
                c.drawFilledRect(rc.p1, rc.p2, Color(1,0,0));
            }
        }
    }
    this() {
        auto b = new BoxContainer(false);
        auto d = new Draw();
        b.add(d);
        mChk = new Button();
        mChk.isCheckbox = true;
        mChk.text = "gradient versus solid rect";
        b.add(mChk, WidgetLayout.Noexpand());
        addChild(b);
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
        auto checkbox = new Button();
        checkbox.isCheckbox = true;
        checkbox.text = "Hello I'm a checkbox!";
        checkbox.shrink = true; //for more testing
        createWindow("CheckBox", checkbox);
        createWindow("Popup-Test", new TestFrame7());
        createWindow("DropDownList", new TestFrame8());
        createWindow("Test gradient", new TestGradient());

        auto k = new Button();
        k.text = "Kill!!!1";
        k.onClick = &onKill;
        createWindow("hihi", k);

        //test loading GUIs from file
        auto loader = new LoadGui(gFramework.loadConfig("test_gui"));
        loader.load();
        createWindow("Test5", loader.lookup("root"));

        //two scrollbars
        auto bar1 = new ScrollBar(false);
        bar1.maxValue = 100;
        createWindow("Test6", bar1);
        auto bar2 = new ScrollBar(true);
        bar2.maxValue = 100;
        bar2.pageSize = 30;
        bar2.largeChange = 30;
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
            //need clone() here, or the default font will be freed later
            font = gFramework.fontManager.getStyle("");
            updateFont();
        }

        override protected void layoutSizeAllocation() {
            updateFont();
        }

        void updateFont() {
            //font size isn't in pixels, but in "points"
            //no idea how to convert these
            font.size = size.y-cBorder.y*4;
            auto oldf = f;
            f = new Font(font);
            if (oldf) {
                oldf.free();
            }
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
    ScrollBar[5] mBars;

    void onScrollbar(ScrollBar sender) {
        float getcolor(int n) {
            return mBars[n].curValue/255.0f;
        }
        mFont.font.fore.a = getcolor(0);
        mFont.font.back.a = getcolor(1);
        mFont.updateFont();
        mBox.box.border.a = getcolor(0);
        mBox.box.back.a = getcolor(1);
        mBox.box.cornerRadius = mBars[3].curValue;
        mBox.box.borderWidth = mBars[4].curValue;
        Color clear = Color(1.0f-getcolor(2),0,0);
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

        auto scr = new TableContainer(2, 5, Vector2i(15, 1));
        char[][] labels = ["foreground/border alpha", "background alpha",
            "container red", "corner size", "border size"];
        int[] values = [128, 128, 0, 5, 1];
        int[] maxvals = [255, 255, 255, 50, 50];

        for (int n = 0; n < mBars.length; n++) {
            auto la = new Label();
            la.font = gFramework.getFont("normal");
            la.text = labels[n];
            la.drawBorder = false;
            scr.add(la, 0, n, WidgetLayout.Aligned(-1,0));

            auto bar = new ScrollBar(true);
            mBars[n] = bar;
            bar.maxValue = maxvals[n];
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

class TestTask3 : Task {
    ScrollBar[4] mBars;
    ImgView mView;
    char[] filename = "storedlevels/bla.png";
    Label mValues;
    StringListWidget mFList;

    void apply(Surface s) {
        float b = 2.0f*mBars[0].curValue/mBars[0].maxValue - 1.0f;
        float c = 2.0f*mBars[1].curValue/mBars[1].maxValue;
        float g = 10.0f*mBars[2].curValue/mBars[2].maxValue;
        float a = 1.0f*mBars[3].curValue/mBars[3].maxValue;
        auto t = new PerfTimer(true);
        t.start();
        s.mapColorChannels((Color cl) {
            cl = cl.applyBCG(b, c, g);
            cl.a *= a;
            return cl;
        });
        t.stop();
        mValues.text = str.format("size=%s, took=%s, b=%s, c=%s, g=%s, a=%s",
            s.size, t.time, b, c, g, a);
    }

    class ImgView : Widget {
        Surface source, current;

        //warning, frees old surface
        void setSource(Surface s) {
            if (source)
                source.free();
            source = s;
            update();
            needRelayout();
        }

        void update() {
            if (current)
                current.free();
            current = null;
            if (source) {
                current = source.clone();
                apply(current);
            }
        }

        protected override Vector2i layoutSizeRequest() {
            return current ? current.size() : Vector2i(0);
        }

        override void onDraw(Canvas c) {
            if (current)
                c.draw(current, Vector2i(0));
        }
    }

    void onScrollbar(ScrollBar sender) {
        mView.update();
    }

    void onSelFile(int index) {
        if (index >= 0) {
            Surface img;
            try {
                img = gFramework.loadImage(mFList.contents[index]);
            } catch (Exception e) {
                mValues.text = "couldn't load, " ~ e.toString;
            }
            mView.setSource(img);
        }
    }

    this(TaskManager tm) {
        super(tm);

        //yes, most code copypasted from alphatest
        auto tgui = new BoxContainer(true, false, 3);
        mFList = new StringListWidget();
        mFList.onSelect = &onSelFile;
        mFList.checkWidth = true;
        auto listwind = new ScrollWindow(mFList, [false, true]);
        listwind.enableMouseWheel = true;
        tgui.add(listwind, WidgetLayout.Expand(false));
        auto gui = new BoxContainer(false, false, 3);
        tgui.add(gui);
        mView = new ImgView();
        auto cnt = new ScrollWindow();
        cnt.setScrollArea(new MouseScroller());
        cnt.area.add(mView);
        gui.add(cnt);

        auto scr = new TableContainer(2, 4, Vector2i(15, 1));
        char[][] labels = ["brightness", "contrast", "gamma", "alpha"];
        int[] values = [50, 50, 10, 100];
        int[] maxvals = [100, 100, 100, 100];

        for (int n = 0; n < mBars.length; n++) {
            auto la = new Label();
            la.font = gFramework.getFont("normal");
            la.text = labels[n];
            la.drawBorder = false;
            scr.add(la, 0, n, WidgetLayout.Aligned(-1,0));

            auto bar = new ScrollBar(true);
            mBars[n] = bar;
            bar.maxValue = maxvals[n];
            bar.curValue = values[n];
            bar.onValueChange = &onScrollbar;
            scr.add(bar, 1, n, WidgetLayout.Border(Vector2i(3)));
        }

        auto sp = new Spacer();
        sp.minSize = Vector2i(0,2);
        sp.color = Color(0);
        gui.add(sp, WidgetLayout.Expand(true));

        gui.add(scr, WidgetLayout.Expand(true));

        mValues = new Label();
        mValues.font = gFramework.getFont("normal");
        mValues.drawBorder = false;
        gui.add(mValues, WidgetLayout.Aligned(-1, 0));

        char[][] files;
        gFramework.fs.listdir("/", "*", false,
            (char[] path) {
                files ~= path;
                return true;
            }
        );
        mFList.setContents(files);

        gWindowManager.createWindow(this, tgui, "BCG test", Vector2i(450, 300));
    }

    static this() {
        TaskFactory.register!(typeof(this))("bcg");
    }
}
