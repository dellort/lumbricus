///access to resources after they were loaded
///note that this completely hides all the suckage about how resources are
///located, created and loaded
module common.resset;

import utils.misc;

///manages a single resource
class ResourceObject {
    ///the resource, must return always the same object
    abstract Object get();
}

///contains the resource itself and a handle to the real entry in ResourceSet
///this struct can be obtained via ResourceSet.Entry.resource!(T)()
struct Resource(T : Object) {
    private T resource;
    //entry must not be referenced from the game engine (serialization issues)
    //ResourceSet.Entry entry;
    private char[] mName;

    final T get() {
        return resource;
        //return entry ? castStrict!(T)(entry.mObject.get()) : T.init;
    }

    char[] name() {
        //return entry.name;
        return mName;
    }

/+
    int id() {
        return entry.id;
    }

    ///return whether this is empty or not
    ///doesn't have anything to do with whether resource is null
    bool defined() {
        return entry !is null;
    }
+/
}

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
        Entry[char[]] mResByName;
        //TODO: possibly change into an array
        Entry[int] mResByID;
        bool mSealed; //more for debugging, see seal()
    }

    class Entry {
        private {
            char[] mName;
            int mID = -1; //by default an invalid ID
            ResourceObject mObject;
        }

        private this() {
        }

        ///name as managed by the resource system
        char[] name() {
            return mName;
        }

        ///user managed ID (for free use, changeable by ResourceSet.setResourceID)
        int id() {
            return mID;
        }

        ///return a Resource struct for this entry
        ///a cast exception is thrown if resource can't be cast to T
        Resource!(T) resource(T)() {
            Resource!(T) res;
            //res.entry = this;
            res.resource = castStrict!(T)(mObject.get());
            res.mName = mName;
            return res;
        }

        ResourceObject wrapper() {
            return mObject;
        }
    }

    ///add a resource with that name
    void addResource(ResourceObject res, char[] name) {
        if (mSealed) {
            assert(false, "seal() was already called");
        }
        if (name in mResByName) {
            throw new ResourceException(name, "double entry");
        }
        auto entry = new Entry();
        entry.mName = name;
        entry.mObject = res;
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

    Entry resourceByName(char[] name, bool canfail = false) {
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
    Resource!(T) resource(T)(char[] name, bool canfail = false) {
        auto res = resourceByName(name, canfail);
        if (canfail && !res) {
            Resource!(T) nothing;
            return nothing;
        }
        return res.resource!(T)();
    }

    ///only the resource itself, by name (when ref. to id or name isn't needed)
    T get(T)(char[] name, bool canfail = false) {
        return resource!(T)(name, canfail).get();
    }
}

///use this for recoverable loading errors
class LoadException : Exception {
    this(char[] name, char[] why) {
        super("Failed to load '" ~ name ~ "': " ~ why ~ ".");
    }
}

class ResourceException : LoadException {
    this(char[] a, char[] b) {
        super(a, b);
    }
}
