module game.gui.weaponsel;

import common.common;
import common.scene;
import common.visual;
import framework.framework;
import framework.font;
import framework.i18n;
import game.gamepublic;
import game.weapon;
import gui.boxcontainer;
import gui.button;
import gui.container;
import gui.label;
import gui.tablecontainer;
import gui.widget;

import utils.array;
import utils.misc;
import utils.vector2;

import std.string : format;

class WeaponSelWindow : Container {
    private {
        //from the config file
        char[][] mCategories;

        struct Weapon {
            WeaponClass type;
            int quantity; //as in WeaponItem

            bool infinite() {
                return quantity == WeaponListItem.QUANTITY_INFINITE;
            }

            int opCmp(Weapon* w) {
                return w.type.value - this.type.value;
            }
        }
        //kind of SICK
        Weapon[Button] mButtonToWeapon;
        Weapon[][char[]] mRows;
        TableContainer mGrid;
        SimpleContainer mGridContainer;
        Label mWeaponName;
        Label mWeaponQuantity;

        Translator mWeaponTranslate;

        Font mDFG;
    }

    KeyBindings selectionBindings;

    void delegate(WeaponClass c) onSelectWeapon;

    //also hack-liek
    //checks if "key" is a shortcut, and if so, cycle the weapon
    //c is the currently selected weapon
    bool checkNextWeaponInCategoryShortcut(KeyInfo key, WeaponClass c) {
        char[] b = selectionBindings.findBinding(key);
        auto parr = b in mRows;
        if (!parr)
            return false;
        Weapon[] arr = *parr;
        if (!arr.length)
            return true; //key shortcut catched
        //sry was lazy!
        WeaponClass[] foo = arrayMap(arr, (Weapon w) { return w.type; });
        auto nc = arrayFindNext(foo, c);
        if (nc && onSelectWeapon)
            onSelectWeapon(nc);
        return true;
    }

    private void clickWeapon(Button sender) {
        Weapon* w = sender in mButtonToWeapon;
        assert(w !is null);

        if (onSelectWeapon) {
            onSelectWeapon(w.type);
        }
    }

    private void mouseoverWeapon(Button sender, bool over) {
        Weapon* w = sender in mButtonToWeapon;
        assert(w !is null);

        if (over) {
            mWeaponName.text = mWeaponTranslate(w.type.name);
            mWeaponQuantity.text = w.infinite ? "" : format("x%s", w.quantity);
        } else {
            mWeaponName.text = "";
            mWeaponQuantity.text = "";
        }
    }

    //recreate the whole GUI when weapons change
    //(finer update granularity didn't seem to be worth it)
    public void update(WeaponList weapons) {
        //set this to true to also show rows with no weapons in them!
        bool showEmpty = false;

        if (mGrid) {
            mGrid.remove();
            mGrid = null;
        }
        //xxx this is all a bit fragile and was written at deep night
        //first recreate the rows and find out required box size
        mRows = null;
        uint x_max;
        foreach (c; mCategories) {
            mRows[c] = [];
        }
        foreach (wi; weapons) {
            if (wi.quantity <= 0)
                continue;

            Weapon w;
            w.type = wi.type;
            w.quantity = wi.quantity;
            auto c = w.type.category;
            if (!(c in mRows)) {
                mCategories ~= c; //violence!
                mRows[c] = [];
            }
            auto arr = mRows[c];
            arr ~= w;
            mRows[c] = arr;
            x_max = max(x_max, arr.length);
        }
        //one box for the shortcut
        x_max++;
        //count rows
        uint y_max;
        foreach (wlist; mRows) {
            if (wlist.length > 0 || showEmpty)
                y_max++;
        }
        //create table and insert stuff
        mGrid = new TableContainer(x_max, y_max, Vector2i(3,3));//, [true, true]);
        //mGrid.forceExpand = true;
        //go with the order of categories
        int y = 0;
        foreach (category; mCategories) {
            auto pwlist = category in mRows;
            if (!showEmpty && (!pwlist || !(*pwlist).length)) {
                continue;
            }

            assert(pwlist !is null);
            Weapon[] wlist = *pwlist;
            wlist.sort; //see Weapon; order by weapon-value

            //reverse-resolve shortcut and show
            auto shortcut = new Label();
            //and yes, the shortcut bind-name is the category-id itself
            shortcut.text = selectionBindings ?
                globals.translateBind(selectionBindings, category) : category;
            shortcut.font = mDFG;
            shortcut.drawBorder = false;
            mGrid.add(shortcut, 0, y, WidgetLayout.Noexpand);

            //add the weapon icons
            int x = 1;
            foreach (Weapon w; wlist) {
                auto button = new Button();
                mButtonToWeapon[button] = w;
                button.image = w.type.icon.get.createTexture();
                button.onClick = &clickWeapon;
                button.onMouseOver = &mouseoverWeapon;
                button.drawBorder = false;
                mGrid.add(button, x, y, WidgetLayout.Noexpand);

                x++;
            }

            y++;
        }

        //re-add it
        mGridContainer.add(mGrid);
    }

    this() {
        //meh how stupid
        auto conf = globals.loadConfig("wsel").getSubNode("categories");
        foreach (char[] name, char[] value; conf) {
            mCategories ~= value;
        }

        mWeaponTranslate = new Translator("/weapons/locale");
        mDFG = getFramework.getFont("weaponsel_side");

        auto all = new BoxContainer(false, false, 4);
        mGridContainer = new SimpleContainer();
        all.add(mGridContainer);
        mWeaponName = new Label();
        mWeaponName.drawBorder = false;
        mWeaponName.font = getFramework.getFont("weaponsel_down");
        mWeaponName.shrink = true;
        mWeaponQuantity = new Label();
        mWeaponQuantity.drawBorder = false;
        mWeaponQuantity.font = mWeaponName.font;
        auto hbox = new BoxContainer(true, false, 10);
        hbox.add(mWeaponName, WidgetLayout.Expand(true));
        hbox.add(mWeaponQuantity, WidgetLayout.Noexpand);
        all.add(hbox);

        addChild(all);
        setChildLayout(all, WidgetLayout.Border(Vector2i(6)));

        BoxProperties boxy;
        boxy.back = Color(0.7,0.7,0.7);
        drawBoxStyle = boxy;
        drawBox = true;
    }
}
