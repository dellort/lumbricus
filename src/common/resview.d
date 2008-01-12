//trivial resource viewer (see framework) to ease debugging
module common.resview;

import common.task;

import framework.font;
import framework.framework;
import framework.resources;
import framework.allres;
import gui.boxcontainer;
import gui.button;
import gui.container;
import gui.label;
import gui.list;
import gui.scrollbar;
import gui.scrollwindow;
import gui.tablecontainer;
import gui.widget;
import gui.wm;

import utils.factory;
import utils.misc;
import utils.vector2;

import std.math : PI;

import game.animation;

class ResViewHandlers : StaticFactory!(ResViewHandlerGeneric, Object) {
}

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

import framework.resfileformats;

class AniHandler : ResViewHandler!(AniFrames) {
    private {
        Widget mViewer;
        ScrollBar mSel;
        SimpleContainer mCont;
    }

    this(Object r) {
        super(r);

        auto box = new BoxContainer(false);
        mSel = new ScrollBar(true);
        mSel.onValueChange = &sel;
        mSel.maxValue = resource.count-1;
        mSel.setLayout(WidgetLayout.Expand(true));
        box.add(mSel);
        mCont = new SimpleContainer();
        auto scroller = new ScrollWindow(mCont);
        box.add(scroller);
        setGUI(box);
    }

    private void sel(ScrollBar sender) {
        auto frames = resource.frames(sender.curValue);
        mCont.clear();
        auto table = new TableContainer(frames.counts[0], frames.counts[1],
            Vector2i(2,2), [true, true]);
        Rect2i bb = resource.framesBoundingBox(sender.curValue);
        for (int x = 0 ; x < table.width; x++) {
            for (int y = 0; y < table.height; y++) {
                auto bmp = new ViewBitmap();
                auto f = frames.getFrame(x, y);
                bmp.part = resource.images.texture(f.bitmapIndex);
                bmp.draw = f.drawEffects;
                bmp.offs = Vector2i(f.centerX, f.centerY);
                bmp.bnds = bb;
                bmp.setLayout(WidgetLayout.Noexpand());
                table.add(bmp, x, y);
            }
        }
        table.setLayout(WidgetLayout.Noexpand());
        mCont.add(table);
    }

    class ViewBitmap : Widget {
        TextureRef part;
        Vector2i offs;
        Rect2i bnds;
        int draw;

        override void onDraw(Canvas c) {
            c.draw(part.surface, bnds.size/2+offs, part.origin, part.size,
                !!(draw & FileDrawEffects.MirrorY));
        }

        Vector2i layoutSizeRequest() {
            return bnds.size;
        }
    }

    static this() {
        registerHandler!(typeof(this));
    }
}

class AnimationHandler : ResViewHandler!(Animation) {
    private {
        Animator mAnim;
        ScrollBar[2] mParams;
        Label[2] mParLbl;
    }

    this(Object r) {
        super(r);

        auto table = new TableContainer(2, 2, Vector2i(10,1), [true, false]);
        void addp(int n) {
            auto lbl = new Label();
            lbl.drawBorder = false;
            lbl.font = gFramework.getFont("normal");
            mParLbl[n] = lbl;
            table.add(lbl, 0, n);
            auto scr = new ScrollBar(true);
            scr.minValue = -90;
            scr.maxValue = 600;
            scr.onValueChange = &onScrollbar;
            mParams[n] = scr;
            table.add(scr, 1, n);
        }

        addp(0);
        addp(1);

        auto box = new BoxContainer(false, false, 10);
        table.setLayout(WidgetLayout.Expand(true));
        box.add(table);
        box.add(new Viewer());

        mAnim = new Animator();
        mAnim.setAnimation(resource);

        //update label texts
        onScrollbar(mParams[0]);

        setGUI(box);
    }

    private void onScrollbar(ScrollBar sender) {
        AnimationParams p;
        p.p1 = mParams[0].curValue;
        p.p2 = mParams[1].curValue;
        mAnim.setParams(p);
        for (int n = 0; n < 2; n++)
            mParLbl[n].text = format("Param %d: %d", n, mParams[n].curValue);
    }

    private int p1() {
        return mParams[0].curValue;
    }
    private void p1(int v) {
        mParams[0].curValue = v;
        onScrollbar(null);
    }

    class Viewer : Widget {
        const radius = 50;
        bool md;
        override void onDraw(Canvas c) {
            auto bnds = mAnim.bounds;
            Vector2i d = size/2;
            mAnim.pos = d;
            mAnim.draw(c);
            c.drawRect(d+bnds.p1-Vector2i(1), d+bnds.p2+Vector2i(1),
                Color(0, 0, 0));
            //assume p1() in degrees (0..360)
            auto dir = Vector2f.fromPolar(radius, (-p1()+180+90)/360.0f*PI*2);
            c.drawCircle(size/2+toVector2i(dir), 5, Color(1,0,0));
        }

        override bool onMouseMove(MouseInfo inf) {
            auto angle = toVector2f(inf.pos-size/2).normal.toAngle;
            //(not if NaN)
            if (angle == angle) {
                p1 = 180+90-cast(int)(angle/PI/2*360);
            }
            return true;
        }

        override bool onKeyEvent(KeyInfo infos) {
            if (infos.isMouseButton) {
                md = infos.isDown;
                return true;
            }
            return super.onKeyEvent(infos);
        }

        Vector2i layoutSizeRequest() {
            return mAnim.bounds.size()+Vector2i(2);
        }
    }

    static this() {
        registerHandler!(typeof(this));
    }
}

/+
should be ported back!
has to be merged with OldAnimationHandler, which is now new again
class FramesHandler : ResViewHandler!(FramesResource) {
    private {
        int mAniId, mFrameIdx;
        Label mLblAniId, mLblFrameIdx;
        ScrollBar mSbFrameIdx;
        FrameProvider mFrames;
    }

    this(Resource r) {
        super(r);
        mFrames = resource.get();

        auto table = new TableContainer(2, 2, Vector2i(10,1), [true, false]);

        Label mkLbl(int n) {
            auto lbl = new Label();
            lbl.drawBorder = false;
            lbl.font = gFramework.getFont("normal");
            table.add(lbl, 0, n);
            return lbl;
        }

        ScrollBar mkSb(int n, int max) {
            auto scr = new ScrollBar(true);
            scr.minValue = 0;
            scr.maxValue = max;
            table.add(scr, 1, n);
            return scr;
        }

        mLblAniId = mkLbl(0);
        auto scr = mkSb(0, 700);
        scr.onValueChange = &onScrollbarAni;

        mLblFrameIdx = mkLbl(1);
        mSbFrameIdx = mkSb(1, 0);  //max value is set from onScrollbar event
        mSbFrameIdx.onValueChange = &onScrollbarFrame;

        onScrollbarAni(scr);
        onScrollbarFrame(mSbFrameIdx);

        auto box = new BoxContainer(false, false, 10);
        table.setLayout(WidgetLayout.Expand(true));
        box.add(table);
        box.add(new Viewer());

        setGUI(box);
    }

    private void onScrollbarAni(ScrollBar sender) {
        mAniId = sender.curValue;
        mLblAniId.text = format("Animation ID: %d", mAniId);
        mSbFrameIdx.maxValue = mFrames.frameCount(mAniId)-1;
    }

    private void onScrollbarFrame(ScrollBar sender) {
        mFrameIdx = sender.curValue;
        mLblFrameIdx.text = format("Frame index: %d", mFrameIdx);
    }

    class Viewer : Widget {
        override void onDraw(Canvas c) {
            //pos is the animation center
            mFrames.draw(c, mAniId, mFrameIdx, size/2);
            Vector2i d = size/2;
            Vector2i b = mFrames.bounds(mAniId).size/2;
            c.drawRect(d-b-Vector2i(1), d+b+Vector2i(1), Color(0, 0, 0));
        }

        Vector2i layoutSizeRequest() {
            return mFrames.bounds(mAniId).size+Vector2i(2);
        }

    }

    static this() {
        registerHandler!(typeof(this), Type);
    }
}
+/

class ResViewerTask : Task {
    this(TaskManager mgr) {
        super(mgr);
        gWindowManager.createWindow(this, new Viewer(), "Res Viewer",
            Vector2i(650, 400));
    }

    class Viewer : Container {
        StringListWidget mList;
        StringListWidget mResTypeList;
        Button mUpdate;
        SimpleContainer mClient;
        ResourceItem[] mResList;
        ClassInfo[] mResTypes;
        ClassInfo mCurRes;
        Label mName, mUID, mType;

        this() {
            auto side = new BoxContainer(false);

            mList = new StringListWidget();
            mList.onSelect = &onSelect;
            auto listwind = new ScrollWindow(mList, [false, true]);
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
                lbl.drawBorder = false;
                lbl.text = name ~ ":";
                lbl.font = f;
                lbl.setLayout(WidgetLayout.Aligned(-1, 0));
                val = new Label();
                val.drawBorder = false;
                val.font = f;
                props.add(lbl, 0, props.height-1);
                props.add(val, 1, props.height-1);
            }
            addLabel(mName, "Name");
            addLabel(mUID, "UID");
            addLabel(mType, "Type");

            auto all = new BoxContainer(true, false, 7);
            //xxx: need splitter control
            side.setLayout(WidgetLayout.Expand(false));
            all.add(side);
            all.add(otherside);
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
            mResList = null;
            struct Sorter {
                ResourceItem res;
                int opCmp(Sorter* other) {
                    return str.cmp(res.fullname, other.res.fullname);
                }
            }
            Sorter[] sorted;
            gFramework.resources.enumResources(
                (char[] fullname, ResourceItem res) {
                    if (isSub(res.get.classinfo, mCurRes)) {
                        sorted ~= Sorter(res);
                    }
                }
            );
            sorted.sort;
            foreach (s; sorted) {
                mResList ~= s.res;
                list ~= s.res.fullname;
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
            mResTypeList.setContents(list);
            mCurRes = null;
            doUpdate();
        }

        private void onUpdate(Button sender) {
            doUpdate2();
        }

        private void onSelectType(int index) {
            mCurRes = null;
            if (index >= 0)
                mCurRes = mResTypes[index];
            doUpdate();
        }

        private void doSelect(ResourceItem s, ClassInfo type) {
            mName.text = s ? s.id : "-";
            //mUID.text = s ? format(s.uid) : "-";
            //mType.text = s ? s.type.toString() : "-";
            mClient.clear();
            if (s) {
                s.get(); //load (even when no handler exists)
                char[] name = type.name;
                Widget widget;
                if (ResViewHandlers.exists(name)) {
                    widget = ResViewHandlers.instantiate(name, s.get).getGUI();
                } else {
                    widget = new Spacer(); //error lol
                }
                mClient.add(widget);
            }
        }

        private void onSelect(int index) {
            doSelect(index < 0 ? null : mResList[index], mCurRes);
        }
    }

    static this() {
        TaskFactory.register!(typeof(this))("resviewer");
    }
}
