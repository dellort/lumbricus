module game.weapon.weaponset;

import common.resset;
import game.core;
import game.events;
import game.sprite;
import game.weapon.weapon;
import utils.configfile;
import utils.misc;
import utils.vector2;
import utils.time;

import tango.util.Convert : to;

//number of weapons changed
alias DeclareEvent!("weaponset_changed", WeaponSet) OnWeaponSetChanged;

//number and types of weapons a team has available
class WeaponSet : GameObject {
    private {
        Entry[] mEntries;
    }

    struct Entry {
        //for the public: all fields readonly (writing getters would be bloat)
        WeaponClass weapon;
        uint quantity; //cINF means infinite
        const cINF = typeof(quantity).max;
        Time lastFire;

        bool infinite() {
            return quantity == cINF;
        }

        char[] quantityToString() {
            if (infinite)
                return "inf";
            return myformat("{}", quantity);
        }

        //non-deterministic (for GUI)
        float cooldownRemainPerc(GameCore engine) {
            float p = 0f;
            if (weapon.cooldown != Time.Null && lastFire != Time.Null) {
                Time diff = (lastFire + weapon.cooldown)
                    - engine.interpolateTime.current;
                p = diff.secsf / weapon.cooldown.secsf;
            }
            return p;
        }
    }

    //config = item from "weapon_sets"
    this (GameCore a_engine, ConfigNode config, bool crateSet = false) {
        this(a_engine);
        foreach (ConfigNode node; config.getSubNode("weapon_list")) {
            WeaponClass w;
            uint quantity;
            char[] wname = node.name;
            try {
                //may throw some exception
                w = engine.resources.get!(WeaponClass)(wname);
                assert(!!w);
            } catch (ResourceException e) {
                engine.log.warn("Error in weapon set '{}': {}", wname, e.msg);
                continue;
            }
            if (node.value == "inf") {
                quantity = Entry.cINF;
            } else {
                quantity = node.getCurValue!(int)();
            }
            if (crateSet) {
                //only drop weapons that are not infinite already,
                //  and that can be used in the current world
                if (quantity == Entry.cINF || !w.canUse(engine))
                    quantity = 0;
            }
            addWeapon(w, quantity);
        }
    }

    //create empty set
    this(GameCore a_engine) {
        super(a_engine, "weaponset");
    }

    private void onChange() {
        //xxx probably not quite kosher, it's a rather random hack
        OnWeaponSetChanged.raise(this);
    }

    void saveToConfig(ConfigNode config) {
        auto node = config.getSubNode("weapon_list");
        node.clear();
        foreach (Entry e; mEntries) {
            node.setStringValue(e.weapon.name, e.quantityToString);
        }
    }

    void iterate(void delegate(Entry e) dg) {
        foreach (e; mEntries)
            dg(e);
    }

    //xxx can't use overloading because of Lua wrapper
    void iterate2(void delegate(WeaponClass weapon, uint quantity) dg) {
        foreach (e; mEntries)
            dg(e.weapon, e.quantity);
    }

    //linear search, but this isn't called that often and item count is low
    private Entry* do_find(WeaponClass w, bool add) {
        foreach (ref e; mEntries) {
            if (e.weapon is w)
                return &e;
        }
        if (!add)
            return null;
        assert(!!w);
        Entry e;
        e.weapon = w;
        mEntries ~= e;
        return &mEntries[$-1];
    }

    Entry find(WeaponClass w) {
        Entry* p = do_find(w, false);
        return p ? *p : Entry(w, 0);
    }

    //add weapons form other set to this set
    void addSet(WeaponSet other) {
        assert(!!other);
        foreach (Entry e; other.mEntries) {
            addWeapon(e.weapon, e.quantity);
        }
    }

    //can pass Entry.cINF to make weapon infinite
    void addWeapon(WeaponClass w, uint quantity = 1) {
        if (!w || quantity < 1)
            return;
        Entry* e = do_find(w, true);
        if (!e.infinite()) {
            if (quantity == Entry.cINF) {
                e.quantity = Entry.cINF;
            } else {
                e.quantity += quantity;
            }
        }
        onChange();
    }

    //decrease weapon by one - return if success
    bool decreaseWeapon(WeaponClass w) {
        Entry* e = do_find(w, false);
        if (!e)
            return false;
        assert(e.quantity != 0); //unallowed state
        if (!e.infinite())
            e.quantity -= 1;
        if (e.quantity == 0) {
            //remove from array by moving the last array element into its place
            size_t idx = e - mEntries.ptr;
            assert(idx < mEntries.length);
            mEntries[idx] = mEntries[$-1];
            mEntries = mEntries[0..$-1];
        }
        onChange();
        return true;
    }

    bool firedWeapon(WeaponClass w) {
        Entry* e = do_find(w, false);
        if (!e)
            return false;
        //note: e.quantity may be 0 (decreaseWeapon is called before)
        e.lastFire = engine.gameTime.current;
        onChange();
        return true;
    }

    //returns true if w currently can't be fired due to cooldown
    //(returns false in all other cases)
    bool coolingDown(WeaponClass w) {
        Entry* e = do_find(w, false);
        if (!e)
            return false;
        return (e.lastFire != Time.Null
            && engine.gameTime.current <= e.lastFire + w.cooldown);
    }

    //return whether at least one ammo point of the weapon is available, and if
    //  the weapon can actually be used in the game
    //returns false for null
    bool canUseWeapon(WeaponClass w) {
        return w && find(w).quantity > 0 && w.canUse(engine);
    }

    //choose a random weapon based on this weapon set
    //returns null if none was found
    //xxx: Implement different drop probabilities (by value/current count)
    WeaponClass chooseRandomForCrate() {
        if (mEntries.length > 0) {
            uint r = engine.rnd.next(0, mEntries.length);
            return mEntries[r].weapon;
        } else {
            return null;
        }
    }

    override bool activity() {
        return false;
    }
}
