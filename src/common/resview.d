//trivial resource viewer (see framework) to ease debugging
module common.resview;

import common.allres;
import common.resources;
import common.resset;
import common.task;
import framework.font;
import framework.drawing;
import framework.event;
import framework.sound;
import framework.surface;
import framework.main;
import utils.timesource;
import gui.boxcontainer;
import gui.button;
import gui.container;
import gui.label;
import gui.list;
import gui.scrollbar;
import gui.scrollwindow;
import gui.splitter;
import gui.tablecontainer;
import gui.widget;
import gui.window;

import utils.factory;
import utils.math;
import utils.misc;
import utils.time;
import utils.vector2;

import std.math;
import str = utils.string;

import game.animation;
import game.particles;

import algorithm = std.algorithm;

alias StaticFactory!("ResViewers", ResViewHandlerGeneric, Object)
    ResViewHandlers;

class ResViewHandlerGeneric {
    private {
        Object mResource;
        Widget mGUI;
    }

    Object resource() {
        return mResource;
    }

    this(Object r) {
        mResource = r;
    }

    final protected void setGUI(Widget gui) {
        if (mGUI)
            mGUI.remove();
        mGUI = gui;
    }

    //guaranteed to return non-null
    final Widget getGUI() {
        return mGUI ? mGUI : new Spacer();
    }
}

class ResViewHandler(T : Object) : ResViewHandlerGeneric {
    alias T Type;
    private {
        T mResource;
    }

    this(Object r) {
        super(r);
        //lol cast it
        mResource = castStrict!(T)(r);
    }

    final override T resource() {
        return mResource;
    }

    static void registerHandler(T1 : ResViewHandler)() {
        ResViewHandlers.register!(T1)(T.classinfo.name);
    }
}

class BitmapHandler : ResViewHandler!(Surface) {
    this(Object r) {
        super(r);
        setGUI(new Viewer());
    }

    class Viewer : Widget {
        override void onDraw(Canvas c) {
            Vector2i d = size/2 - resource.size/2;
            c.draw(resource, d);
            c.drawRect(Rect2i(d-Vector2i(1), d+resource.size+Vector2i(1)),
                Color(0, 0, 0));
        }

        override Vector2i layoutSizeRequest() {
            return resource.size()+Vector2i(2); //with frame hurhur
        }
    }

    static this() {
        registerHandler!(typeof(this));
    }
}

class ParticleHandler : ResViewHandler!(ParticleType) {
    this(Object r) {
        super(r);
        setGUI(new Drawer());
    }

    class Drawer : Widget {
        ParticleWorld world;

        this() {
            world = new ParticleWorld();
            world.waterLine = 200;
        }

        override bool onKeyDown(KeyInfo info) {
            if (!info.isMouseButton)
                return false;
            world.emitParticle(toVector2f(mousePos()), Vector2f(0), resource);
            return true;
        }

        override void onDraw(Canvas c) {
            world.draw(c);
            c.drawLine(Vector2i(0, world.waterLine),
                Vector2i(size.x, world.waterLine), Color(0,0,1));
        }
    }

    static this() {
        registerHandler!(typeof(this));
    }
}

class SampleHandler : ResViewHandler!(Sample) {
    this(Object r) {
        super(r);
        setGUI(new Viewer());
    }

    Source ch;
    SoundSourceInfo pos;

    string state() {
        final switch (ch.state) {
            case PlaybackState.stopped: return "stopped";
            case PlaybackState.stopping: return "stopping";
            case PlaybackState.playing: return "playing";
            case PlaybackState.paused: return "paused";
        }
    }

    class Viewer : SimpleContainer {
        Label lblstate;
        this() {
            ch = gSoundManager.createSource();
            ch.sample = resource;
            auto al = WidgetLayout.Aligned(-1, 0);
            auto box = new BoxContainer(false, false, 5);
            lblstate = new Label();
            box.add(lblstate, al);
            auto btnBox = new BoxContainer(true, false, 2);
            Button button(string c, void delegate(Button) cb, bool bx = false) {
                auto b = new Button();
                b.text = c;
                b.onClick = cb;
                if (bx)
                    box.add(b, al);
                else
                    btnBox.add(b, al);
                return b;
            }
            auto chk = new CheckBox();
            chk.text = "loop?";
            chk.onClick = &onLoop;
            box.add(chk, al);
            button("play", &onPlay);
            button("pause", &onPause);
            button("stop", &onStop);
            button("fade", &onFade);
            box.add(btnBox, al);
            box.add(new Position());
            addChild(box);
        }
        void onLoop(CheckBox b) {
            ch.looping = b.checked();
        }
        void onPlay(Button b) {
            ch.play();
        }
        void onStop(Button b) {
            ch.stop();
        }
        void onPause(Button s) {
            ch.paused = true;
        }
        void onFade(Button s) {
            ch.stop(timeSecs(2));
        }
        override void simulate() {
            ch.info = pos;
            lblstate.text = state()
                ~ (gSoundManager.available() ? " a " : " n ")
                ~ ch.position().toString ~ "/" ~ resource.length.toString;
        }
    }

    class Position : Widget {
        Font f;
        string msg;
        Rect2i box;
        override void onMouseMove(MouseInfo mi) {
            auto sz = widgetBounds().size();
            auto center = sz/2;
            int len = min(sz.x, sz.y)/2 - 10; //border=10
            box.p1 = center-Vector2i(len);
            box.p2 = center+Vector2i(len);
            auto p = mousePos() - center;
            pos.position = (toVector2f(p)/len);
            msg = myformat("%s -> %s", mousePos(), pos.position);
        }
        override void onDraw(Canvas c) {
            if (!f)
                f = gFontManager.loadFont("normal");
            c.drawRect(box, Color(0,0,0));
            c.drawCircle(mousePos(), 5, Color(1,0,0));
            f.drawText(c, Vector2i(0), msg);
            if (resource.length > Time.Null) {
                //testing of cooldown rect code
                c.drawPercentRect(box.p1, box.p2, ch.position().secsf /
                    resource.length.secsf, Color(0.3, 0.3, 0.3, 0.5));
            }
        }
        override bool onKeyDown(KeyInfo infos) {
            if (!infos.isMouseButton)
                return false;
            ch.play(resource.length/4, timeMsecs(300));
            return true;
        }
    }

    static this() {
        registerHandler!(typeof(this));
    }
}

class ViewAniFrames : Container {
    private {
        DebugAniFrames frames;
    }

    this(Animation ani) {
        frames = cast(DebugAniFrames)ani;
        if (!frames)
            return;

        auto gui = new BoxContainer(false);

        string inf;

        inf ~= "Param mappings:\n";
        foreach (i; frames.paramInfos()) {
            inf ~= i ~ "\n";
        }

        Label inftxt = new Label();
        inftxt.textMarkup = inf;
        inftxt.setLayout(WidgetLayout.Aligned(-1,-1));
        gui.add(inftxt);

        int[] pcounts = frames.paramCounts();

        for (int idx_c = 0; idx_c < pcounts[2]; idx_c++) {
            if (idx_c > 0) {
                auto spacer = new Spacer();
                spacer.minSize = Vector2i(2,3);
                //spacer.color = Color(1,0,0);
                WidgetLayout lay;
                lay.expand[] = [true, false];
                spacer.setLayout(lay);
                gui.add(spacer);
            }

            auto table = new TableContainer(pcounts[0], pcounts[1],
                Vector2i(2,2), [true, true]);
            Rect2i bb = frames.frameBoundingBox();
            for (int x = 0 ; x < table.width; x++) {
                for (int y = 0; y < table.height; y++) {
                    auto bmp = new ViewBitmap();
                    bmp.p1 = x;
                    bmp.p2 = y;
                    bmp.p3 = idx_c;
                    bmp.offs = -bb.p1;
                    bmp.size = bb.size;
                    bmp.setLayout(WidgetLayout.Noexpand());
                    table.add(bmp, x, y);
                }
            }
            table.setLayout(WidgetLayout.Aligned(0,0));
            gui.add(table);
        }

        addChild(gui);
    }

    class ViewBitmap : Widget {
        int p1, p2, p3;
        Vector2i offs, size;

        override void onDraw(Canvas c) {
            frames.drawFrame(c, offs, p1, p2, p3);
            c.drawRect(Rect2i(Vector2i(), size-Vector2i(1)), Color(1,1,0));
        }

        override Vector2i layoutSizeRequest() {
            return size;
        }
    }
}

class AnimationHandler : ResViewHandler!(Animation) {
    private {
        TimeSource mTime;
        Animator mAnim;
        ScrollBar[3] mParams;
        Label[3] mParLbl;
        ScrollBar mFrame;
        Label mFrameLabel;
        ScrollBar mSpeed;
        Label mSpeedLabel;
        CheckBox mPaused;
        Button mShowFrames;
        BoxContainer mGuiBox;
    }

    this(Object r) {
        super(r);

        mTime = new TimeSource("resview");

        auto table = new TableContainer(2, 0, Vector2i(10,1), [true, false]);

        auto infos = new Label();
        infos.text = "Flags: "
            ~ (resource.repeat ? "repeat, " : " ")
            ~ myformat("frametime: %s ", resource.frameTime)
            ~ myformat("duration: %s", resource.duration);
        table.addRow();
        table.add(infos, 0, table.height-1, 2, 1);

        void addscr(out ScrollBar scr, out Label lbl) {
            lbl = new Label();
            scr = new ScrollBar(true);
            scr.onValueChange = &onScrollbar;
            table.addRow();
            table.add(lbl, 0, table.height-1);
            table.add(scr, 1, table.height-1);
        }

        void addp(int n) {
            ScrollBar scr;
            Label lbl;
            addscr(scr, lbl);
            scr.minValue = -90;
            scr.maxValue = 600;
            mParams[n] = scr;
            mParLbl[n] = lbl;
        }

        addp(0);
        addp(1);
        addp(2);

        auto box = new BoxContainer(false, false, 10);
        table.setLayout(WidgetLayout.Expand(true));
        box.add(table);
        box.add(new Viewer());

        mAnim = new Animator(mTime);

        addscr(mFrame, mFrameLabel);
        mFrame.minValue = 0;
        mFrame.maxValue = resource.frameCount-1;
        //mFrame.onValueChange = &onSetFrame;

        addscr(mSpeed, mSpeedLabel);
        mSpeed.minValue = 0;
        mSpeed.maxValue = 100;
        mSpeed.curValue = mSpeed.maxValue/2;

        table.addRow();
        mPaused = new CheckBox();
        //mPaused.font = gFramework.getFont("normal");
        mPaused.text = "paused";
        mPaused.onClick = &onPause;
        table.add(mPaused, 0, table.height-1, 2, 1);

        mShowFrames = new Button();
        mShowFrames.text = "show ani frames";
        mShowFrames.onClick = &onShowFrames;
        table.add(mShowFrames, 0, table.height-1, 2, 1);

        //update label texts
        onScrollbar(null);

        mGuiBox = box;
        setGUI(mGuiBox);

        resetAnim();
    }

    private void onScrollbar(ScrollBar sender) {
        AnimationParams p;
        p.p[0] = mParams[0].curValue;
        p.p[1] = mParams[1].curValue;
        p.p[2] = mParams[2].curValue;
        mAnim.params = p;
        foreach (int idx, Label l; mParLbl)
            l.text = myformat("Param %s: %s", idx, mParams[idx].curValue);
        mFrameLabel.text = myformat("Frame: %s/%s", mFrame.curValue,
            mFrame.maxValue);
        float speed = 2.0f*mSpeed.curValue/mSpeed.maxValue;
        mTime.slowDown = speed;
        mSpeedLabel.text = myformat("Speed: %s", mTime.slowDown);
    }

    private void onPause(CheckBox sender) {
        mTime.paused = mPaused.checked;
    }

    private void onShowFrames(Button sender) {
        mGuiBox.clear();
        mGuiBox.add(new ViewAniFrames(resource()));
    }

    private int p1() {
        return mParams[0].curValue;
    }
    private void p1(int v) {
        mParams[0].curValue = v;
        onScrollbar(null);
    }
    private int p2() {
        if (p1 > 90 && p1 < 270)
            return 180+mParams[1].curValue;
        else
            return -mParams[1].curValue;
    }
    private void p2(int v) {
        bool left = false;
        //convert [0, 360] to [-90, 90]
        if (v <= 90)
            v = -v;
        else if (v < 270) {
            //left side, p1 will be changed accordingly
            v = v - 180;
            left = true;
        } else
            v = 360 - v;
        //modify p1 so animation is facing the right way
        if ((!left && p1 > 90 && p1 < 270) || (left && (p1 < 90 || p1 > 270)))
            p1 = realmod(180 - p1, 360);
        mParams[1].curValue = v;
        onScrollbar(null);
    }

    private void resetAnim() {
        mAnim.setAnimation(resource);
    }

    class Viewer : Widget {
        enum radius = 50;
        bool md;
        override void onDraw(Canvas c) {
            auto bnds = mAnim.bounds;
            Vector2i d = size/2;
            mAnim.pos = d;
            mAnim.draw(c);
            c.drawRect(Rect2i(bnds.p1-Vector2i(1), bnds.p2+Vector2i(1)),
                Color(0, 0, 0));
            //assume p1() in degrees (0..360)
            auto dir = Vector2f.fromPolar(radius, p1()/360.0f*PI*2);
            c.drawCircle(size/2+toVector2i(dir), 5, Color(1,0,0));
            dir = Vector2f.fromPolar(radius, p2()/360.0f*PI*2);
            c.drawCircle(size/2+toVector2i(dir), 5, Color(0,1,0));
        }

        override void simulate() {
            mTime.update();
            mFrame.curValue = mAnim.curFrame;
        }

        override void onMouseMove(MouseInfo inf) {
            auto angle = toVector2f(inf.pos-size/2).normal.toAngle;
            //(not if NaN)
            if (angle == angle) {
                int aint = realmod(cast(int)(angle/PI/2*360), 360);
                if (gFramework.getKeyState(Keycode.MOUSE_RIGHT))
                    p2 = aint;
                else
                    p1 = aint;
            }
        }

        override bool onKeyDown(KeyInfo infos) {
            if (!infos.isMouseButton)
                return false;
            resetAnim();
            return true;
        }

        override Vector2i layoutSizeRequest() {
            return mAnim.bounds.size()+Vector2i(2);
        }
    }

    static this() {
        registerHandler!(typeof(this));
    }
}

class ResViewerTask {
    this() {
        this(ResourceSet.init);
    }

    this(ResourceSet resources) {
        gWindowFrame.createWindow(new Viewer(resources), "Res Viewer",
            Vector2i(750, 500));
    }

    class Viewer : Container {
        StringListWidget mList;
        StringListWidget mResTypeList;
        Button mUpdate;
        SimpleContainer mClient;
        ResourceSet mSourceSet; //might be null (use global resources then)
        ResEntry[] mResources;
        ClassInfo[] mResTypes;
        ClassInfo mCurRes;
        ClassInfo mShowNothing;
        Label mName;

        struct ResEntry {
            string name;
            Object res;

            int opCmp(in ResEntry other) const {
                return str.cmp(name, other.name);
            }
        }

        this(ResourceSet resset) {
            //some random non-null ClassInfo, that a resource isn't derived of
            mShowNothing = cast(ClassInfo)this.classinfo;

            mSourceSet = resset;

            auto side = new BoxContainer(false);

            mList = new StringListWidget();
            mList.onSelect = &onSelect;
            auto listwind = new ScrollWindow(mList, [false, true]);
            listwind.minSize = Vector2i(275, 0);
            listwind.enableMouseWheel = true;
            side.add(listwind);

            auto noexp = WidgetLayout.Expand(true);

            auto spacer = new Spacer();
            spacer.minSize = Vector2i(0, 2);
            spacer.visible = false;
            spacer.setLayout(noexp);
            side.add(spacer);

            mResTypeList = new StringListWidget();
            mResTypeList.onSelect = &onSelectType;
            mResTypeList.setLayout(noexp);
            side.add(mResTypeList);

            mUpdate = new Button();
            mUpdate.text = "Update List";
            mUpdate.onClick = &onUpdate;
            mUpdate.setLayout(WidgetLayout.Noexpand());
            side.add(mUpdate);

            auto otherside = new BoxContainer(false, false, 5);
            auto props = new TableContainer();
            props.setLayout(WidgetLayout.Expand(true));
            otherside.add(props);
            mClient = new SimpleContainer();
            auto scroller = new ScrollWindow(mClient);
            otherside.add(scroller);

            props.addColumn();
            props.addColumn();
            props.cellSpacing = Vector2i(7, 1);
            void addLabel(out Label val, string name) {
                props.addRow();
                auto lbl = new Label();
                lbl.text = name ~ ":";
                lbl.setLayout(WidgetLayout.Aligned(-1, 0));
                val = new Label();
                props.add(lbl, 0, props.height-1);
                props.add(val, 1, props.height-1);
            }
            addLabel(mName, "Name");

            auto all = new HSplitter();
            //side.setLayout(WidgetLayout.Expand(false));
            all.setChild(0, side);
            all.setChild(1, otherside);
            addChild(all);

            doUpdate2();
        }

        //check if sub is equal to or is below c
        static bool isSub(const(ClassInfo) sub_, const(ClassInfo) c) {
            ClassInfo sub = cast(ClassInfo)sub_;
            while (sub) {
                if (sub is c)
                    return true;
                sub = sub.base;
            }
            return false;
        }

        void doUpdate() {
            doSelect(null, null);
            string[] list;
            mResources = null;
            void add(string name, Object res) {
                bool ok;
                if (mCurRes) {
                    ok = isSub(res.classinfo, mCurRes);
                } else {
                    ok = true;
                    foreach (c; mResTypes) {
                        if (c && isSub(res.classinfo, c))
                            ok = false;
                    }
                }
                if (ok) {
                    mResources ~= ResEntry(name, res);
                }
            }
            if (mSourceSet) {
                foreach (r; mSourceSet.resourceList) {
                    add(r.name, r.resource());
                }
            } else {
                gResources.enumResources(
                    (string fullname, ResourceItem res) {
                        assert(fullname == res.fullname);
                        add(fullname, res.get);
                    }
                );
            }
            algorithm.sort(mResources);
            foreach (s; mResources) {
                list ~= s.name;
            }
            mList.setContents(list);
        }

        void doUpdate2() {
            string[] list = null;
            mResTypes = null;
            foreach (name; ResViewHandlers.classes) {
                auto cinf = cast(ClassInfo)ClassInfo.find(name);
                if (cinf) {
                    mResTypes ~= cinf;
                    auto s = cinf.name;
                    //split to first point
                    auto t = str.rfind(s, '.');
                    if (t >= 0)
                        s = s[t+1..$];
                    list ~= s;
                }
            }
            list ~= "<unknown>";
            //ClassInfo.init doesn't work because Walter is stupid
            ClassInfo i;
            mResTypes ~= i;
            mResTypeList.setContents(list);
            mCurRes = mShowNothing;
            doUpdate();
        }

        private void onUpdate(Button sender) {
            doUpdate2();
        }

        private void onSelectType(sizediff_t index) {
            mCurRes = mShowNothing;
            if (index >= 0)
                mCurRes = mResTypes[index];
            doUpdate();
        }

        private void doSelect(ResEntry* s, const(ClassInfo) type) {
            mName.text = s ? s.name : "-";
            mClient.clear();
            if (s && type) {
                string name = type.name;
                Widget widget;
                if (ResViewHandlers.exists(name)) {
                    widget = ResViewHandlers.instantiate(name, s.res).getGUI();
                } else {
                    widget = new Spacer(); //error lol
                }
                mClient.add(widget);
            }
        }

        private void onSelect(sizediff_t index) {
            doSelect(index < 0 ? null : &mResources[index], mCurRes);
        }
    }

    static this() {
        registerTaskClass!(typeof(this))("resviewer");
    }
}
