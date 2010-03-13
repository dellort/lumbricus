module gui.propedit;

import common.task;

import framework.framework;
import framework.globalsettings;

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
import utils.vector2;

//xxx deprecated
class PropertyEditor : Container {
    private {
        TableContainer mStuff;
        EditProperty[] mEditors;
    }

    this() {
        mStuff = new TableContainer(2, 0, Vector2i(3, 5));
        foreach (s; gSettings) {
            switch (s.type) {
            case SettingType.String:
                addValue!(EditString)(s);
                break;
            case SettingType.Choice:
                if (s.choices == ["true"[], "false"]
                    || s.choices == ["false"[], "true"])
                {
                    addValue!(EditBool)(s);
                } else {
                    addValue!(EditChoice)(s);
                }
                break;
            case SettingType.Percent:
                addValue!(EditPercent)(s);
                break;
            default:
                addValue!(EditUnknown)(s);
            }
        }
        auto r = mStuff.addRow();
        auto fwreload = new Button();
        fwreload.text = "reload framework";
        fwreload.onClick2 = { gFramework.scheduleDriverReload(); };
        mStuff.add(fwreload, 0, r, 2, 1);
        r = mStuff.addRow();
        auto save = new Button();
        save.text = "save to disk";
        save.onClick2 = { saveSettings(); };
        mStuff.add(save, 0, r, 2, 1);
        addChild(mStuff);
    }

    private void addValue(T)(Setting v) {
        EditProperty edit = new T(v);
        edit.doinit();
        int r = mStuff.addRow();
        auto name = new Label();
        name.text = v.name;
        mStuff.add(name, 0, r);
        mStuff.add(edit.widget, 1, r);
    }
}

class EditProperty {
    Widget widget;
    Setting value;
    private {
        int mChanging;
        bool mDead;
    }

    this(Setting v) {
        assert(!!v);
        value = v;
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

    void unlink() {
        //xxx: remove listener???
    }

    protected void onchange() {
    }
}

class EditBool : EditProperty {
//private: lol dmd bug 3581
    CheckBox mCheckbox;
    public this(Setting v) {
        super(v);
        mCheckbox = new CheckBox;
        mCheckbox.onClick2 = &onclick;
        widget = mCheckbox;
    }
    override void onchange() {
        mCheckbox.checked = value.get!(bool)();
    }
    void onclick() {
        set({value.set(mCheckbox.checked);});
    }
}

class EditPercent : EditProperty {
//private:
    ScrollBar mSlider;
    public this(Setting v) {
        super(v);
        mSlider = new ScrollBar(true);
        mSlider.onValueChange = &onclick;
        mSlider.maxValue = 100;
        mSlider.smallChange = 5;
        mSlider.largeChange = 10;
        widget = mSlider;
    }
    override void onchange() {
        mSlider.curValue = cast(int)(value.get!(float)() * 100.0);
    }
    void onclick(ScrollBar sender) {
        set({value.set(cast(float)(mSlider.curValue / 100.0));});
    }
}

class EditString : EditProperty {
//private:
    EditLine mText;
    public this(Setting v) {
        super(v);
        mText = new EditLine;
        mText.onChange = &oneditchange;
        widget = mText;
    }
    override void onchange() {
        mText.text = value.value;
    }
    void oneditchange(EditLine sender) {
        set({value.set(mText.text);});
    }
}

class EditChoice : EditProperty {
//private:
    DropDownList mList;
    public this(Setting v) {
        super(v);
        mList = new DropDownList;
        mList.list.setContents(value.choices);
        mList.onSelect = &onselect;
        widget = mList;
    }
    override void onchange() {
        mList.selection = value.value;
    }
    void onselect(DropDownList list) {
        set({value.set(mList.selection);});
    }
}

//specially created for unknown property types
class EditUnknown : EditProperty {
//private:
    Label mL;
    public this(Setting v) {
        super(v);
        mL = new Label();
        widget = mL;
    }
    override void onchange() {
        mL.text = "(unknown type) " ~ value.value;
    }
}

import gui.window;

WindowWidget createPropertyEditWindow(char[] caption) {
    auto edit = new PropertyEditor();
    return gWindowFrame.createWindow(edit, caption);
}
