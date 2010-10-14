module gui.test;

import framework.imgread;
import gui.container;
import gui.console;
import gui.global;
import gui.menu;
import gui.window;
import gui.widget;
import gui.button;
import gui.boxcontainer;
import gui.dropdownlist;
import gui.edit;
import gui.tablecontainer;
import gui.label;
import gui.list;
import gui.logwindow;
import gui.mousescroller;
import gui.scrollbar;
import gui.scrollwindow;
import gui.splitter;
import gui.loader;
import gui.tabs;
import gui.progress;
import common.task;
import gui.renderbox;
import gui.rendertext;
import framework.drawing;
import framework.event;
import framework.filesystem;
import framework.main;
import framework.surface;
import framework.config;
import framework.font;
import framework.commandline : CommandBucket, Command;
import utils.mybox : MyBox;
import utils.output;
import utils.perf;
import utils.time;
import utils.array;
import utils.log;
import utils.rect2;
import utils.vector2;
import utils.misc;

import gui.window;

class TestFrame : SimpleContainer {
    private Button[] mButtons;

    private void foo(Button sender) {
        gLog.notice("button: {}", arraySearch(mButtons, sender));
    }

    this() {
        void put(int nr, int x, int y) {
            auto label = new Button();
            label.onClick = &foo;
            label.text = myformat("Label {}", nr);
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
        auto label = new Button();
        scroll.add(label);
        label.text = "MouseScroller huhuh!";
        //label.font = gFontManager.loadFont("test");
        addChild(wind);
    }
}

class TestFrame4 : Container {
    class Bla : Widget {
        override protected Vector2i layoutSizeRequest() {
            return Vector2i(500, 500);
        }
        override  void onDraw(Canvas canvas) {
            auto rc = canvas.visibleArea();
            rc.extendBorder(-Vector2i(5));
            canvas.drawFilledRect(rc, Color(1,0,0));
            auto x1 = Vector2i(0), x2 = size-Vector2i(1);
            canvas.drawRect(Rect2i(x1, x2), Color(0));
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
        write.writefln("you said: '{}'", args[0].unbox!(char[]));
    }
}

//popup test
class TestFrame7 : Container {
    Button mCreate;
    Vector2i mGravity;
    CheckBoxGroup mChk;
    WindowWidget mActivePopup;
    Widget mPopup;
    ScrollBar mAlign, mLength;
    CheckBox mVolatile, mInside;

    this() {
        auto tc = new TableContainer(3, 3, Vector2i(10));
        CheckBox[4] chk;
        foreach (inout b; chk) {
            b = new CheckBox();
            b.onClick = &onChk;
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
        mVolatile = new CheckBox();
        mVolatile.text = "Volatile";
        inner.add(mVolatile);
        mInside = new CheckBox();
        mInside.text = "Inside Wnd.";
        inner.add(mInside);
        tc.add(inner, 1, 1);
        addChild(tc);
        Label p = new Label();
        p.text = "Hi! I'm a popup or so!";
        p.styles.addClass("worm-label"); //something with border
        mPopup = p;
    }

    void onChk(CheckBox b) {
        mChk.check(b);
        //update();
    }

    void onAlign(ScrollBar b) {
        //update();
    }

    void onCreate(Button b) {
        // code killed in r1103
    }
}

class TestFrame8 : Container {
    DropDownList mList;
    Label mInfo;
    int mSelCount;

    void select(DropDownList list) {
        mInfo.text = myformat("sel {}: '{}'", mSelCount, list.selection);
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

class TestFrame9 : Container {
    class T : Container {
        this(int r) {
            auto x = new Label();
            x.text = myformat("{}", r);
            auto props = gFontManager.loadFont("normal").properties();
            props.size += r*10; //just to have different request sizes
            x.styles.setStyleOverrideT!(Font)("text-font",
                gFontManager.create(props));
            addChild(x);
        }
        override void onDraw(Canvas c) {
            super.onDraw(c);
            c.drawRect(widgetBounds, Color(0));
        }
    }
    this() {
        auto s = new VSplitter();
        s.setChild(0, new T(0));
        s.setChild(1, new T(1));
        addChild(s);
    }
}

//not really GUI related
class TestGradient : Container {
    CheckBox mChk;
    class Draw : Widget {
        override void onDraw(Canvas c) {
            auto rc = widgetBounds();
            rc.extendBorder(Vector2i(-20));
            Rect2i rc2;
            rc2 = rc;
            rc2.p1.y = rc.p2.y/2;
            rc.p2.y = rc.p2.y/2;
            if (mChk.checked) {
                c.drawVGradient(rc, Color.fromBytes(16,20,40), Color.fromBytes(46,23,0));
                c.drawVGradient(rc2, Color.fromBytes(46,23,0), Color.fromBytes(2,1,0));
            } else {
                c.drawFilledRect(rc, Color(1,0,0));
            }
        }
    }
    this() {
        auto b = new BoxContainer(false);
        auto d = new Draw();
        b.add(d);
        mChk = new CheckBox();
        mChk.text = "gradient versus solid rect";
        b.add(mChk, WidgetLayout.Noexpand());
        addChild(b);
    }
}

class TestFrame10 : Container {
    this() {
        auto tabs = new Tabs();
        addChild(tabs);
        auto c1 = new Label();
        c1.text = "tab 1 client area";
        c1.setLayout(WidgetLayout.Noexpand());
        tabs.addTab(c1, "Tab 1 lol");
        auto c2 = new Label();
        c2.text = "client area of tab 2";
        //try to be a bit different
        auto fp = c2.font.properties;
        fp.size = 70;
        fp.border_width = 3;
        fp.border_color = Color(1, 0, 0);
        c2.styles.setStyleOverrideT!(Font)("text-font",
            gFontManager.create(fp));
        tabs.addTab(c2, "Tab 2");
        auto c3 = new Label();
        c3.text = "tab 3";
        c3.setLayout(WidgetLayout.Noexpand());
        tabs.addTab(c3, "Tab 3 ...");
    }
}

//just to show the testframe
class TestTask {
    //private Widget mWindow;

    this() {
        //xxx move to WindowFrame
        void createWindow(char[] name, Widget client) {
            gWindowFrame.createWindow(client, name);
        }

        createWindow("TestFrame", new TestFrame);
        createWindow("TestFrame2", new TestFrame2);
        createWindow("TestFrame3", new TestFrame3);
        createWindow("Visibility Test", new TestFrame4);
        createWindow("List", new TestFrame5);
        auto editl = new EditLine;
        createWindow("EditLine", editl);
        createWindow("Console", new TestFrame6);
        auto checkbox = new CheckBox();
        checkbox.text = "Hello I'm a checkbox!";
        //checkbox.shrink = true; //for more testing
        createWindow("CheckBox", checkbox);
        createWindow("Popup-Test", new TestFrame7());
        createWindow("DropDownList", new TestFrame8());
        createWindow("Splitter", new TestFrame9());
        createWindow("Test gradient", new TestGradient());
        createWindow("Tabs", new TestFrame10());

        //test loading GUIs from file
        auto loader = new LoadGui(loadConfig("dialogs/test_gui.conf"));
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

    static this() {
        registerTaskClass!(typeof(this))("testtask");
    }
}

class TestTask2 {
    const cBorder = Vector2i(10);

    class FontTest : Widget {
        FontProperties font;
        Color clear;
        Font f;

        this() {
            //need clone() here, or the default font will be freed later
            font = gFontManager.getStyle("");
            updateFont();
        }

        override protected void layoutSizeAllocation() {
            updateFont();
        }

        //non-sensical test for custom mouse cursors
        override MouseCursor mouseCursor() {
            MouseCursor res;
            res.graphic = gGuiResources.get!(Surface)("window_maximize");
            res.graphic_spot = res.graphic.size/2;
            return res;
        }

        void updateFont() {
            //font size isn't in pixels, but in "points"
            //no idea how to convert these
            font.size = size.y-cBorder.y*4;
            //if (!f || font.size != f.properties.size
            //    || font.border_width != f.properties.border_width)
            //{
            //    Trace.formatln("New Font");
                auto oldf = f;
                f = new Font(font);
                if (oldf) {
                    oldf.free();
                }
            //}
        }

        override void onDraw(Canvas c) {
            c.drawFilledRect(Rect2i(size), clear);
            f.drawText(c, cBorder, "Ab");
        }
    }

    class BoxTest : Widget {
        BoxProperties box;
        Color clear;

        override void onDraw(Canvas c) {
            c.drawFilledRect(Rect2i(size), clear);
            auto rc = widgetBounds;
            rc.extendBorder(-cBorder);
            drawBox(c, rc, box);
        }
    }

    FontTest mFont;
    BoxTest mBox;
    ScrollBar[6] mBars;
    CheckBox mBevel, mNotRounded;

    void onScrollbar(ScrollBar sender) {
        float getcolor(int n) {
            return mBars[n].curValue/255.0f;
        }
        mFont.font.fore_color = Color(1,1,1,getcolor(0));
        mFont.font.back_color.a = 0; //getcolor(1);
        mFont.font.border_color = Color(0.5,1.0,0.5,getcolor(1));
        mFont.font.border_width = mBars[4].curValue;
        mFont.font.shadow_offset = mBars[5].curValue;
        mFont.font.shadow_color = Color(0.5,0.5,0.5,0.5);
        mFont.updateFont();
        mBox.box.border = mFont.font.border_color;
        mBox.box.back = mFont.font.fore_color;
        mBox.box.cornerRadius = mBars[3].curValue;
        mBox.box.borderWidth = mFont.font.border_width;
        Color clear = Color(1.0f,1.0-getcolor(2),1.0-getcolor(2));
        mFont.clear = clear;
        mBox.clear = clear;

        mBox.box.bevel = Color(0,0,1);

        //xxx we don't have any cache managment, and the cache fills up QUITE
        //    fast (rapidly gets to 1 GB RAM usage when scrollbaring around)
        //=> better clear everything
        gFramework.releaseCaches(false);
    }

    void onBevelClick(CheckBox sender) {
        mBox.box.drawBevel = sender.checked();
    }

    void onNotRoundedClick(CheckBox sender) {
        mBox.box.noRoundedCorners = sender.checked();
    }

    this() {
        mFont = new FontTest();
        mBox = new BoxTest();

        auto gui = new BoxContainer(false, false, 3);
        auto cnt = new BoxContainer(true);
        cnt.add(mFont);
        cnt.add(mBox);
        gui.add(cnt);

        auto scr = new TableContainer(2, 0, Vector2i(15, 1));
        char[][] labels = ["foreground alpha", "background alpha",
            "container red", "corner size", "border size", "shadow offset"];
        int[] values = [128, 128, 128, 5, 5, 0];
        int[] maxvals = [255, 255, 255, 50, 50, 10];

        for (int n = 0; n < mBars.length; n++) {
            scr.addRow();

            auto la = new Label();
            la.text = labels[n];
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
        //sp.color = Color(0);
        gui.add(sp, WidgetLayout.Expand(true));

        gui.add(scr, WidgetLayout.Expand(true));

        mBevel = new CheckBox();
        mBevel.onClick = &onBevelClick;
        mBevel.text = "Bevel";
        gui.add(mBevel, WidgetLayout.Expand(true));

        mNotRounded = new CheckBox();
        mNotRounded.onClick = &onNotRoundedClick;
        mNotRounded.text = "No rounded corners";
        gui.add(mNotRounded, WidgetLayout.Expand(true));

        onScrollbar(null); //update

        gWindowFrame.createWindow(gui, "Alpha test", Vector2i(450, 300));
    }

    static this() {
        registerTaskClass!(typeof(this))("alphatest");
    }
}

class TestTask3 {
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
        mValues.text = myformat("size={}, took={}, b={}, c={}, g={}, a={}",
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
            loadFile(mFList.contents[index]);
        }
    }

    void loadFile(char[] fn) {
        if (fn != "") {
            Surface img;
            try {
                img = loadImage(fn);
            } catch (CustomException e) {
                mValues.text = "couldn't load, " ~ e.toString;
            }
            mView.setSource(img);
        }
    }

    this() {
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
            la.text = labels[n];
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
        //sp.color = Color(0);
        gui.add(sp, WidgetLayout.Expand(true));

        gui.add(scr, WidgetLayout.Expand(true));

        mValues = new Label();
        gui.add(mValues, WidgetLayout.Aligned(-1, 0));

        char[][] files;
        gFS.listdir("/", "*", false,
            (char[] path) {
                files ~= path;
                return true;
            }
        );
        mFList.setContents(files);

        loadFile(filename);

        gWindowFrame.createWindow(tgui, "BCG test", Vector2i(450, 300));
    }

    static this() {
        registerTaskClass!(typeof(this))("bcg");
    }
}

//write GUI events into a log window
class TestTask4 {
    template ReportEvents() {
        Output log;

        this() {
            focusable = true;
        }

        override bool greedyFocus() {
            return true;
        }

        override void onMouseMove(MouseInfo m) {
            log.writefln("{}: {}", this, m);
        }

        override bool onKeyDown(KeyInfo info) {
            log.writefln("{}: {}", this, info.toString());
            if (info.isDown && info.code == Keycode.MOUSE_RIGHT)
                gFramework.mouseLocked = !gFramework.mouseLocked;
            return true;
        }
        override void onKeyUp(KeyInfo info) {
            log.writefln("{}: {}", this, info.toString());
        }

        override void onMouseEnterLeave(bool mouseIsInside) {
            log.writefln("{}: onMouseEnterLeave({})", this, mouseIsInside);
        }

        override Vector2i layoutSizeRequest() {
            log.writefln("{}: layoutSizeRequest()", this);
            return Vector2i(0);
        }

        override void layoutSizeAllocation() {
            log.writefln("{}: layoutSizeAllocation(), size={}", this, size());
        }

        override void onFocusChange() {
            log.writefln("{}: focus change: global={} focus={}", this,
                gui?gui.focused():null, focused());
            super.onFocusChange();
        }

        override void onDraw(Canvas c) {
            c.drawFilledCircle(mousePos(), 5, Color(1,0,0));
        }
    }

    class W1 : Widget {
        mixin ReportEvents;
        char[] toString() {
            return "W1";
        }
    }

    private void mouseLock(CheckBox sender) {
        gFramework.mouseLocked = sender.checked();
    }

    this() {
        auto log = new LogWindow(gFontManager.loadFont("normal"));

        auto x = new W1();
        x.log = log;
        auto t = gWindowFrame.createWindow(x, "huh", Vector2i(400, 200));

        auto wnd = gWindowFrame.createWindow(log, "log",
            Vector2i(400, 175));
    }
    static this() {
        registerTaskClass!(typeof(this))("events");
    }
}

//silly off-by-one test
//should show 2 rectangles:
//1st rectangle: a filled red rect rectangle, and on each of the 4 corners, a
//   black dot; the dot must be outside the rectangle by 1 pixel (if the
//   rectangle had a one pixel-wide border, the dots would be the corners of the
//   unfilled rectangle which forms that border)
//2nd rectangle: same as above, but the rectangle is unfilled
//   inside the unfilled rect, there's a filled yellow rectangle with a 1 pixel
//   thick black border (but see how that's actually drawn)
//   there should be a 1 pixel undrawn (= white) space between the red and the
//   black lines
//error on my machine, when the hack in fwgl.d is disabled: filled rectangles
//   look like 1 was added to all y coordinates
class OffByOneTest {
    class W : Widget {
        Surface bmp;
        this() {
            //black pixel
            bmp = new Surface(Vector2i(1));
            bmp.fill(bmp.rect(), Color(0,0,0));
        }
        override void onDraw(Canvas c) {
            auto rc = widgetBounds();
            auto rc1 = rc;
            rc1.p2.x /= 2;
            rc1.extendBorder(Vector2i(-20));
            //4 points drawn such that they only touch with the interrior of rc
            //the right/bottom line of rc is not a part of rc anymore
            void drawPts(Rect2i rc) {
                c.draw(bmp, rc.p1 - bmp.size);
                c.draw(bmp, rc.p2);
                c.draw(bmp, rc.pA() - Vector2i(0, bmp.size.y));
                c.draw(bmp, rc.pB() - Vector2i(bmp.size.x, 0));
            }
            drawPts(rc1);
            c.drawFilledRect(rc1, Color(1,0,0));
            auto rc2 = rc;
            rc2.p2.x /= 2;
            rc2 += Vector2i(rc2.p2.x, 0);
            rc2.extendBorder(Vector2i(-20));
            drawPts(rc2);
            c.drawRect(rc2, Color(1,0,0));
            rc2.extendBorder(Vector2i(-2));
            //check for correct tiling...
            c.drawTiled(bmp, rc2.p1, rc2.size());
            rc2.extendBorder(Vector2i(-1));
            c.drawFilledRect(rc2, Color(1,1,0));
        }
    }

    this() {
        gWindowFrame.createWindow(new W(), "off-by-one", Vector2i(400, 200));
    }
    static this() {
        registerTaskClass!(typeof(this))("offbyone");
    }
}

class TextColorTest {
    FormattedText mText;

    class W : Widget {
        this() {
            setVirtualFrame();
        }
        override void layoutSizeAllocation() {
            mText.setArea(size, -1, -1);
        }
        override void onDraw(Canvas c) {
            c.drawRect(Rect2i(Vector2i(0), this.outer.mText.textSize() +
                Vector2i(2)), Color(1,0,0));
            mText.draw(c, Vector2i(1));
        }
    }

    private void editChange(EditLine sender) {
        mText.setMarkup(sender.text);
    }

    private void wrapChange(CheckBox sender) {
        mText.shrink = sender.checked ? ShrinkMode.wrap : ShrinkMode.shrink;
    }

    this() {
        mText = new FormattedText();
        mText.shrink = ShrinkMode.shrink;

        auto box = new BoxContainer(false);
        auto e = new EditLine();
        e.onChange = &editChange;
        mText.setImage(0, gGuiResources.get!(Surface)("window_maximize"));
        e.text = r"hi\c(a=0.5)half alpha \r\[\bbold\] \t(gui.cancel)\n\s(800 %)\blink\c(red)\border-color(blue)\shadow-color(grey,a=0.5)\shadow-offset(-90%)\border-width(10)LOL\imgref(0)\r\s(-10 %)\imgres(checkbox_on)oh god wtf\s(1300 %)X";
        editChange(e);
        box.add(e, WidgetLayout.Expand(true));
        auto wrap = new CheckBox();
        wrap.text = "wrap line";
        wrap.onClick = &wrapChange;
        box.add(wrap, WidgetLayout.Expand(true));
        box.add(new W());

        gWindowFrame.createWindow(box, "Colored text",
            Vector2i(600, 900));
    }
    static this() {
        registerTaskClass!(typeof(this))("colortext");
    }
}

class MultiLineTest {
    MultilineEdit mEdit;

    this() {
        mEdit = new typeof(mEdit)();

        gWindowFrame.createWindow(mEdit, "multine edit",
            Vector2i(300, 200));
    }
    static this() {
        registerTaskClass!(typeof(this))("multilinetest");
    }
}

class PixelTest {

    class W : Widget {
        int x;

        this() {
        }
        override bool onKeyDown(KeyInfo inf) {
            if (inf.code == Keycode.MOUSE_LEFT)
                x++;
            else if (inf.code == Keycode.MOUSE_RIGHT)
                x--;
            else
                return false;
            return true;
        }
        override void onDraw(Canvas canvas) {
            const m = 5;
            int f = ((x % m) + m) % m;
            auto c = Color(!!(f==0),!!(f==1),!!(f==2));
            if (f == 3)
                c = Color(0);
            else if (f == 4)
                c = Color(1);
            canvas.clear(c);
        }
    }

    this() {
        gWindowFrame.createWindowFullscreen(new W(), "meh");
    }
    static this() {
        registerTaskClass!(typeof(this))("pixeltest");
    }
}

class FoobarTest {
    private Label mLabel;
    private Foobar mFoo;
    private ScrollBar mBar1, mBar2;

    private void onScroll(ScrollBar sender) {
        float p = cast(float)mBar1.curValue/mBar1.maxValue;
        mLabel.text = myformat("{}/{}", p, mBar2.curValue);
        mFoo.percent = p;
        mFoo.minSize = Vector2i(mBar2.curValue, 0);
    }

    this() {
        auto box = new BoxContainer(false, false, 10);

        mLabel = new Label();
        box.add(mLabel);

        mBar1 = new ScrollBar(true);
        mBar1.maxValue = 100;
        mBar1.largeChange = 10;
        mBar1.onValueChange = &onScroll;
        box.add(mBar1);

        mBar2 = new ScrollBar(true);
        mBar2.maxValue = 200;
        mBar2.largeChange = 10;
        mBar2.onValueChange = &onScroll;
        box.add(mBar2);

        mFoo = new Foobar();
        mFoo.fill = Color(1, 0.5, 0);
        mFoo.border.border = Color(0.7);
        mFoo.border.back = Color(0);
        mFoo.border.cornerRadius = 3;
        WidgetLayout lay; //expand in y, but left-align in x
        lay.alignment[0] = 0;
        lay.expand[0] = false;
        box.add(mFoo, lay);

        onScroll(mBar1);

        gWindowFrame.createWindow(box, "Foobar", Vector2i(200, 150));
    }
    static this() {
        registerTaskClass!(typeof(this))("foobartest");
    }
}

class CanvasTest {
    private {
        ScrollBar mRot, mZoom;
        const cZoomScale = 100;
        CheckBox mMirrY;
        Surface mImg;
        SubSurface mImgSub;
        Vector2i mCenter;
        BitmapEffect eff;
    }

    class Draw : Widget {
        this() {
        }

        Vector2i at() {
            return size/2;
        }

        override void onDraw(Canvas c) {
            eff.mirrorY = mMirrY.checked();
            eff.rotate = mRot.curValue/180.0*3.14159;
            eff.scale = Vector2f(mZoom.curValue*1.0/cZoomScale);
            eff.center = mCenter;
            c.drawSprite(mImgSub, at, &eff);
            c.drawFilledCircle(at, 10, Color(0));
            auto x = toVector2i(
                toVector2f(mCenter).rotated(eff.rotate) ^ eff.scale);
            c.drawFilledCircle(at-x, 3, Color(1,0,0));
        }

        override bool onKeyDown(KeyInfo inf) {
            if (inf.code != Keycode.MOUSE_LEFT)
                return false;
            auto r = toVector2f(mousePos - at);
            r = r.rotated(-eff.rotate) / eff.scale;
            mCenter = toVector2i(r) + eff.center;
            return true;
        }
    }

    this() {
        auto box = new BoxContainer(false, false, 10);

        mRot = new ScrollBar(true);
        mRot.maxValue = 360;
        mRot.largeChange = 10;
        mRot.setLayout(WidgetLayout.Expand(true));
        box.add(mRot);

        mZoom = new ScrollBar(true);
        mZoom.maxValue = 10*cZoomScale;
        mZoom.curValue = cZoomScale;
        mZoom.setLayout(WidgetLayout.Expand(true));
        box.add(mZoom);

        mMirrY = new CheckBox();
        mMirrY.text = "Mirror Y";
        mMirrY.setLayout(WidgetLayout.Expand(true));
        box.add(mMirrY);

        Draw d = new Draw();
        box.add(d);

        mImg = loadImage("level/gpl/objects/keller.png");
        mImgSub = mImg.createSubSurface(mImg.rect);

        gWindowFrame.createWindow(box, "drawtest", Vector2i(500, 500));
    }

    static this() {
        registerTaskClass!(typeof(this))("drawtest");
    }
}

//Ehrm, lol...
//Tiny function plotter to visualize interpolation functions

import utils.interpolate;

//Interpolation function parameter is compile-time
const cFuncCount = 200;
float function(float)[cFuncCount] gFuncsExp;
float function(float)[cFuncCount] gFuncsExp2;
static float getP(int i) {
    return (i - cast(float)cFuncCount/2)/12.0;
}
void setF(alias A, alias F, int idx = cFuncCount - 1)() {
    static if (idx >= 0) {
        A[idx] = &F!(getP(idx));
        setF!(A, F, idx-1)();
    }
}

static this() {
    setF!(gFuncsExp, interpExponential)();
    setF!(gFuncsExp2, interpExponential2)();
}

class InterpTest {
    ScrollBar bar;
    Label mLabel;
    int mIdx;

    class W : Widget {
        this() {
        }
        override void onDraw(Canvas c) {
            plot(c, gColors["red"], gFuncsExp2[mIdx]);
            plot(c, gColors["green"], gFuncsExp[mIdx]);
            plot(c, gColors["yellow"], &interpLinear);
        }

        private void plot(Canvas c, Color col, float function(float) func) {
            Vector2i last = Vector2i(int.max);
            for (int x = 0; x < size.x; x++) {
                float xv = cast(float)x / (size.x-1);
                float yv = func(xv);
                int y = (size.y-1) - cast(int)(yv*(size.y-1));
                auto p = Vector2i(x, y);
                if (last.x != int.max)
                    c.drawLine(last, p, col, 1);
                last = p;
            }
        }
    }

    this() {
        auto box = new BoxContainer(false, false, 1);

        mLabel = new Label();
        box.add(mLabel, WidgetLayout.Expand(true));

        bar = new ScrollBar(true);
        bar.maxValue = cFuncCount - 1;
        bar.largeChange = 10;
        bar.onValueChange = &onScroll;
        box.add(bar, WidgetLayout.Expand(true));
        box.add(new W());
        onScroll(bar);

        gWindowFrame.createWindow(box,
            "Interpolate [0, 1]; r = Exp2, g = Exp, y = Linear",
            Vector2i(500, 550));
    }

    private void onScroll(ScrollBar sender) {
        mIdx = sender.curValue();
        mLabel.text = myformat("A = {}", getP(sender.curValue()));
    }

    static this() {
        registerTaskClass!(typeof(this))("interpolate");
    }
}
