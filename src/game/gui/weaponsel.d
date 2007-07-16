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
        Weapon[GuiButton] mButtonToWeapon;
        Weapon[][char[]] mRows;
        TableContainer mGrid;
        SimpleContainer mGridContainer;
        GuiLabel mWeaponName;
        GuiLabel mWeaponQuantity;

        Translator mWeaponTranslate;

        Font mDFG;
    }

    void delegate(WeaponClass c) onSelectWeapon;

    private void clickWeapon(GuiButton sender) {
        Weapon* w = sender in mButtonToWeapon;
        assert(w !is null);

        if (onSelectWeapon) {
            onSelectWeapon(w.type);
        }
    }

    private void mouseoverWeapon(GuiButton sender, bool over) {
        Weapon* w = sender in mButtonToWeapon;
        assert(w !is null);

        if (over) {
            mWeaponName.text = mWeaponTranslate(w.type.name);
            mWeaponQuantity.text = w.infinite ? "" : format(w.quantity);
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
        mGrid.forceExpand = true;
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
            auto shortcut = new GuiLabel();
            //and yes, the shortcut bind-name is the category-id itself
            shortcut.text = bindings ? globals.translateBind(bindings, category)
                : category;
            shortcut.font = mDFG;
            shortcut.drawBorder = false;
            mGrid.add(shortcut, 0, y, WidgetLayout.Noexpand);

            //add the weapon icons
            int x = 1;
            foreach (Weapon w; wlist) {
                auto button = new GuiButton();
                mButtonToWeapon[button] = w;
                button.image = w.type.icon.get.createTexture();
                button.onClick = &clickWeapon;
                button.onMouseOver = &mouseoverWeapon;
                mGrid.add(button, x, y, WidgetLayout.Noexpand);

                x++;
            }

            y++;
        }

        //re-add it
        mGridContainer.add(mGrid);
    }

    class Foolinator : SceneObject {
        override void draw(Canvas c) {
            drawBox(c, Vector2i(0), size, 1, 8, Color(0.7,0.7,0.7));
        }
    }

    this() {
        //meh how stupid
        auto conf = globals.loadConfig("wsel").getSubNode("categories");
        foreach (char[] name, char[] value; conf) {
            mCategories ~= value;
        }

        mWeaponTranslate = new Translator("weapons");
        mDFG = getFramework.getFont("weaponsel_down");

        scene.add(new Foolinator);

        auto all = new BoxContainer(false);
        mGridContainer = new SimpleContainer();
        all.add(mGridContainer);
        mWeaponName = new GuiLabel();
        mWeaponName.drawBorder = false;
        mWeaponName.font = getFramework.getFont("weaponsel_down");
        mWeaponQuantity = new GuiLabel();
        mWeaponQuantity.drawBorder = false;
        mWeaponQuantity.font = mWeaponName.font;
        auto box = new SimpleContainer();
        box.add(mWeaponName, WidgetLayout.Aligned(-1, 0));
        box.add(mWeaponQuantity, WidgetLayout.Aligned(1, 0));
        all.add(box);

        addChild(all);
        setChildLayout(all, WidgetLayout.Border(Vector2i(6)));
    }
}
