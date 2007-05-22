//aw! I couldn't resist!
module game.leveledit;
import utils.vector2;
import utils.rect2;
import utils.mylist;
import framework.commandline;
import framework.framework;
import framework.keysyms;
import game.scene;
import game.common;
import utils.log;
import levelgen.level;
import levelgen.generator;
import std.string : format;

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

    void draw(Canvas canvas) {
        //by default, draw the bounding box, then all subobjects
        auto c = isHighlighted ? Color(1,1,1,0.4) : Color(1,1,1,0.2);
        canvas.drawFilledRect(bounds.p1, bounds.p2, c, true);
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

    bool pick(Vector2i p) {
        auto a = toVector2f(p);
        auto b = toVector2f(mPTs[0]);
        auto c = toVector2f(mPTs[1]);
        return a.distance_from(b, b-c) <= 5.0f;
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

    Vector2i[] getPoints() {
        Vector2i[] res;
        EditPPoint cur = first;
        for (;;) {
            res ~= cur.pt;
            if (!cur.next)
                break;
            cur = cur.next.next;
        }
        return res;
    }
}

class EditRoot : EditObject {
}

class RenderEditor : SceneObject {
    LevelEditor editor;
    this (LevelEditor e) {
        editor = e;
    }
    void draw(Canvas c) {
        if (editor.mPreviewImage)
            c.draw(editor.mPreviewImage, Vector2i(0));
        editor.root.draw(c);
    }
}

public class LevelEditor {
    EditRoot root;
    RenderEditor render;
    Scene scene;
    bool isDraging, didReallyDrag;
    Vector2i dragPick; //start position when draging
    Vector2i dragRel; //moving always relative -> need to undo relative moves
    EditObject pickedObject; //for draging

    Texture mPreviewImage;

    //update cheap things (called often on small state changes)
//    private void updateState() {
//        //scene.thesize = root.bounds.p2;
//    }

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

    bool onKeyDown(EventSink sender, KeyInfo infos) {
        if (infos.code == Keycode.MOUSE_LEFT) {
            auto obj = pickDeepest(sender.mousePos);
            if (gFramework.getModifierState(Modifier.Control)) {
                if (obj)
                    setSelected(obj, !obj.isSelected);
                return false;
            }
            if (!obj) {
                deselectAll();
                return false;
            }

            if (!obj.isSelected)
                setSelected(obj, true);
            pickedObject = obj;
            isDraging = true;
            didReallyDrag = false;
            dragPick = sender.mousePos;
            dragRel = Vector2i(0);
        }
        return false;
    }

    bool onKeyPress(EventSink sender, KeyInfo infos) {
        if (infos.code == Keycode.N)
            insertPoint();
        return false;
    }

    bool onKeyUp(EventSink sender, KeyInfo infos) {
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
        }
        return false;
    }

    bool onMouseMove(EventSink sender, MouseInfo info) {
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
        return true;
    }

    this() {
        scene = new Scene();
        root = new EditRoot();
        render = new RenderEditor(this);
        render.setScene(scene, 2);
        scene.thesize = Vector2i(1000,1000);
        EditPolygon tmp = new EditPolygon();
        root.add(tmp);
        tmp.addTrailingPoint(Vector2i(10, 10));
        tmp.addTrailingPoint(Vector2i(10, 100));
        tmp.addTrailingPoint(Vector2i(100, 100));

        globals.cmdLine.registerCommand("preview", &cmdPreview, "preview");

        auto ev = render.getEventSink();
        ev.onMouseMove = &onMouseMove;
        ev.onKeyDown = &onKeyDown;
        ev.onKeyPress = &onKeyPress;
        ev.onKeyUp = &onKeyUp;
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

    void cmdPreview(CommandLine) {
        //create a level generator configfile...
        ConfigNode rootnode = new ConfigNode();
        auto sub = rootnode.getSubNode("templates").getSubNode("");
        sub["is_cave"] = "true";
        sub["marker"] = "LAND";
        auto polies = sub.getSubNode("polygons");
        const WIDTH = 1900;
        const HEIGHT = 690;
        foreach (o; root.subObjects) {
            if (!cast(EditPolygon)o)
                continue;
            EditPolygon p = cast(EditPolygon)o;
            auto curpoly = polies.getSubNode(""); //create new unnamed node
            curpoly["marker"] = "FREE";
            auto points = curpoly.getSubNode("points");
            Vector2i[] pts = p.getPoints();
            foreach (x; pts) {
                points.setStringValue("",
                    format("%s %s", 1.0f*x.x/WIDTH, 1.0f*x.y/HEIGHT));
            }
        }
        auto generator = new LevelGenerator();
        generator.config = rootnode;
        Level level = generator.generateRandom(WIDTH, HEIGHT, "", "gpl");
        if (level)
            mPreviewImage = level.image.createTexture();
    }
}

