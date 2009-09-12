//trivial resource viewer (see framework) to ease debugging
module common.resview;

import common.common;
import common.task;

import framework.font;
import framework.framework;
import common.resources;
import common.resset;
import common.allres;
import framework.timesource;
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
import gui.wm;

import utils.factory;
import utils.math;
import utils.misc;
import utils.time;
import utils.vector2;

import tango.math.Math : PI;
import str = utils.string;

import game.animation;

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
            c.drawRect(d-Vector2i(1), d+resource.size+Vector2i(1),
                Color(0, 0, 0));
        }

        Vector2i layoutSizeRequest() {
            return resource.size()+Vector2i(2); //with frame hurhur
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

    char[] state() {
        switch (ch.state) {
            case PlaybackState.stopped: return "stopped";
            case PlaybackState.stopping: return "stopping";
            case PlaybackState.playing: return "playing";
            case PlaybackState.paused: return "paused";
        }
    }

    class Viewer : SimpleContainer {
        Label lblstate;
        this() {
            ch = gFramework.sound.createSource();
            ch.sample = resource;
            auto al = WidgetLayout.Aligned(-1, 0);
            auto box = new BoxContainer(false, false, 5);
            lblstate = new Label();
            box.add(lblstate, al);
            auto btnBox = new BoxContainer(true, false, 2);
            Button button(char[] c, void delegate(Button) cb, bool bx = false) {
                auto b = new Button();
                b.text = c;
                b.onClick = cb;
                if (bx)
                    box.add(b, al);
                else
                    btnBox.add(b, al);
                return b;
            }
            auto chk = button("loop?", &onLoop, true);
            chk.isCheckbox = true;
            button("play", &onPlay);
            button("pause", &onPause);
            button("stop", &onStop);
            button("fade", &onFade);
            box.add(btnBox, al);
            box.add(new Position());
            addChild(box);
        }
        void onLoop(Button b) {
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
                ~ (gFramework.sound.available() ? " a " : " n ")
                ~ ch.position().toString ~ "/" ~ resource.length.toString;
        }
    }

    class Position : Widget {
        Font f;
        char[] msg;
        Rect2i box;
        override void onMouseMove(MouseInfo mi) {
            auto sz = widgetBounds().size();
            auto center = sz/2;
            int len = min(sz.x, sz.y)/2 - 10; //border=10
            box.p1 = center-Vector2i(len);
            box.p2 = center+Vector2i(len);
            auto p = mousePos() - center;
            pos.position = (toVector2f(p)/len);
            msg = myformat("{} -> {}", mousePos(), pos.position);
        }
        override void onDraw(Canvas c) {
            if (!f)
                f = gFramework.getFont("normal");
            c.drawRect(box, Color(0,0,0));
            c.drawCircle(mousePos(), 5, Color(1,0,0));
            f.drawText(c, Vector2i(0), msg);
            if (resource.length > Time.Null) {
                //testing of cooldown rect code
                c.drawPercentRect(box.p1, box.p2, ch.position().secsf /
                    resource.length.secsf, Color(0.3, 0.3, 0.3, 0.5));
            }
        }
        override void onKeyEvent(KeyInfo infos) {
            if (infos.isMouseButton && infos.isDown) {
                ch.play(resource.length/4, timeMsecs(300));
            }
        }
    }

    static this() {
        registerHandler!(typeof(this));
    }
}

class AtlasHandler : ResViewHandler!(Atlas) {
    private {
        Widget mViewer;
        ScrollBar mSel;
        TextureRef mCur;
    }

    this(Object r) {
        super(r);

        auto box = new BoxContainer(false);
        mSel = new ScrollBar(true);
        mSel.onValueChange = &sel;
        mSel.maxValue = resource.count-1;
        mSel.setLayout(WidgetLayout.Expand(true));
        box.add(mSel);
        mCur = resource.texture(0);
        mViewer = new Viewer();
        box.add(mViewer);
        setGUI(box);
    }

    private void sel(ScrollBar sender) {
        mCur = resource.texture(sender.curValue);
        mViewer.needRelayout();
    }

    class Viewer : Widget {
        override void onDraw(Canvas c) {
            Vector2i d = size/2 - mCur.surface.size/2;
            c.draw(mCur.surface, d);
            c.drawRect(d+mCur.origin-Vector2i(1),
                d+mCur.origin+mCur.size+Vector2i(1),Color(0, 0, 0));
        }

        Vector2i layoutSizeRequest() {
            return mCur.surface.size()+Vector2i(2);
        }
    }

    static this() {
        registerHandler!(typeof(this));
    }
}

import common.resfileformats;

class ViewAniFrames : Container {
    private {
    }

    this(Animation ani) {
        //there's also AnimationStrip and some transformed animations
        auto cani = cast(ComplicatedAnimation)ani;
        if (!cani)
            return;
        Frames frames = cani.frames();

        auto gui = new BoxContainer(false);

        char[] inf;

        inf ~= "Param mappings:\n";
        foreach (int i, Frames.ParamData p; frames.params) {
            inf ~= myformat("  {} <- {} ({} frames)\n", i,
                cFileAnimationParamTypeStr[p.map], p.count);
        }

        Label inftxt = new Label();
        inftxt.textMarkup = inf;
        inftxt.setLayout(WidgetLayout.Aligned(-1,-1));
        gui.add(inftxt);

        for (int idx_c = 0; idx_c < frames.params[2].count; idx_c++) {
            if (idx_c > 0) {
                auto spacer = new Spacer();
                spacer.minSize = Vector2i(2,3);
                spacer.color = Color(1,0,0);
                WidgetLayout lay;
                lay.expand[] = [true, false];
                spacer.setLayout(lay);
                gui.add(spacer);
            }

            auto table = new TableContainer(frames.params[0].count,
                frames.params[1].count, Vector2i(2,2), [true, true]);
            Rect2i bb = frames.boundingBox();
            for (int x = 0 ; x < table.width; x++) {
                for (int y = 0; y < table.height; y++) {
                    auto bmp = new ViewBitmap();
                    bmp.frames = frames;
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
        Frames frames;
        int p1, p2, p3;
        Vector2i offs, size;

        override void onDraw(Canvas c) {
            frames.drawFrame(c, offs, p1, p2, p3);
            c.drawRect(Vector2i(), size-Vector2i(1), Color(1,1,0));
        }

        Vector2i layoutSizeRequest() {
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
        Button mPaused, mShowFrames;
        BoxContainer mGuiBox;
    }

    this(Object r) {
        super(r);

        mTime = new TimeSource("resview");

        auto table = new TableContainer(2, 0, Vector2i(10,1), [true, false]);

        auto infos = new Label();
        infos.font = gFramework.getFont("normal");
        infos.text = "Flags: "
            ~ (resource.keepLastFrame ? "keepLastFrame, " : "")
            ~ (resource.repeat ? "repeat, " : " ")
            ~ myformat("frametime: {} ", resource.frameTime)
            ~ myformat("duration: {}", resource.duration);
        table.addRow();
        table.add(infos, 0, table.height-1, 2, 1);

        void addscr(out ScrollBar scr, out Label lbl) {
            lbl = new Label();
            lbl.font = gFramework.getFont("normal");
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
        mPaused = new Button();
        //mPaused.font = gFramework.getFont("normal");
        mPaused.isCheckbox = true;
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
        p.p1 = mParams[0].curValue;
        p.p2 = mParams[1].curValue;
        p.p3 = mParams[2].curValue;
        mAnim.params = p;
        foreach (int idx, Label l; mParLbl)
            l.text = myformat("Param {}: {}", idx, mParams[idx].curValue);
        mFrameLabel.text = myformat("Frame: {}/{}", mFrame.curValue,
            mFrame.maxValue);
        float speed = 2.0f*mSpeed.curValue/mSpeed.maxValue;
        mTime.slowDown = speed;
        mSpeedLabel.text = myformat("Speed: {}", mTime.slowDown);
    }

    private void onPause(Button sender) {
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
        const radius = 50;
        bool md;
        override void onDraw(Canvas c) {
            auto bnds = mAnim.bounds;
            Vector2i d = size/2;
            mAnim.pos = d;
            mAnim.draw(c);
            c.drawRect(bnds.p1-Vector2i(1), bnds.p2+Vector2i(1),
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

        override void onKeyEvent(KeyInfo infos) {
            if (infos.isMouseButton && infos.isUp) {
                resetAnim();
            }
        }

        Vector2i layoutSizeRequest() {
            return mAnim.bounds.size()+Vector2i(2);
        }
    }

    static this() {
        registerHandler!(typeof(this));
    }
}

class ResViewerTask : Task {
    this(TaskManager mgr, char[] args = "") {
        this(mgr, ResourceSet.init);
    }

    this(TaskManager mgr, ResourceSet resources) {
        super(mgr);
        gWindowManager.createWindow(this, new Viewer(resources), "Res Viewer",
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
            char[] name;
            Object res;

            int opCmp(ResEntry* other) {
                return str.cmp(name, other.name);
            }
        }

        this(ResourceSet resset) {
            //some random non-null ClassInfo, that a resource isn't derived of
            mShowNothing = this.classinfo;

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
            void addLabel(out Label val, char[] name) {
                Font f = gFramework.getFont("normal");
                props.addRow();
                auto lbl = new Label();
                lbl.text = name ~ ":";
                lbl.font = f;
                lbl.setLayout(WidgetLayout.Aligned(-1, 0));
                val = new Label();
                val.font = f;
                props.add(lbl, 0, props.height-1);
                props.add(val, 1, props.height-1);
            }
            addLabel(mName, "Name");

            auto all = new Splitter(true);
            //side.setLayout(WidgetLayout.Expand(false));
            all.setChild(0, side);
            all.setChild(1, otherside);
            addChild(all);

            doUpdate2();
        }

        //check if sub is equal to or is below c
        static bool isSub(ClassInfo sub, ClassInfo c) {
            while (sub) {
                if (sub is c)
                    return true;
                sub = sub.base;
            }
            return false;
        }

        void doUpdate() {
            doSelect(null, null);
            char[][] list;
            mResources = null;
            void add(char[] name, Object res) {
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
                    add(r.name, r.get!(Object)());
                }
            } else {
                gResources.enumResources(
                    (char[] fullname, ResourceItem res) {
                        assert(fullname == res.fullname);
                        add(fullname, res.get);
                    }
                );
            }
            mResources.sort;
            foreach (s; mResources) {
                list ~= s.name;
            }
            mList.setContents(list);
        }

        void doUpdate2() {
            char[][] list = null;
            mResTypes = null;
            foreach (name; ResViewHandlers.classes) {
                auto cinf = ClassInfo.find(name);
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

        private void onSelectType(int index) {
            mCurRes = mShowNothing;
            if (index >= 0)
                mCurRes = mResTypes[index];
            doUpdate();
        }

        private void doSelect(ResEntry* s, ClassInfo type) {
            mName.text = s ? s.name : "-";
            mClient.clear();
            if (s && type) {
                char[] name = type.name;
                Widget widget;
                if (ResViewHandlers.exists(name)) {
                    widget = ResViewHandlers.instantiate(name, s.res).getGUI();
                } else {
                    widget = new Spacer(); //error lol
                }
                mClient.add(widget);
            }
        }

        private void onSelect(int index) {
            doSelect(index < 0 ? null : &mResources[index], mCurRes);
        }
    }

    static this() {
        TaskFactory.register!(typeof(this))("resviewer");
    }
}
