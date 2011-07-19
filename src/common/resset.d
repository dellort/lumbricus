///access to resources after they were loaded
///note that this completely hides all the suckage about how resources are
///located, created and loaded
module common.resset;

import utils.misc;

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

    void free() {
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

    Entry resourceByName(in char[] name, bool canfail = false) {
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
    T get(T)(in char[] name, bool canfail = false) {
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
            if (isImplicitly(o.classinfo, cls))
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
    this(in char[] name, in char[] why) {
        super(("Failed to load '" ~ name ~ "': " ~ why ~ ".").idup);
    }
}

class ResourceException : LoadException {
    this(in char[] a, in char[] b) {
        super(a, b);
    }
}


// Parts taken from Tango tango.core.RuntimeTraits, as Phobos2 doesn't seem to
//  provide anything like this.
// The only function I needed was isImplicitly().

private:

/**
 * Provides runtime traits, which provide much of the functionality of tango.core.Traits and
 * is-expressions, as well as some functionality that is only available at runtime, using
 * runtime type information.
 *
 * Authors: Chris Wright (dhasenan) $(EMAIL dhasenan@gmail.com)
 * License: Tango License, Apache 2.0
 * Copyright: Copyright (c) 2009, CHRISTOPHER WRIGHT
 */

/** Returns true iff one type is an ancestor of the other, or if the types are the same.
 * If either is null, returns false. */
bool isDerived (ClassInfo derived, ClassInfo base)
{
    if (derived is null || base is null)
        return false;
    do
        if (derived is base)
            return true;
    while ((derived = derived.base) !is null)
    return false;
}

/** Returns true iff implementor implements the interface described
 * by iface. This is an expensive operation (linear in the number of
 * interfaces and base classes).
 */
bool implements (ClassInfo implementor, ClassInfo iface)
{
    foreach (info; applyInterfaces (implementor))
    {
        if (iface is info)
            return true;
    }
    return false;
}

/** Returns true iff an instance of class test is implicitly castable to target.
 * This is an expensive operation (isDerived + implements). */
bool isImplicitly (ClassInfo test, ClassInfo target)
{
    // Keep isDerived first.
    // isDerived will be much faster than implements.
    return (isDerived (test, target) || implements (test, target));
}

/** Iterate through all interfaces that type implements, directly or indirectly, including base interfaces. */
struct applyInterfaces
{
    ///
    static applyInterfaces opCall (ClassInfo type)
    {
        applyInterfaces apply;
        apply.type = type;
        return apply;
    }

    ///
    int opApply (scope int delegate (ref ClassInfo) dg)
    {
        int result = 0;
        for (; type; type = type.base)
        {
            foreach (iface; type.interfaces)
            {
                result = dg (iface.classinfo);
                if (result)
                    return result;
                result = applyInterfaces (iface.classinfo).opApply (dg);
                if (result)
                    return result;
            }
        }
        return result;
    }

    ClassInfo type;
}
