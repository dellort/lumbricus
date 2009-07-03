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

//this is stupid; but for now... (all stuff in this file could probbaly be
//radically simplified, because we don't need many things I thought we'd need)
class ResWrap(T) : ResourceObject {
    T value;
    this(T v) {
        value = v;
    }
    override Object get() {
        return value;
    }
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

        ///a cast exception is thrown if resource can't be cast to T
        T get(T)() {
            return castStrict!(T)(mObject.get());
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
    T get(T)(char[] name, bool canfail = false) {
        auto res = resourceByName(name, canfail);
        if (canfail && !res) {
            return null;
        }
        return res.get!(T)();
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
