//trivial resource viewer (see framework) to ease debugging
module common.resview;

import common.task;

import framework.font;
import framework.framework;
import framework.resources;
import framework.restypes.bitmap;
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

import oldanim = game.animation;

class ResViewHandlers : StaticFactory!(ResViewHandlerGeneric, Resource) {
}

class ResViewHandlerGeneric {
    private {
        Resource mResource;
        Widget mGUI;
    }

    Resource resource() {
        return mResource;
    }

    this(Resource r) {
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

class ResViewHandler(T : Resource) : ResViewHandlerGeneric {
    alias T Type;
    private {
        T mResource;
    }

    this(Resource r) {
        super(r);
        //lol cast it
        mResource = castStrict!(T)(r);
    }

    final override T resource() {
        return mResource;
    }

    static void registerHandler(T1 : ResViewHandler, T2 : Resource)() {
        ResViewHandlers.register!(T1)(typeid(T2.Type).toString());
    }
}

class BitmapHandler : ResViewHandler!(BitmapResource) {
    this(Resource r) {
        super(r);
        setGUI(new Viewer());
    }

    class Viewer : Widget {
        override void onDraw(Canvas c) {
            Vector2i d = size/2 - resource.get().size/2;
            c.draw(resource.get(), d);
            c.drawRect(d-Vector2i(1), d+resource.get.size+Vector2i(1),
                Color(0, 0, 0));
        }

        Vector2i layoutSizeRequest() {
            return resource.get.size()+Vector2i(2); //with frame hurhur
        }
    }

    static this() {
        registerHandler!(typeof(this), Type);
    }
}

class OldAnimationHandler : ResViewHandler!(oldanim.AnimationResource) {
    private {
        oldanim.Animator mAnim;
        ScrollBar[2] mParams;
        Label[2] mParLbl;
    }

    this(Resource r) {
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

        mAnim = new oldanim.Animator();
        mAnim.setAnimation(resource.get());

        //update label texts
        onScrollbar(mParams[0]);

        setGUI(box);
    }

    private void onScrollbar(ScrollBar sender) {
        mAnim.animationState.setParams(mParams[0].curValue, mParams[1].curValue);
        for (int n = 0; n < 2; n++)
            mParLbl[n].text = format("Param %d: %d", n, mParams[n].curValue);
    }

    class Viewer : Widget {
        override void onDraw(Canvas c) {
            Vector2i d = size/2 - resource.get().size/2;
            mAnim.pos = d;
            mAnim.draw(c);
            c.drawRect(d-Vector2i(1), d+resource.get.size+Vector2i(1),
                Color(0, 0, 0));
        }

        Vector2i layoutSizeRequest() {
            return mAnim.size()+Vector2i(2);
        }
    }

    static this() {
        registerHandler!(typeof(this), Type);
    }
}

class ResViewerTask : Task {
    this(TaskManager mgr) {
        super(mgr);
        gWindowManager.createWindow(this, new Viewer(), "Res Viewer",
            Vector2i(650, 400));
    }

    class Viewer : Container {
        StringListWidget mList;
        Button mUpdate;
        SimpleContainer mClient;
        Resource[] mResList;
        Label mName, mUID, mType;

        this() {
            auto side = new BoxContainer(false);
            mList = new StringListWidget();
            mList.onSelect = &onSelect;
            auto listwind = new ScrollWindow(mList, [false, true]);
            listwind.enableMouseWheel = true;
            side.add(listwind);
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

            doUpdate();
        }

        void doUpdate() {
            doSelect(null);
            char[][] list;
            mResList = null;
            gFramework.resources.enumResources(
                (char[] fullname, Resource res) {
                    mResList ~= res;
                    list ~= fullname;
                }
            );
            mList.setContents(list);
        }

        private void onUpdate(Button sender) {
            doUpdate();
        }

        private void doSelect(Resource s) {
            mName.text = s ? s.id : "-";
            mUID.text = s ? format(s.uid) : "-";
            mType.text = s ? s.type.toString() : "-";
            mClient.clear();
            if (s) {
                char[] name = s.type.toString;
                Widget widget;
                if (ResViewHandlers.exists(name)) {
                    widget = ResViewHandlers.instantiate(name, s).getGUI();
                } else {
                    widget = new Spacer(); //error lol
                }
                mClient.add(widget);
            }
        }

        private void onSelect(int index) {
            doSelect(index < 0 ? null : mResList[index]);
        }
    }

    static this() {
        TaskFactory.register!(typeof(this))("resviewer");
    }
}
