module game.hud.weaponsel;

import common.common;
import common.scene;
import common.visual;
import framework.framework;
import framework.font;
import framework.i18n;
import game.gamepublic;
import game.controller;
import game.weapon.weapon;
import gui.boxcontainer;
import gui.button;
import gui.container;
import gui.label;
import gui.tablecontainer;
import gui.widget;

import utils.array;
import utils.random;
import utils.misc;
import utils.vector2;

import str = utils.string;

class WeaponSelWindow : Container {
    private {
        //from the config file
        char[][] mCategories;

        //weapon or placeholder for a weapon
        class Cell : Container {
            WeaponClass weapon;
            WeaponItem item; //can be null (=> not available)

            Button active;  //enabled, selectable weapon
            Label inactive; //disabled weapon (like airstrikes in caves)

            bool infinite() {
                return item ? item.infinite() : false;
            }
            int quantity() {
                return item ? item.count : 0;
            }
            bool canUse() {
                return item ? item.canUse : false;
            }

            bool visible() {
                return active.parent || inactive.parent;
            }

            this(WeaponClass c) {
                weapon = c;
                active = new Button();
                mButtonToCell[active] = this;
                active.image = weapon.icon;
                active.onClick = &clickWeapon;
                active.onMouseOver = &mouseoverWeapon;
                inactive = new Label();
                auto dimg = active.image.clone;
                //make the image look disabled
                dimg.applyBCG(-0.3, 0.5f, 2.5f);
                inactive.image = dimg;
                active.styles.addClasses(["in-weapon-cell"]);
                inactive.styles.addClasses(["in-weapon-cell"]);
            }

            //enable/disable etc. weapon based on the list
            void update(WeaponSet wset) {
                item = null;
                if (wset) {
                    auto pitem = weapon in wset.weapons;
                    item = pitem ? *pitem : null;
                }
                active.remove();
                inactive.remove();
                if (quantity > 0) {
                    addChild(canUse ? active : inactive);
                }
            }

            //used by init() code to sort row lines
            //(not used by the GUI or so)
            override int opCmp(Object o) {
                auto w = castStrict!(typeof(this))(o); //blergh
                auto res = -(w.weapon.value - this.weapon.value);
                //if of same value compare untranslated names instead
                if (res == 0)
                    res = str.cmp(this.weapon.name, w.weapon.name);
                return res;
            }

            override protected Vector2i layoutSizeRequest() {
                auto s1 = active.layoutCachedContainerSizeRequest();
                auto s2 = inactive.layoutCachedContainerSizeRequest();
                //so that removing a weapon doesn't change size!
                return s1.max(s2);
            }
        }

        //kind of SICK
        Cell[Button] mButtonToCell; //(reverse of Cell.active)
        Cell[][char[]] mRows;
        Cell[] mAll;
        TableContainer mGrid;
        SimpleContainer mGridContainer;
        Label mWeaponName;
        Label mWeaponQuantity;

        //currently shown weapon in the info-line below the weapon grid
        WeaponClass mWeaponInfoline;

        Translator mWeaponTranslate, mWeaponFooTranslate;
        char[][] mWeaponPostfixes;
        int mFooCode;

        Font mDFG;
    }

    KeyBindings selectionBindings;

    void delegate(WeaponClass c) onSelectWeapon;

    //also hack-liek
    //checks if "key" is a shortcut, and if so, cycle the weapon
    //c is the currently selected weapon
    bool checkNextWeaponInCategoryShortcut(char[] category, WeaponClass c) {
        auto parr = category in mRows;
        if (!parr)
            return false;
        Cell[] arr = *parr;
        if (!arr.length)
            return true; //key shortcut catched
        //sry was lazy!
        WeaponClass[] foo;
        foreach (Cell w; arr) {
            if (w.canUse && w.quantity > 0)
                foo ~= w.weapon;
        }
        auto nc = arrayFindNext(foo, c);
        if (nc && onSelectWeapon)
            onSelectWeapon(nc);
        return true;
    }

    private void clickWeapon(Button sender) {
        Cell* w = sender in mButtonToCell;
        assert(w !is null);

        if (onSelectWeapon) {
            onSelectWeapon(w.weapon);
        }
    }

    private void mouseoverWeapon(Button sender, bool over) {
        Cell* w = sender in mButtonToCell;
        assert(w !is null);

        mWeaponInfoline = over ? w.weapon : null;
        updateWeaponInfoline();
    }

    private char[] translateWeapon(char[] id) {
        auto tr = mWeaponTranslate(id);
        auto count = mWeaponPostfixes.length;
        if (count == 0)
            return tr;
        uint hash = 123 + mFooCode;
        foreach (char c; tr) {
            hash ^= c;
        }
        return mWeaponFooTranslate(mWeaponPostfixes[hash % count], tr);
    }

    private void updateWeaponInfoline() {
        Cell w;
        foreach (Cell c; mAll) {
            if (c.weapon is mWeaponInfoline) {
                w = c;
                break;
            }
        }

        if (w && w.visible()) {
            mWeaponName.text = translateWeapon(w.weapon.name);
            mWeaponQuantity.text = w.infinite ? "" : myformat("x{}", w.quantity);
        } else {
            mWeaponName.text = "";
            mWeaponQuantity.text = "";
        }
    }

    //recreate the whole GUI when weapons change
    //(finer update granularity didn't seem to be worth it)
    public void update(WeaponSet wset) {
        foreach (Cell c; mAll) {
            c.update(wset);
        }
        updateWeaponInfoline();
        debug {
            if (!wset)
                return;
            //check if there's an entry in weapons for which no Cell exists
            foreach (w; wset.weapons) {
                bool found;
                foreach (c; mAll) {
                    if (w.weapon is c.weapon) {
                        found = true;
                        break;
                    }
                }
                assert(found, myformat("weapon '{}' was not known at init time!",
                    w.weapon.name));
            }
        }
    }

    //recreate the whole GUI
    //should be only needed once, at initialization
    public void init(WeaponClass[] weapons) {
        //set this to true to also show rows with no weapons in them!
        bool showEmpty = false;

        //destroy old GUI, if any
        if (mGrid) {
            mGrid.remove();
            mGrid = null;
        }
        mAll = null;
        mButtonToCell = null;
        mRows = null;

        //for each WeaponClass a Cell
        mAll.length = weapons.length;
        for (int n = 0; n < mAll.length; n++) {
            mAll[n] = new Cell(weapons[n]);
        }

        //xxx this is all a bit fragile and was written at deep night
        //first recreate the rows
        foreach (c; mCategories) {
            mRows[c] = [];
        }
        foreach (w; mAll) {
            auto c = w.weapon.category;
            if (!(c in mRows)) {
                mCategories ~= c; //violence!
                mRows[c] = [];
            }
            auto arr = mRows[c];
            arr ~= w;
            mRows[c] = arr;
        }
        //create table and insert stuff
        mGrid = new TableContainer(1, 0, Vector2i(3,3));//, [true, true]);
        //mGrid.forceExpand = true;
        //go with the order of categories
        foreach (category; mCategories) {
            auto pwlist = category in mRows;
            if (!showEmpty && (!pwlist || !(*pwlist).length)) {
                continue;
            }

            int y = mGrid.addRow();

            assert(pwlist !is null);
            Cell[] wlist = *pwlist;
            wlist.sort; //see Weapon; order by weapon-value

            //reverse-resolve shortcut and show
            auto shortcut = new Label();
            //and yes, the shortcut bind-name is the category-id itself
            const cCShortcut = "category "; //xxx duplicated in gameview.d
            shortcut.text = selectionBindings ?
                globals.translateBind(selectionBindings, cCShortcut ~ category)
                : category;
            shortcut.font = mDFG;
            mGrid.add(shortcut, 0, y, WidgetLayout.Noexpand);

            //add the weapon icons
            int x = 1;
            foreach (Cell c; wlist) {
                if (x >= mGrid.width) {
                    mGrid.setSize(x+1, mGrid.height);
                }
                mGrid.add(c, x, y, WidgetLayout.Noexpand);

                x++;
            }
        }

        //re-add it
        mGridContainer.add(mGrid);
    }

    this() {
        //hm
        styles.id = "weaponwindow";

        //meh how stupid
        auto conf = loadConfig("wsel").getSubNode("categories");
        foreach (char[] name, char[] value; conf) {
            mCategories ~= value;
        }

        mWeaponTranslate = localeRoot.bindNamespace("weapons");
        mDFG = gFramework.getFont("weaponsel_side");
        mWeaponFooTranslate = localeRoot.bindNamespace("weaponsfoo");
        mWeaponPostfixes = mWeaponFooTranslate.names();

        mFooCode = rngShared.nextRange(0, 255);

        auto all = new BoxContainer(false, false, 4);
        mGridContainer = new SimpleContainer();
        all.add(mGridContainer);
        mWeaponName = new Label();
        mWeaponName.font = gFramework.getFont("weaponsel_down");
        mWeaponName.shrink = true;
        mWeaponQuantity = new Label();
        mWeaponQuantity.font = gFramework.getFont("weaponsel_down_bold");
        auto hbox = new BoxContainer(true, false, 10);
        hbox.add(mWeaponName, WidgetLayout.Expand(true));
        hbox.add(mWeaponQuantity, WidgetLayout.Noexpand);
        all.add(hbox);

        addChild(all);
        setChildLayout(all, WidgetLayout.Border(Vector2i(4)));
    }
}
