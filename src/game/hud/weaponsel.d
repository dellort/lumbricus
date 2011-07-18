module game.hud.weaponsel;

import common.scene;
import framework.config;
import framework.drawing;
import framework.surface;
import framework.font;
import framework.i18n;
import framework.keybindings;
import game.controller;
import game.core;
import game.weapon.weapon;
import game.weapon.weaponset;
import gui.boxcontainer;
import gui.button;
import gui.container;
import gui.global;
import gui.label;
import gui.tablecontainer;
import gui.widget;
import gui.styles;

import utils.array;
import utils.random;
import utils.misc;
import utils.vector2;
import utils.time;

import str = utils.string;

class WeaponSelWindow : Container {
    private {
        GameCore mEngine;

        //from the config file
        string[] mCategories;

        //weapon or placeholder for a weapon
        class Cell : Button {
            WeaponClass weapon;
            WeaponSet.Entry item;

            ImageLabel image;

            Surface active;   //enabled, selectable weapon
            Surface inactive; //disabled weapon (like airstrikes in caves)

            bool infinite() {
                return item.infinite;
            }
            uint quantity() {
                return item.quantity;
            }
            bool canUse() {
                return item.quantity > 0 && weapon.canUse(mEngine);
            }

            this(WeaponClass c) {
                allowFocus = false;
                image = new ImageLabel();
                setClient(image);

                weapon = c;

                Surface icon = weapon.icon;
                if (!icon)
                    icon = gGuiResources.get!(Surface)("missing");

                active = icon;
                inactive = active.clone;
                //make the image look disabled
                inactive.applyBCG(-0.3, 0.5f, 2.5f);

                image.image = active;
                visible = false;
                styles.addClass("in-weapon-cell");
                onClick = &clickWeapon;
                onMouseOver = &mouseoverWeapon;
            }

            //enable/disable etc. weapon based on the list
            void update(WeaponSet wset) {
                if (!wset) {
                    item = WeaponSet.Entry(weapon, 0);
                } else {
                    item = wset.find(weapon);
                }
                if (quantity > 0) {
                    image.image = (canUse ? active : inactive);
                    enabled = canUse;
                }
                visible = (quantity > 0);
            }

            override void onDraw(Canvas canvas) {
                super.onDraw(canvas);
                if (enabled) {
                    float p = item.cooldownRemainPerc(mEngine);
                    if (p > float.epsilon) {
                        Color cdCol = styles.get!(Color)("cooldown-color");
                        canvas.drawPercentRect(Vector2i(0), size, p, cdCol);
                    }
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
        }

        Cell[][string] mRows;
        Cell[] mAll;
        TableContainer mGrid;
        SimpleContainer mGridContainer;
        Label mWeaponName;
        Label mWeaponQuantity;

        //currently shown weapon in the info-line below the weapon grid
        WeaponClass mWeaponInfoline;

        Translator mWeaponTranslate, mWeaponFooTranslate;
        string[] mWeaponPostfixes;
        int mFooCode;
    }

    KeyBindings selectionBindings;

    void delegate(WeaponClass c) onSelectWeapon;

    //also hack-liek
    //checks if "key" is a shortcut, and if so, cycle the weapon
    //c is the currently selected weapon
    bool checkNextWeaponInCategoryShortcut(string category, WeaponClass c) {
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
        Cell w = cast(Cell)sender;
        assert(w !is null);

        if (onSelectWeapon) {
            onSelectWeapon(w.weapon);
        }
    }

    private void mouseoverWeapon(Button sender, bool over) {
        Cell w = cast(Cell)sender;
        assert(w !is null);

        mWeaponInfoline = over ? w.weapon : null;
        updateWeaponInfoline();
    }

    private string translateWeapon(string id) {
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
            mWeaponQuantity.text = w.infinite ? "" : myformat("x%s", w.quantity);
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
        /+
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
                assert(found, myformat("weapon '%s' was not known at init time!",
                    w.weapon.name));
            }
        }
        +/
    }

    //recreate the whole GUI
    //should be only needed once, at initialization
    public void init(GameCore a_engine) {
        //set this to true to also show rows with no weapons in them!
        bool showEmpty = false;

        mEngine = a_engine;

        WeaponClass[] weapons = mEngine.resources.findAll!(WeaponClass)();

        //destroy old GUI, if any
        if (mGrid) {
            mGrid.remove();
            mGrid = null;
        }
        mAll = null;
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
            const cCShortcut = "category_"; //xxx duplicated in gameview.d
            shortcut.text = selectionBindings ?
                translateBind(selectionBindings, cCShortcut ~ category)
                : category;
            shortcut.styles.addClass("weaponsel_shortcut");
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
        styles.addClass("weaponwindow");

        //meh how stupid
        auto conf = loadConfig("wsel.conf").getSubNode("categories");
        foreach (string name, string value; conf) {
            mCategories ~= value;
        }

        mWeaponTranslate = localeRoot.bindNamespace("weapons");
        mWeaponFooTranslate = localeRoot.bindNamespace("weaponsfoo");
        mWeaponPostfixes = mWeaponFooTranslate.names();

        mFooCode = rngShared.nextRange(0, 255);

        auto all = new BoxContainer(false, false, 4);
        mGridContainer = new SimpleContainer();
        all.add(mGridContainer);
        mWeaponName = new Label();
        mWeaponName.styles.addClass("weaponsel_name");
        mWeaponName.shrink = true;
        mWeaponQuantity = new Label();
        mWeaponQuantity.styles.addClass("weaponsel_quantity");
        auto hbox = new BoxContainer(true, false, 10);
        hbox.add(mWeaponName, WidgetLayout.Expand(true));
        hbox.add(mWeaponQuantity, WidgetLayout.Noexpand);
        all.add(hbox);

        addChild(all);
        setChildLayout(all, WidgetLayout.Border(Vector2i(4)));
    }
}
