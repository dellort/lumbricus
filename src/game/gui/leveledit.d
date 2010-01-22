//aw! I couldn't resist!
//NOTE: if this file causes problems, simply exclude it from compilation
//      (not needed for the game)
module game.gui.leveledit;
import utils.vector2;
import utils.rect2;
import utils.list2;
import utils.mybox;
import framework.commandline;
import framework.framework;
import framework.event;
import framework.filesystem;
import framework.i18n;
import common.scene;
import common.common;
import common.task;
import gui.widget;
import gui.container;
import gui.button;
import gui.boxcontainer;
import gui.list;
import gui.loader;
import gui.mousescroller;
import gui.wm;
import utils.log;
import utils.misc;
import utils.array;
import utils.configfile;
import game.levelgen.level;
import game.levelgen.landscape;
import game.levelgen.generator;
import game.levelgen.genrandom;
import game.levelgen.placeobjects;
import game.levelgen.renderer;
import utils.output;

//import stdx.bind;
import utils.stream;

//for playing the preview
import game.gametask;
import game.setup;

private:

//added to all bounding boxes to increase tolerance
const int cBoundingBorder = 2;

class EditObject {
    ObjectList!(EditObject, "node") subObjects;
    ObjListNode!(typeof(this)) node;
    Rect2i bounds;
    EditObject parent;
    //sum of sub-objects, that are selected (including this)
    uint subselected;
    //if this node is selected (subselected will be >0, but from subselected
    //alone, you can't tell whether this object is selected or not)
    //set with LevelEditor.setSelected(this, state)
    bool isSelected;
    //quite stupid hack for moving stuff in LevelEditor
    bool isMoving;

    this() {
        subObjects = new typeof(subObjects);
    }

    bool isHighlighted() {
        return (subselected > 0);
    }

    //returns true if maybechild is a transitive child of us
    //always false for "maybechild is this"
    bool isTransitiveParentOf(EditObject maybechild) {
        auto cur = maybechild.parent;
        while (cur) {
            if (cur is this)
                return true;
            cur = cur.parent;
        }
    }

    bool hasSelectedKids() {
        return subselected > (isSelected ? 1 : 0);
    }

    //members can override this
    protected void doUpdateBoundingBox() {
        void addBB(Rect2i b) {
            if (!bounds.isNormal()) {
                bounds = b;
            } else {
                if (b.isNormal())
                    bounds.extend(b);
            }
        }

        bounds = Rect2i.Empty();
        foreach (o; subObjects) {
            addBB(o.bounds);
        }

        if (bounds.isNormal()) {
            bounds.p1 -= Vector2i(cBoundingBorder);
            bounds.p2 += Vector2i(cBoundingBorder);
        }
    }

    //changed points or subobjects
    //update of bounding box is propagating upwards
    private void internalChangedPoints() {
        doUpdateBoundingBox();
        if (parent) {
            parent.doChangedPoints();
        }
    }

    //implementors of EditObjects must call this after changing point positions
    protected final void doChangedPoints() {
        internalChangedPoints();
        changedPoints();
    }

    //user can override this to capture position changes
    void changedPoints() {
    }

    //update bounding box downwards
    final void updateBB() {
        foreach (o; subObjects) {
            o.updateBB();
        }
        doUpdateBoundingBox();
    }

    //move relative (absolute move avoided because objects don't necessarely
    //have a start; at most, they have a bounding box or so)
    void moveRel(Vector2i rel) {
        //default implementation: move all subobjects
        //NOTE: as the sub objects change their position, the bounding box will
        //      be updated... this is done by changedPoints()
        foreach (o; subObjects) {
            o.isMoving = true;
        }
        foreach (o; subObjects) {
            o.moveRel(rel);
        }
        foreach (o; subObjects) {
            o.isMoving = false;
        }
    }

    //after the object was added to the subObjects list, do the important stuff
    final void doAdd(EditObject sub) {
        //first update all bounding boxes of the new object
        sub.updateBB();
        //then do updates upwards the tree to notice the new bounding box
        doChangedPoints();
    }

    void add(EditObject sub, bool to_tail = true) {
        assert(sub.parent is null);
        sub.parent = this;
        if (to_tail) {
            subObjects.add(sub);
        } else {
            subObjects.insert_head(sub);
        }
        doAdd(sub);
    }

    //try to pick an object by a coordinate
    //returns true, is _this_ object is affected
    bool pick(Vector2i p) {
        return bounds.isInside(p);
    }
    //try to find a subobject
    EditObject pickSub(Vector2i p) {
        if (pick(p)) {
            //backwards, because objects with higher zorder (== drawn at last)
            //should also be picked preferably
            //xxx replaced backwards iteration by forward iteration + suckiness
            EditObject last;
            foreach (EditObject cur; subObjects) {
                if (cur.pick(p))
                    last = cur;
            }
            return last;
        }
        return null;
    }

    //select all objects which touch the bounding box
    //doesn't necessarely use the object's bounding box, but should rather
    //behave as if pickSub() was called for each pixel
    EditObject[] pickBoundingBox(in Rect2i bb) {
        auto res = pickSubBoundingBox(bb);
        if (doPickBoundingBox(bb)) {
            res ~= this;
        }
        return res;
    }

    //like pickBoundingBox(), but only pick sub objects
    EditObject[] pickSubBoundingBox(in Rect2i bb) {
        EditObject[] res;
        foreach (o; subObjects) {
            res ~= o.pickBoundingBox(bb);
        }
        return res;
    }

    //if the this object is picked (without any sub objects)
    protected bool doPickBoundingBox(in Rect2i bb) {
        //default: by bounding box
        return bb.intersects(bounds);
    }

    void draw(Canvas canvas) {
        //by default, draw the bounding box, then all subobjects
        auto c = isHighlighted ? Color(1,1,1,0.4) : Color(1,1,1,0.2);
        if (cast(EditRoot)this is null) {
            canvas.drawFilledRect(bounds.p1, bounds.p2, c);
        }
        foreach (o; subObjects) {
            o.draw(canvas);
        }
    }
}

//NOTE: contains no subobjects
class EditPoint : EditObject {
    Vector2i mPT;

    Vector2i pt() {
        return mPT;
    }
    void pt(Vector2i pt) {
        if (mPT != pt) {
            mPT = pt;
            doChangedPoints();
        }
    }

    bool pick(Vector2i p) {
        return (toVector2f(p-mPT).length) <= 5;
    }

    override void doUpdateBoundingBox() {
        bounds = Rect2i(mPT - Vector2i(cBoundingBorder),
            mPT + Vector2i(cBoundingBorder));
    }

    void moveRel(Vector2i rel) {
        mPT += rel;
        doChangedPoints();
    }

    void draw(Canvas canvas) {
        auto c = isHighlighted ? Color(1,1,1) : Color(0.5,0.5,0.5);
        canvas.drawFilledRect(bounds.p1, bounds.p2, c);
    }
}

//NOTE: doesn't contain subobjects
class EditLine : EditObject {
    Vector2i[2] mPTs;

    void setPT(int index, Vector2i pt) {
        if (mPTs[index] != pt) {
            mPTs[index] = pt;
            doChangedPoints();
        }
    }
    Vector2i getPT(int index) {
        return mPTs[index];
    }

    override bool pick(Vector2i p) {
        auto a = toVector2f(p);
        auto b = toVector2f(mPTs[0]);
        auto c = toVector2f(mPTs[1]);
        return a.distance_from(b, b-c) <= 5.0f;
    }

    override protected bool doPickBoundingBox(in Rect2i bb) {
        //xxx :)
        return super.doPickBoundingBox(bb);
    }

    override void doUpdateBoundingBox() {
        bounds = Rect2i(mPTs[0], mPTs[1]);
        bounds.normalize();
    }

    void moveRel(Vector2i rel) {
        mPTs[0] += rel;
        mPTs[1] += rel;
        doChangedPoints();
    }

    void draw(Canvas canvas) {
        auto c = isHighlighted ? Color(1,1,1) : Color(0.5,0.5,0.5);
        canvas.drawLine(mPTs[0], mPTs[1], c);
    }
}

//line from a polygon
class EditPLine : EditLine {
    //both must always be non-null
    EditPPoint prev;
    EditPPoint next;

    bool noChange;

    void draw(Canvas canvas) {
        Color x = noChange ? Color(1,1,0) : Color(1,1,1);
        auto c = isHighlighted ? x : x*0.5;
        canvas.drawLine(mPTs[0], mPTs[1], c);
    }

    override void changedPoints() {
        //move both joining points (they must exist)
        assert((prev !is null) && (next !is null));
        if (!prev.isMoving)
            prev.pt = getPT(0);
        if (!next.isMoving)
            next.pt = getPT(1);
    }

    //insert a new point, split the line into two lines
    void split(Vector2i at) {
        EditPPoint np = new EditPPoint();
        EditPLine nl = new EditPLine();
        next.isMoving = true;
        np.isMoving = true;
        parent.add(np);
        parent.add(nl, false);

        //np connects to nl
        np.next = nl; nl.prev = np;
        //nl to next
        nl.next = next; next.prev = nl;
        //this to np
        next = np; np.prev = this;

        //update and force updates
        np.pt = at;
        np.doChangedPoints();
        np.isMoving = false;
        nl.next.isMoving = false;
        nl.next.doChangedPoints();
    }
}

//point from a polygon
class EditPPoint : EditPoint {
    //both can be null
    EditPLine prev;
    EditPLine next;

    override void changedPoints() {
        //a point has 0, 1 or 2 joining lines
        if (prev && !prev.isMoving)
            prev.setPT(1, pt);
        if (next && !next.isMoving)
            next.setPT(0, pt);
    }
}

class EditPolygon : EditObject {
    //the polygon contains subobjects of the types EditPPoint and EditPLine
    EditPPoint first;

    //xxx lumbricus-level specific data, maybe move out of here
    Lexel marker = Lexel.Null; //default is cave
    bool p_changeable = true, p_visible = true;

    //init closed polygon
    void initLine(Vector2i[] pts) {
        //allowed for initlization only
        assert(first is null);
        assert(pts.length >= 3);
        first = new EditPPoint();
        auto last = new EditPPoint();
        auto line = new EditPLine();
        line.prev = first; first.next = line;
        line.next = last;  last.prev = line;
        //and the line back...
        auto back = new EditPLine();
        back.prev = last;  last.next = back;
        back.next = first; first.prev = back;
        //hm
        add(first);
        add(last);
        add(line, false);
        add(back, false);
        //set the points, warning stupidity!
        first.isMoving = true;
        last.isMoving = true;
        first.pt = pts[0];
        last.pt = pts[$-1];
        first.isMoving = false;
        last.isMoving = false;
        //insert the rest points
        auto cur = line;
        foreach (Vector2i pt; pts[1..$-1]) {
            cur.split(pt);
            cur = cur.next.next;
        }
    }

    Vector2i[] getPoints() {
        Vector2i[] res;
        EditPPoint cur = first;
        for (;;) {
            res ~= cur.pt;
            if (!cur.next)
                break;
            if (cur.next.next is first)
                break;
            cur = cur.next.next;
        }
        return res;
    }
    //get indices of points whose following line is not changeable (noChange)
    uint[] getNoChangeable() {
        uint[] res;
        EditPPoint cur = first;
        int index = 0;
        for (;;) {
            if (!cur.next) {
                break;
            } else {
                if (cur.next.noChange) {
                    res ~= index;
                }
            }
            if (cur.next.next is first)
                break;
            cur = cur.next.next;
            index++;
        }
        return res;
    }
    //reverse of above; doesn't reset the EditPLine.nochange property
    void setNoChangeable(uint[] nochange) {
        EditPPoint cur = first;
        int index = 0;
        for (;;) {
            if (!cur.next) {
                break;
            } else {
                //inefficient
                foreach (uint x; nochange) {
                    if (x == index) {
                        cur.next.noChange = true;
                        break;
                    }
                }
            }
            if (cur.next.next is first)
                break;
            cur = cur.next.next;
            index++;
        }
    }
}

class EditRoot : EditObject {
}

public class LevelEditor : Task {
    EditRoot root;
    RenderEditor render;
    CommandBucket commands;
    bool isDraging, didReallyDrag;
    Vector2i dragPick; //start position when draging
    Vector2i dragRel; //moving always relative -> need to undo relative moves
    EditObject pickedObject; //for draging

    bool isSelecting;
    Vector2i selectStart, selectEnd;

    //cf. LevelGeometry.caveness
    Lexel levelCaveness = Lexel.SolidSoft; //means it's a cave
    Vector2i levelSize = {2000, 700};

    Level mCurrentPreview;
    LandscapeBitmap mPreviewImage;
    GenerateFromTemplate mPreview2;

    Window mWindow;

    Widget mEditor;
    Widget mLoadTemplate;
    Button[3] mS;
    Button mCaveCheckbox, mNochangeCheckbox, mPreviewCheckbox,
        mPreview2Checkbox;

    StringListWidget mLoadTemplateList;
    LevelTemplate[] mTemplateList; //temporary during mLoadTemplate
    MouseScroller mScroller;

    //current rectangle-selection mode
    //(what to do if the user draws this rect)
    //if null, just try to select stuff
    void delegate(Rect2i) onSelect;

    //pseudo object for input and drawing
    class RenderEditor : Widget {
        LevelEditor editor;
        this (LevelEditor e) {
            focusable = true;
            editor = e;
        }
        protected void onDraw(Canvas c) {
            if (mPreviewCheckbox.checked && editor.mPreviewImage)
                editor.mPreviewImage.draw(c, Vector2i(0));
            if (mPreview2Checkbox.checked && editor.mPreview2)
                editor.renderGeoWireframe(editor.mPreview2, c);
            editor.root.draw(c);
            //selection rectangle
            if (editor.isSelecting) {
                auto sel = Rect2i(editor.selectStart, editor.selectEnd);
                sel.normalize();
                c.drawFilledRect(sel.p1, sel.p2, Color(0.5, 0.5, 0.5, 0.5));
            }
        }

        override bool greedyFocus() {
            return true;
        }

        Vector2i layoutSizeRequest() {
            return levelSize;
        }

        bool onKeyDown(char[] bind, KeyInfo infos) {
            if (infos.code == Keycode.MOUSE_LEFT) {
                auto obj = pickDeepest(mousePos);
                if (gFramework.getModifierState(Modifier.Control)) {
                    if (obj)
                        setSelected(obj, !obj.isSelected);
                    return true;
                }
                if (!obj || obj is root) {
                    deselectAll();
                    //start selection mode
                    selectStart = mousePos;
                    selectEnd = selectStart;
                    isSelecting = true;
                    return true;
                }

                if (!obj.isSelected)
                    setSelected(obj, true);
                pickedObject = obj;
                isDraging = true;
                didReallyDrag = false;
                dragPick = mousePos;
                dragRel = Vector2i(0);
            }
            if (infos.code == Keycode.MOUSE_RIGHT) {
                mScroller.mouseScrollToggle();
            }
            return true;
        }

        bool onKeyUp(char[] bind, KeyInfo infos) {
            if (infos.code == Keycode.MOUSE_LEFT) {
                if (isDraging) {
                    isDraging = false;
                    if (!didReallyDrag) {
                        deselectAll();
                        if (pickedObject) {
                            setSelected(pickedObject, true);
                        }
                    }
                }
                if (isSelecting) {
                    isSelecting = false;
                    selectEnd = mousePos;
                    auto r = Rect2i(selectStart, selectEnd);
                    r.normalize();
                    if (onSelect) {
                        auto tmp = onSelect;
                        onSelect = null;
                        tmp(r);
                    } else {
                        doSelect(r);
                    }
                }
            }
            return true;
        }

        override protected void onKeyEvent(KeyInfo ki) {
            auto b = findBind(ki);
            (ki.isDown && onKeyDown(b, ki))
                || (ki.isUp && onKeyUp(b, ki));
        }

        override void onMouseMove(MouseInfo info) {
            if (isDraging) {
                didReallyDrag = true;
                auto move = -dragRel + (info.pos - dragPick);
                dragRel += move;
                //the same stupid hack about isMoving is in moveRel() itself
                foreachSelected(true,
                    (EditObject cur) {
                        cur.isMoving = true;
                    }
                );
                foreachSelected(true,
                    (EditObject cur) {
                        cur.moveRel(move);
                    }
                );
                foreachSelected(true,
                    (EditObject cur) {
                        cur.isMoving = false;
                    }
                );
            }
            if (isSelecting) {
                selectEnd = info.pos;
            }
        }
    } //RenderEditor

    //update cheap things (called often on small state changes)
    private void updateState() {
        //scene.thesize = root.bounds.p2;
    }

    private EditObject pickDeepest(Vector2i at) {
        EditObject cur = root;
        for (;;) {
            auto next = cur.pickSub(at);
            if (!next)
                return cur;
            cur = next;
        }
        //never reached
        assert(false);
    }

    private void setSelected(EditObject obj, bool select_state) {
        void updateParent(void delegate(EditObject cur) code) {
            EditObject cur = obj;
            while (cur) {
                code(cur);
                cur = cur.parent;
            }
        }

        if (select_state == obj.isSelected)
            return;

        //simply refuse to select root!
        if (obj is root)
            return;

        if (select_state) {
            //select the object
            obj.isSelected = true;
            updateParent((EditObject o){o.subselected++;});
        } else {
            //deselect
            obj.isSelected = false;
            updateParent((EditObject o){o.subselected--;});
        }

        //is this right??? (added this later)
        updateSelected();
    }

    private void updateSelected() {
        updateLexelType();
        updateNochange();
    }

    //enumerate all objects with isSelected==true
    //noParents == true:
    //  no (selected) objects that have selected children (needed for multi-sel)
    //  if this confuses you, don't change any code of the LevelEditor, srsly
    private void foreachSelected(bool noParents,
        void delegate(EditObject obj) code)
    {
        void doStuff(EditObject cur) {
            if (cur.isSelected && !(noParents && cur.hasSelectedKids))
                code(cur);
            if (cur.hasSelectedKids) {
                foreach (o; cur.subObjects) {
                    if (o.subselected > 0) {
                        doStuff(o);
                    }
                }
            }
        }
        doStuff(root);
    }

    //iterate over everything which is selected or which has selected children
    private void foreachSelectedAll(void delegate(EditObject obj) code) {
        void doStuff(EditObject cur) {
            if (cur.isSelected || cur.hasSelectedKids)
                code(cur);
            if (cur.hasSelectedKids) {
                foreach (o; cur.subObjects) {
                    if (o.subselected > 0) {
                        doStuff(o);
                    }
                }
            }
        }
        doStuff(root);
    }

    void deselectAll() {
        foreachSelected(false,
            (EditObject obj) {
                setSelected(obj, false);
            }
        );
    }

    void doSelect(Rect2i r) {
        EditObject[] sel = root.pickBoundingBox(r);
        foreach (o; sel) {
            //don't select PLines, it's annoying
            if (cast(EditPLine)o)
                continue;
            setSelected(o, true);
        }
    }

    void newPolyAt(Rect2i r) {
        EditPolygon tmp = new EditPolygon();
        tmp.initLine([r.p1, Vector2i(r.p1.x, r.p2.y),r.p2,
            Vector2i(r.p2.x, r.p1.y)]);
        root.add(tmp);
    }

    this(TaskManager tm, char[] args = "") {
        super(tm);

        root = new EditRoot();
        render = new RenderEditor(this);

        newPolyAt(Rect2i(100, 100, 500, 500));

        commands = new typeof(commands);
        registerCommands();
        commands.bind(globals.cmdLine);

        createGui();
    }

    private void btn_setnochange(Button b) {
        setNochange(b.checked);
    }
    private void btn_setcave(Button b) {
        setCave(b.checked);
    }

    void createGui() {
        //"static", non-configfile version was in r351
        auto loader = new LoadGui(loadConfig("dialogs/ledit_gui"));
        loader.addNamedWidget(render, "render");
        loader.load();

        //NOTE: indirection through bind is done because using the this-ptr
        // directly would reference the stack, which is invalid when called

        alias typeof(this) Me;

        //button events, sigh
        //bind removed because LDC barfed on it, old version in r582
        void setOnClick2(char[] name, void delegate() onclick) {
            auto b = loader.lookup!(Button)(name);
            b.onClick2 = onclick;
        }
        void setOnClick(char[] name, void delegate(Button b) onclick) {
            auto b = loader.lookup!(Button)(name);
            b.onClick = onclick;
        }

        setOnClick2("preview", &genPreview);
        setOnClick2("inspt", &insertPoint);
        setOnClick2("addpoly", &setNewPolygon);
        setOnClick2("play", &play);
        setOnClick2("load", &loadTemplate);

        setOnClick("setnochange", &btn_setnochange);
        setOnClick("setcave", &btn_setcave);

        mS[0] = loader.lookup!(Button)("s1");
        mS[1] = loader.lookup!(Button)("s2");
        mS[2] = loader.lookup!(Button)("s3");
        mS[0].onClick = &selLexelType;
        mS[1].onClick = mS[0].onClick;
        mS[2].onClick = mS[0].onClick;

        mNochangeCheckbox = loader.lookup!(Button)("setnochange");
        mPreviewCheckbox = loader.lookup!(Button)("showpreview");
        mPreview2Checkbox = loader.lookup!(Button)("showpreview2");
        mCaveCheckbox = loader.lookup!(Button)("setcave");

        mEditor = loader.lookup("ledit_root");
        mWindow = gWindowManager.createWindowFullscreen(this, mEditor,
            "Level Editor");
        auto props = mWindow.properties;
        props.background = Color(0,0,0);
        mWindow.properties = props;

        //that other dialog to load templates
        mLoadTemplate = loader.lookup("load_templ");
        mLoadTemplateList = loader.lookup!(StringListWidget)("load_list");
        setOnClick2("load_ok", &loadTemplate_OK);
        setOnClick2("load_cancel", &loadTemplate_Cancel);

        mScroller = loader.lookup!(MouseScroller)("scroller");
    }

    const cLexelTypes = [Lexel.Null, Lexel.SolidSoft, Lexel.SolidHard];

    void selLexelType(Button b) {
        int n = -1;
        foreach (int x, b2; mS) {
            if (b2 is b) { n = x; break; }
        }
        if (n < 0)
            return; //wtf happened?

        //switch the others off (radio button like behaviour)
        foreach (b2; mS) {
            if (b2 !is b)
                b2.checked = false;
        }

        auto type = cLexelTypes[n];

        //set selection to that type
        foreachSelected(true,
            (EditObject obj) {
                auto poly = cast(EditPolygon)obj;
                if (poly) {
                    poly.marker = type;
                }
            }
        );
    }

    void updateLexelType() {
        //(overcomplicated)
        //find the most common marker type from all selected polygons...
        int[cLexelTypes.length] win;
        foreachSelectedAll(
            (EditObject obj) {
                auto poly = cast(EditPolygon)obj;
                if (poly) {
                    foreach (int index, t; cLexelTypes) {
                        if (poly.marker == t)
                            win[index]++;
                    }
                }
            }
        );
        //...and set that as selection
        auto winindex = arrayFindHighest(win);
        if (win[winindex] == 0)
            winindex = -1; //select nothing if 0
        foreach (index, b; mS) {
            b.checked = index == winindex;
        }
    }

    private void loadTemplate() {
        //exchange the Window's GUI to display the dialog, oh what evilness
        mWindow.client = mLoadTemplate;
        auto lgen = new LevelGeneratorShared();
        auto templs = lgen.templates.all();
        char[][] names;
        mTemplateList = null;
        auto templ_trans = localeRoot.bindNamespace("templates");
        templ_trans.errorString = false;
        foreach (LevelTemplate t; templs) {
            names ~= templ_trans(t.description);
            mTemplateList ~= t;
        }
        mLoadTemplateList.setContents(names);
    }

    private void loadTemplate_Cancel() {
        mWindow.client = mEditor;
    }

    private void loadTemplate_OK() {
        mWindow.client = mEditor;
        auto sel = mLoadTemplateList.selectedIndex;
        clear();
        if (sel < 0)
            return;
        loadFromTemplate(mTemplateList[sel]);
    }

    void loadFromTemplate(LevelTemplate templ) {
        assert(!!templ);
        clear();
        //currently we throw everything away, except the geometry:
        //if there's one lol; I extended the Level, but not the level editor
        //so it's natural there's information loss
        //also it's not very nice to load the stuff manually sigh
        auto node = templ.data.getPath("objects.land0");
        if (node && node["type"] == "landscape_template") {
            auto geo = new LandscapeGeometry();
            geo.loadFrom(node);
            doLoadGeometry(geo);
        }
        //update GUI
        mCaveCheckbox.checked = levelCaveness != Lexel.Null;
    }

    private void doLoadGeometry(LandscapeGeometry geo) {
        levelSize = geo.size;
        levelCaveness = geo.fill;
        foreach (LandscapeGeometry.Polygon p; geo.polygons) {
            //xxx: only loads the point-list, nothing else
            auto poly = new EditPolygon();
            poly.initLine(p.points);
            poly.setNoChangeable(p.nochange);
            poly.marker = p.marker;
            poly.p_changeable = p.changeable;
            poly.p_visible = p.visible;
            root.add(poly);
        }
        render.needResize(); //for level size
    }

    void clear() {
        mPreviewImage = null;
        mCurrentPreview = null;
        //xxx this is most likely a BAD IDEA
        root = new EditRoot();
    }

    //play the preview
    void play() {
        if (!mCurrentPreview)
            genPreview();
        if (!mCurrentPreview)
            return;
        //cut'n'paste from game.gui.preview
        auto gc = loadGameConfig(loadConfig("newgame"),
            mCurrentPreview);
        //don't care about the game anymore as soon as spawned
        new GameTask(manager, gc);
    }

    override protected void onKill() {
        commands.kill();
    }

    void insertPoint() {
        EditPLine pline;
        foreachSelected(false,
            (EditObject o) {
                pline = pline ? pline : cast(EditPLine)o;
            }
        );
        if (pline) {
            pline.split(pline.getPT(0)+(pline.getPT(1)-pline.getPT(0))/2);
        }
    }

    //for the currently selected lines, toggle the nochange-flag
    void setNochange(bool s) {
        foreachSelected(false,
            (EditObject obj) {
                if (cast(EditPLine)obj) {
                    auto line = cast(EditPLine)obj;
                    line.noChange = s;
                }
            }
        );
    }

    void updateNochange() {
        //if one is, show it as "nochange"
        //looks like checkbox needs middle-state :/
        //(a disabled state too, if nothing useful is selected)
        bool nochange;
        foreachSelected(false,
            (EditObject obj) {
                if (cast(EditPLine)obj) {
                    auto line = cast(EditPLine)obj;
                    nochange |= line.noChange;
                }
            }
        );
        mNochangeCheckbox.checked = nochange;
    }

    void setCave(bool c) {
        //only support SolidSoft caves hurhur
        auto ncaveness = c ? Lexel.SolidSoft : Lexel.Null;
        if (levelCaveness == ncaveness) {
            return;
        }

        //convert the whole level on the fly lol
        foreach (o; root.subObjects) {
            auto poly = cast(EditPolygon)o;
            if (!poly)
                continue;
            //invert the marker
            //not that SolidHard markers won't be touched which this
            if (poly.marker == levelCaveness) {
                poly.marker = ncaveness;
            } else if (poly.marker == ncaveness) {
                poly.marker = levelCaveness;
            }
        }

        levelCaveness = ncaveness;

        //reload some GUI states
        updateSelected();
    }

    //create polygon on next selection
    void setNewPolygon() {
        onSelect = &newPolyAt;
    }

    void saveLevel(ConfigNode sub) {
        sub["description"] = "levelgenerator";
        sub["load_defaults"] = (levelCaveness == Lexel.Null) ? "isle" : "cave";

        auto ls0 = sub.getPath("objects.land0", true);
        ls0["type"] = "landscape_template";

        auto geo = new LandscapeGeometry();
        geo.size = levelSize;
        geo.fill = levelCaveness;

        foreach (o; root.subObjects) {
            if (!cast(EditPolygon)o)
                continue;
            EditPolygon p = cast(EditPolygon)o;
            LandscapeGeometry.Polygon curpoly;
            curpoly.points = p.getPoints();
            curpoly.nochange = p.getNoChangeable();
            curpoly.marker = p.marker;
            curpoly.changeable = p.p_changeable;
            curpoly.visible = p.p_visible;
            geo.polygons ~= curpoly;
        }

        geo.saveTo(ls0);
    }

    void cmdSave(MyBox[] args, Output write) {
        char[] filename = args[0].unbox!(char[])();
        ConfigNode rootnode = new ConfigNode();
        auto sub = rootnode.getSubNode("templates").add();
        saveLevel(sub);
        try {
            Stream outp = gFS.open(filename, File.WriteCreate);
            auto s = new StreamOutput(outp);
            rootnode.writeFile(s);
            outp.close();
        } catch (FilesystemException e) {
            write.writefln("oh noes! something has gone wrong: '{}'", e);
        }
    }

    void cmdPreview(MyBox[] args, Output write) {
        genPreview();
    }

    void registerCommands() {
        commands.register(Command("preview", &cmdPreview, "preview"));
        commands.register(Command("save", &cmdSave, "save edit level",
            ["text...:filename"]));
    }

    void genPreview() {
        if (!mPreviewCheckbox.checked && !mPreview2Checkbox.checked)
            mPreviewCheckbox.checked = true;
        genRenderedLevel();
    }

    Level genRenderedLevel() {
        //create a level generator configfile...
        ConfigNode config = new ConfigNode();
        saveLevel(config);
        auto shared = new LevelGeneratorShared();
        //second parameter is the "name", don't know what it was for
        auto templ = new LevelTemplate(config, "hallo");
        auto generator = new GenerateFromTemplate(shared, templ);
        generator.selectTheme(shared.themes.findRandom("gpl"));
        mCurrentPreview = generator.render();
        assert(!!mCurrentPreview);
        //xxx: there might be several landscapes with different positions etc.
        mPreviewImage = null;
        foreach (obj; mCurrentPreview.objects) {
            if (auto ls = cast(LevelLandscape)obj) {
                mPreviewImage = ls.landscape;
                break;
            }
        }
        mPreview2 = generator;
        return mCurrentPreview;
    }

    //render a wireframe image of the geometry and the objects
    void renderGeoWireframe(GenerateFromTemplate g, Canvas c)
    {
        foreach (d; g.listGenerated()) {
            if (d.ls && (d.ls.landscape is mPreviewImage) && d.geo) {
                auto theme = g.theme;
                doRenderGeoWireframe(c, d.geo, theme ? theme.genTheme : null,
                    d.objs);
            }
        }
    }
    void doRenderGeoWireframe(Canvas c, LandscapeGeometry geo,
        LandscapeGenTheme theme, LandscapeObjects objs)
    {
        foreach (p; geo.polygons) {
            auto plist = p.points.dup;
            if (plist.length == 0)
                continue;
            plist ~= plist[0]; //close polygon
            for (int n = 0; n < plist.length-1; n++) {
                c.drawLine(plist[n], plist[n+1], Color(1,1,1));
                Rect2i r;
                r.p1 = r.p2 = plist[n];
                r.extendBorder(Vector2i(2));
                c.drawFilledRect(r, Color(0.7));
            }
        }
        if (!theme || !objs)
            return;
        foreach (p; objs.items) {
            auto obj = theme.findObject(p.id);
            auto rc = Rect2i.Span(p.params.at, p.params.size);
            c.drawRect(rc, Color(0.7, 0.7, 0.7));
        }
    }

    static this() {
        TaskFactory.register!(typeof(this))("leveledit");
    }
}

