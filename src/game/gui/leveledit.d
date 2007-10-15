//aw! I couldn't resist!
//NOTE: if this file causes problems, simply exclude it from compilation
//      (not needed for the game)
module game.gui.leveledit;
import utils.vector2;
import utils.rect2;
import utils.mylist;
import utils.mybox;
import framework.commandline;
import framework.framework;
import framework.event;
import common.scene;
import common.common;
import common.task;
import gui.widget;
import gui.container;
import gui.button;
import gui.boxcontainer;
import gui.loader;
import gui.mousescroller;
import gui.wm;
import utils.log;
import utils.configfile;
import levelgen.level;
import levelgen.generator;
import std.string : format;
import utils.output;

import std.bind;

private:

//added to all bounding boxes to increase tolerance
const int cBoundingBorder = 2;

Rect2i emptyBB() {
    return Rect2i(0, 0, -1, -1);
}
bool isEmptyBB(Rect2i r) {
    return (r == emptyBB());
}

class EditObject {
    List!(EditObject) subObjects;
    mixin ListNodeMixin node;
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
        subObjects = new List!(EditObject)(EditObject.node.getListNodeOffset());
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
            if (isEmptyBB(bounds)) {
                bounds = b;
            } else {
                if (!isEmptyBB(b))
                    bounds.extend(b);
            }
        }

        bounds = emptyBB();
        foreach (o; subObjects) {
            addBB(o.bounds);
        }

        bounds.p1 -= Vector2i(cBoundingBorder);
        bounds.p2 += Vector2i(cBoundingBorder);
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
            subObjects.insert_tail(sub);
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
            auto cur = subObjects.tail;
            while (cur) {
                if (cur.pick(p)) {
                    return cur;
                }
                cur = subObjects.prev(cur);
            }
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
            canvas.drawFilledRect(bounds.p1, bounds.p2, c, true);
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
        canvas.drawFilledRect(bounds.p1, bounds.p2, c, true);
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

    /+
    void addTrailingPoint(Vector2i pt) {
        EditPPoint last;
        EditPLine nline;
        if (!subObjects.isEmpty) {
            last = cast(EditPPoint)subObjects.tail;
            assert(last !is null);

            //insert line
            nline = new EditPLine();
            nline.prev = last;
            last.next = nline;
            add(nline, false);
        }
        auto obj = new EditPPoint();
        obj.pt = pt;
        add(obj);
        if (last) {
            obj.prev = nline;
            nline.next = obj;
            //force update
            //ridiculous hack :-)
            obj.isMoving = true;
            last.changedPoints();
            obj.changedPoints();
            obj.isMoving = false;
        }
        if (!first)
            first = obj;
    }
    +/

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

    Texture mPreviewImage;

    Widget mContainer;

    //current rectangle-selection mode
    //(what to do if the user draws this rect)
    //if null, just try to select stuff
    void delegate(Rect2i) onSelect;

    //pseudo object for input and drawing
    class RenderEditor : Widget {
        LevelEditor editor;
        this (LevelEditor e) {
            editor = e;
        }
        protected void onDraw(Canvas c) {
            if (editor.mPreviewImage)
                c.draw(editor.mPreviewImage, Vector2i(0));
            editor.root.draw(c);
            //selection rectangle
            if (editor.isSelecting) {
                auto sel = Rect2i(editor.selectStart, editor.selectEnd);
                sel.normalize();
                c.drawFilledRect(sel.p1, sel.p2, Color(0.5, 0.5, 0.5, 0.5), true);
            }
        }

        override bool canHaveFocus() {
            return true;
        }
        override bool greedyFocus() {
            return true;
        }

        Vector2i layoutSizeRequest() {
            //this is considered to be the default & maximum size of a level
            //xxx should return root.bounds.p2 instead; currently not done
            // because there's no mouse-capture, and so mouse events outside
            // the Widget are always lost
            return Vector2i(2000, 700);
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
            return true;
        }

        /+bool onKeyPress(char[] bind, KeyInfo infos) {
            return false;
        }+/


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

        bool onMouseMove(MouseInfo info) {
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
            return true;
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

    this(TaskManager tm) {
        super(tm);

        root = new EditRoot();
        render = new RenderEditor(this);

        newPolyAt(Rect2i(100, 100, 500, 500));

        commands = new typeof(commands);
        commands.register(Command("preview", &cmdPreview, "preview"));
        commands.register(Command("save", &cmdSave, "save edit level"));
        commands.bind(globals.cmdLine);

        createGui();
    }

    void createGui() {
        //"static", non-configfile version was in r351
        auto loader = new LoadGui(globals.loadConfig("ledit_gui"));
        loader.addNamedWidget(render, "render");
        loader.load();

        //NOTE: indirection through bind is done because using the this-ptr
        // directly would reference the stack, which is invalid when called

        alias typeof(this) Me;

        //button events, sigh
        void setOnClick(char[] name, void delegate(Button, Me) onclick) {
            auto b = loader.lookup!(Button)(name);
            b.onClick = bind(onclick, _0, this).ptr;
        }

        setOnClick("preview", (Button, Me me) {me.genPreview;});
        setOnClick("inspt", (Button, Me me) {me.insertPoint;});
        setOnClick("nochange", (Button, Me me) {me.toggleNochange;});
        setOnClick("addpoly", (Button, Me me) {me.setNewPolygon;});

        mContainer = loader.lookup("ledit_root");
        auto wnd = gWindowManager.createWindowFullscreen(this, mContainer,
            "Level Editor");
        auto props = wnd.properties;
        props.background = Color(0,0,0);
        wnd.properties = props;
    }

    override protected void onKill() {
        mContainer.remove(); //GUI
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
    void toggleNochange() {
        foreachSelected(false,
            (EditObject obj) {
                if (cast(EditPLine)obj) {
                    auto line = cast(EditPLine)obj;
                    line.noChange = !line.noChange;
                }
            }
        );
    }

    //create polygon on next selection
    void setNewPolygon() {
        onSelect = &newPolyAt;
    }

    void saveLevel(ConfigNode sub) {
        LevelGeometry geo = new LevelGeometry();
        geo.size = Vector2i(2000, 700);
        geo.caveness = Lexel.SolidSoft;

        foreach (o; root.subObjects) {
            if (!cast(EditPolygon)o)
                continue;
            EditPolygon p = cast(EditPolygon)o;
            LevelGeometry.Polygon curpoly;
            curpoly.points = p.getPoints();
            curpoly.nochange = p.getNoChangeable();
            curpoly.marker = Lexel.Null;
            geo.polygons ~= curpoly;
        }

        geo.saveTo(sub);
    }

    void cmdSave(MyBox[] args, Output write) {
        ConfigNode rootnode = new ConfigNode();
        auto sub = rootnode.getSubNode("templates").getSubNode("");
        saveLevel(sub);
        auto s = new StringOutput();
        rootnode.writeFile(s);
        write.writefln(s.text);
    }

    void cmdPreview(MyBox[] args, Output write) {
        genPreview();
    }

    void genPreview() {
        //create a level generator configfile...
        ConfigNode config = new ConfigNode();
        saveLevel(config);
        auto templ = new LevelTemplate(config);
        auto generator = new LevelGenerator();
        auto gfx = generator.findRandomGfx("gpl");
        Level level = generator.renderLevel(templ, gfx);
        if (level)
            mPreviewImage = level.image.createTexture();
    }

    static this() {
        TaskFactory.register!(typeof(this))("ledit");
    }
}

