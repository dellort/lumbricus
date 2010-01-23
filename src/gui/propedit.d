module gui.propedit;

import common.task;

import gui.boxcontainer;
import gui.button;
import gui.container;
import gui.dropdownlist;
import gui.edit;
import gui.label;
import gui.scrollbar;
import gui.tablecontainer;
import gui.widget;

import utils.factory;
import utils.misc;
import utils.proplist;
import utils.vector2;

class PropertyEditor : Container {
    private {
        TableContainer mStuff;
        PropertyNode mRoot;
        EditProperty[] mEditors;
    }

    this() {
        mStuff = new TableContainer(2, 0, Vector2i(3, 5));
        addChild(mStuff);
    }

    private void addValue(PropertyValue v) {
        char[] t = propertyTypeToName(v);
        EditProperty edit;
        if (gPropertyEditors.exists(t)) {
            edit = gPropertyEditors.instantiate(t, v);
        } else {
            edit = new EditUnknown(v);
        }
        edit.doinit();
        int r = mStuff.addRow();
        auto name = new Label();
        name.text = v.path(mRoot);
        mStuff.add(name, 0, r);
        mStuff.add(edit.widget, 1, r);
    }

    void properties(PropertyNode root) {
        mRoot = root;
        mStuff.clear();
        void recurse(PropertyNode cur) {
            if (cur.isValue()) {
                addValue(cur.asValue());
            } else {
                foreach (s; cur.asList()) {
                    recurse(s);
                }
            }
        }
        recurse(root);
    }
}

class EditProperty {
    Widget widget;
    PropertyValue value;
    private {
        int mChanging;
        bool mDead;
    }

    this(PropertyValue v) {
        assert(!!v);
        value = v;
        value.addListener(&internal_onchange);
    }

    void doinit() {
        onchange();
    }

    //call this with code to set a value (to prevent recursion with listener)
    //xxx add handling for invalid values (catch PropertyException)
    protected void set(void delegate() doset) {
        mChanging++;
        scope (exit) mChanging--;
        doset();
    }

    private void internal_onchange() {
        if (mChanging == 0)
            onchange();
    }

    void unlink() {
        //xxx: remove listener???
    }

    protected void onchange() {
    }
}

class EditBool : EditProperty {
//private: lol dmd bug 3581
    PropertyBool mB;
    CheckBox mCheckbox;
    public this(PropertyValue v) {
        super(v);
        mB = castStrict!(PropertyBool)(v);
        mCheckbox = new CheckBox;
        mCheckbox.onClick2 = &onclick;
        widget = mCheckbox;
    }
    override void onchange() {
        mCheckbox.checked = mB.get;
    }
    void onclick() {
        set({mB.set(mCheckbox.checked);});
    }
}

class EditPercent : EditProperty {
//private:
    PropertyPercent mPercent;
    ScrollBar mSlider;
    public this(PropertyValue v) {
        super(v);
        mPercent = castStrict!(PropertyPercent)(v);
        mSlider = new ScrollBar(true);
        mSlider.onValueChange = &onclick;
        mSlider.maxValue = 100;
        mSlider.smallChange = 5;
        mSlider.largeChange = 10;
        widget = mSlider;
    }
    override void onchange() {
        mSlider.curValue = cast(int)(mPercent.get * 100.0);
    }
    void onclick(ScrollBar sender) {
        set({mPercent.set(cast(float)(mSlider.curValue / 100.0));});
    }
}

class EditString : EditProperty {
//private:
    EditLine mText;
    public this(PropertyValue v) {
        super(v);
        mText = new EditLine;
        mText.onChange = &oneditchange;
        widget = mText;
    }
    override void onchange() {
        mText.text = value.asString();
    }
    void oneditchange(EditLine sender) {
        set({value.setAsString(mText.text);});
    }
}

class EditChoice : EditProperty {
//private:
    PropertyChoice mChoice;
    DropDownList mList;
    public this(PropertyValue v) {
        super(v);
        mChoice = castStrict!(PropertyChoice)(v);
        mList = new DropDownList;
        mList.list.setContents(mChoice.choices());
        mList.onSelect = &onselect;
        widget = mList;
    }
    override void onchange() {
        mList.selection = mChoice.asString();
    }
    void onselect(DropDownList list) {
        set({mChoice.setAsString(mList.selection);});
    }
}

class EditCommand : EditProperty {
//private:
    PropertyCommand mC;
    Button mButton;
    public this(PropertyValue v) {
        super(v);
        mC = castStrict!(PropertyCommand)(v);
        mButton = new Button;
        mButton.text = "blurb!";
        mButton.onClick2 = &onclick;
        widget = mButton;
    }
    void onclick() {
        mC.touch();
    }
}

//specially created for unknown property types
class EditUnknown : EditProperty {
//private:
    Label mL;
    public this(PropertyValue v) {
        super(v);
        mL = new Label();
        widget = mL;
    }
    override void onchange() {
        mL.text = "(unknown type) " ~ value.asString();
    }
}

Factory!(EditProperty, PropertyValue) gPropertyEditors;

//convert the type of P/v (class derived from PropertyValue) to some string
//if v is null, use the static type P
//xxx not sane AT ALL, but works for now (and so the hacky mess begins...)
char[] propertyTypeToName(P)(P v) {
    static assert(is(P : PropertyValue));
    return (v ? v.classinfo : P.classinfo).name; //lol.
}

//register editor T for property type P
void registerPropertyEditor(P, T)() {
    gPropertyEditors.register!(T)(propertyTypeToName!(P)(null));
}

static this() {
    gPropertyEditors = new typeof(gPropertyEditors);
    alias registerPropertyEditor reg;
    reg!(PropertyBool, EditBool)();
    reg!(PropertyString, EditString)();
    reg!(PropertyPercent, EditPercent)();
    reg!(PropertyChoice, EditChoice)();
    reg!(PropertyCommand, EditCommand)();
}

import gui.wm;

//add_okcancelapply: false=a window where edit actions take effect immediately,
//  true=add buttons, and copy the properties and write them back on ok/apply
//  xxx not implemented
Window createPropertyEditWindow(Task owner, PropertyNode root,
    bool add_okcancelapply, char[] caption)
{
    //auto c = new PropWndClosure();
    auto edit = new PropertyEditor();
    edit.properties = root;
    /+if (add_okcancelapply) {
        Button o = new Button(), c = new Button(), a = new Button();
        o.text = "OK"; c.text = "Cancel"; a.text = "Apply";
        o.onClick2 = &c.onok; c.onClick2 = &c.oncancel; a.onClick2 = &onapply;
    }+/
    return gWindowManager.createWindow(owner, edit, caption);
}
