///access to resources after they were loaded
///note that this completely hides all the suckage about how resources are
///located, created and loaded
module common.resset;

import utils.misc;

import rtraits = tango.core.RuntimeTraits;

///a ResourceSet holds a set of resources and can be i.e. used to do level
///themes, graphic themes (GPL versus WWP graphics) or to change graphic aspects
///of the game (different water colors + associated graphics for objects)
///this is done by simply building different ResourceSets for each game
///
///also, each Resource (which is really only a wrapper to a pointer to the real
///object) is instantiated per ResourceSet, so the Resource objects can contain
///values which are only valid per-game (like assigning a network-ID to .id)
class ResourceSet {
    private {
        Entry[string] mResByName;
        bool mSealed; //more for debugging, see seal()
    }

    static class Entry {
        private {
            string mName;
            Object mResource;
            bool mIsAlias;
        }

        private this() {
        }

        ///name as managed by the resource system
        string name() {
            return mName;
        }

/+
        ///a cast exception is thrown if resource can't be cast to T
        T get(T)() {
            return castStrict!(T)(mResource);
        }
+/
        Object resource() {
            return mResource;
        }

        bool isAlias() {
            return mIsAlias;
        }
    }

    override void dispose() {
        foreach (string n, ref Entry e; mResByName) {
            e = null;
        }
    }

    ///add a resource with that name
    void addResource(Object res, string name) {
        doAddResource(res, name, false);
    }

    ///add an alias new_name to res
    void addAlias(string res, string new_name) {
        Entry r = resourceByName(res);
        doAddResource(r.mResource, new_name, true);
    }

    private void doAddResource(Object res, string name, bool is_alias) {
        if (mSealed) {
            assert(false, "seal() was already called");
        }
        if (name in mResByName) {
            throw new ResourceException(name, "double entry");
        }
        auto entry = new Entry();
        entry.mName = name;
        entry.mResource = res;
        entry.mIsAlias = is_alias;
        mResByName[entry.mName] = entry;
    }

    ///disallow further addition of resources to this set
    void seal() {
        mSealed = true;
    }

    ///all resources in this set
    Entry[] resourceList() {
        return mResByName.values;
    }

    Entry resourceByName(string name, bool canfail = false) {
        auto pres = name in mResByName;
        if (!pres) {
            if (!canfail) {
                throw new ResourceException(name, "resource not found");
            } else {
                return null;
            }
        }
        return *pres;
    }

    ///get a resource by name...
    T get(T)(string name, bool canfail = false) {
        auto res = resourceByName(name, canfail);
        if (canfail && !res) {
            return null;
        }
        Object r = res.mResource;
        assert(!!r);
        T ret = cast(T)r;
        if (!ret && !canfail)
            throw new ResourceException(name, "resource has wrong type");
        return ret;
    }

    Object getDynamic(string name, bool canfail = false) {
        return get!(Object)(name, canfail);
    }

    ///return all resources that are of type T (or a subtype of it)
    T[] findAll(T)() {
        static assert(is(T : Object));
        T[] res;
        foreach (Entry e; mResByName) {
            if (auto r = cast(T)e.resource())
                res ~= r;
        }
        return res;
    }

    //same as findAll(), but suitable for scripting
    Object[] findAllDynamic(ClassInfo cls) {
        if (!cls)
            return null;
        Object[] res;
        foreach (Entry e; mResByName) {
            Object o = e.resource();
            if (rtraits.isImplicitly(o.classinfo, cls))
                res ~= o;
        }
        return res;
    }

    ///slow O(n)
    Entry reverseLookup(Object res) {
        foreach (Entry e; mResByName) {
            if (e.mResource is res)
                return e;
        }
        return null;
    }
}

///use this for recoverable loading errors
class LoadException : CustomException {
    this(string name, string why) {
        super("Failed to load '" ~ name ~ "': " ~ why ~ ".");
    }
}

class ResourceException : LoadException {
    this(string a, string b) {
        super(a, b);
    }
}


