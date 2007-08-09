module common.resources;

import framework.framework;
import framework.filesystem;
import common.common;
import str = std.string;
import utils.configfile;
import utils.log;
import utils.output;
import utils.misc;
import utils.factory;
import utils.time;

private char[][char[]] gNamespaceMap;

///base template for any resource that is held ready for being loaded
///resources are loaded on the first call to get(), not when loading them from
///file
///Resource references can be stored and passed on without ever actually
///loading the file
///once loaded, the resource will stay cached unless invalidated
protected class Resource {
    ///unique id of resource
    char[] id;
    ///unique numeric id
    ///useful for networking, has the same meaning across all nodes
    int uid;

    private bool mValid = false;
    protected Resources mParent;
    protected ConfigItem mConfig;
    package bool mRefed = false;

    final bool isLoaded() {
        return mValid;
    }

    public ConfigItem config() {
        return mConfig;
    }

    package this(Resources parent, char[] id, ConfigItem item)
    {
        mParent = parent;
        this.id = id;
        this.uid = parent.getUid();
        mConfig = item;
        mParent.log("Preparing resource "~id);
    }

    ///get the contents of this resource
    ///allowFail to ignore load errors (not recommended)
    abstract Object get(bool allowFail = false);

    //preloads the resource from disk, allowFail controls if an exception
    //is thrown on error
    package void preload(bool allowFail = false) {
        try {
            mParent.log("Loading resource "~id);
            load();
            mValid = true;
        } catch (Exception e) {
            char[] errMsg = "Resource " ~ id ~ "(" ~ toString() ~ ") failed to load: "~e.msg;
            mParent.log(errMsg);
            if (!allowFail)
                throw new ResourceException(errMsg);
        }
    }

    ///destroy contents and make resource reload on next use
    package void invalidate() {
        if (mValid)
            doUnload();
        mValid = false;
    }

    ///implement this to actually load the data
    ///store result in mContents, throw exception on error
    abstract protected void load();

    protected void doUnload() {
        //implement if you need this
    }

    //Wrapper for Resources.createResource to keep this private
    protected void createSubResource(char[] type, ConfigItem it,
        bool allowFail = false, char[] id = "")
    {
        mParent.createResource(type,it,allowFail,id);
    }

    protected static void setResourceNamespace(T : Resource)(char[] id) {
        gNamespaceMap[ResFactory.lookup!(T)()] = id;
    }
}

private class ResourceBase(T) : Resource {
    protected T mContents;

    package this(Resources parent, char[] id, ConfigItem item) {
        super(parent, id, item);
    }

    override protected void doUnload() {
        mContents = null;
        super.doUnload();
    }

    override T get(bool allowFail = false) {
        if (!mValid)
            preload(allowFail);
        return mContents;
    }
}

alias void delegate(int cur, int total) ResourceLoadProgress;

///the resource manager
///currently manages:
///  - bitmap (Surface)
///  - animations (Animation)
public class Resources {
    private Resource[char[]] mResources;
    Log log;
    private bool[char[]] mLoadedResourceFiles;
    //used to assign uids
    private long mCurUid;

    this() {
        log = registerLog("Res");
        //log.setBackend(DevNullOutput.output, "null");
    }

    long getUid() {
        return ++mCurUid;
    }

    private char[] addNSPrefix(char[] type, char[] resId) {
        assert(type in gNamespaceMap, "'" ~ type ~ "' needs a namespace, set with "
            ~ "setResourceNamespace()");
        return gNamespaceMap[type] ~ "_" ~ resId;
    }

    //Create a resource directly from a configitem, knowing the
    //resource type identifier
    //This is an internal method and should only used from this class
    //and from Resource implementations
    //*** Internal: Use loadResources() instead ***
    private void createResource(char[] type, ConfigItem it,
        bool allowFail = false, char[] id = "")
    {
        ConfigNode n = cast(ConfigNode)it;
        if (!n)
            n = it.parent;
        if (id.length == 0)
            id = n.filePath ~ it.name;
        if (!(id in mResources)) {
            Resource r = ResFactory.instantiate(type,this,id,it);
            mResources[addNSPrefix(type,id)] = r;
        }
    }

    ///hacky: create a resource from a plain filename (only for resources
    ///supporting it, currently just BitmapResource)
    ///id will be the filename
    public T createResourceFromFile(T)(char[] filename,
        bool allowFail = false, bool markDirty = true)
    {
        char[] id = filename;
        if (!(id in mResources)) {
            ConfigValue v = new ConfigValue;
            v.value = filename;
            Resource r = new T(this,id,v);
            mResources[addNSPrefix(ResFactory.lookup!(T)(),id)] = r;
        }
        if (markDirty)
            return resource!(T)(id,allowFail);
        else
            return doFindResource!(T)(id,allowFail);
    }

    ///get a reference to a resource by its id
    /// doref = mark resource as used (for preloading)
    public T resource(T)(char[] id, bool allowFail = false, bool doref = true) {
        T ret = doFindResource!(T)(id, allowFail);
        ret.mRefed |= doref;
        return ret;
    }

    private T doFindResource(T)(char[] id, bool allowFail = false) {
        assert(id != "","called resource() with empty id");
        char[] internalId = addNSPrefix(ResFactory.lookup!(T)(),id);
        Resource* r = internalId in mResources;
        if (!r) {
            char[] errMsg = "Resource "~id~" not defined";
            log(errMsg);
            if (!allowFail)
                throw new ResourceException(errMsg);
            return null;
        }
        T ret = cast(T)*r;
        if (!ret) {
            char[] errMsg = "Resource "~id~" is not of type "~T.stringof;
            log(errMsg);
            if (!allowFail)
                throw new ResourceException(errMsg);
            return null;
        }
        return ret;
    }

    ///support for preloading stuff incrementally (step-by-step)
    ///since D doesn't support coroutines, pack state in an extra class and call
    ///a "progress...()" method periodically
    public final class Preloader {
        private bool mUsedOnly;
        private int mOffset; //already loaded stuff that isn't in mToLoad
        private Resource[] mToLoad;
        private int mCurrent; //next res. to load, index into mToLoad

        this(bool used_only) {
            mUsedOnly = used_only;

            log("Preloading %s resources", mUsedOnly ? "USED" : "ALL");

            updateToLoad();
        }

        private void updateToLoad() {
            mOffset += mToLoad.length;
            mToLoad = null;
            foreach (Resource r; mResources) {
                bool wantLoad = r.mRefed || !mUsedOnly;
                if (wantLoad && !r.isLoaded) {
                    mToLoad ~= r; //inefficient, but optimizing not worthy
                }
            }
        }

        ///total count of resources to load
        ///not guaranteed to be constant!
        int totalCount() {
            return mOffset + mToLoad.length;
        }

        ///number of loaded resources, monotonically growing
        int loadedCount() {
            return mOffset + mCurrent;
        }

        ///(not updated once all requested resources were loaded)
        bool done() {
            return loadedCount >= totalCount;
        }

        ///load count-many resources
        void progressSteps(int count) {
            while (count-- > 0 && !done) {
                mToLoad[mCurrent].get();
                mCurrent++;
                if (done) {
                    //still check for maybe newly created resources
                    //(normally shouldn't happen, but it's simple to handle it)
                    updateToLoad();

                    if (done)
                        log("Finished preloading");
                }
            }
        }

        ///load as much stuff as possible, but return if time was exceeded
        ///this is useful to i.e. update the screen while loading
        void progressTimed(Time return_after) {
            Time start = timeCurrentTime;
            while (!done && timeCurrentTime() - start <= return_after) {
                progressSteps(1);
            }
        }

        ///load everything in one go, no incremental loading (old behaviour)
        void loadAll(ResourceLoadProgress progress = null) {
            while (!done) {
                progressSteps(1);
                if (progress)
                    progress(loadedCount, totalCount);
            }
        }
    }

    ///Create a Preloader, which enables you to incrementally load resources
    /// used_only = if true, only resources marked as "used" are preloaded
    public Preloader createPreloader(bool used_only = true) {
        return new Preloader(used_only);
    }

    public void preloadUsed(ResourceLoadProgress prog) {
        createPreloader().loadAll(prog);
    }

    ///Unload all "unnused" resources (whatever that means)
    ///xxx: currently can crash, because surfaces are always freed by force
    ///   actually, Resource or Surface should be refcounted or so to prevent
    //    this; i.e. unload Resource only if underlying object isn't in use
    void unloadUnneeded() {
        foreach (Resource r; mResources) {
            r.invalidate();
        }
    }

    //load resources as requested in "item"
    //currently, item shall be a ConfigValue which contains the configfile name
    //note that this name shouldn't contain a ".conf", argh.
    //also can be a resources configfile directly
    void loadResources(ConfigItem item) {
        if (!item)
            return;

        ConfigNode cfg;

        auto v = cast(ConfigValue)item;
        if (v) {
            //argh
            ConfigNode n = v.parent;
            //argh
            char[][] files = n.getValueArray!(char[])(v.name);
            foreach (file; files) {
                file = n.fixPathValue(file);
                if (file in mLoadedResourceFiles)
                    continue;

                mLoadedResourceFiles[file] = true;
                cfg = globals.loadConfig(file);
                loadResources(cfg);
            }
            return;
        } else if (cast(ConfigNode)item) {
            cfg = cast(ConfigNode)item;
        } else {
            assert(false);
        }

        assert(cfg !is null);

        auto load_further = cfg.find("require_resources");
        if (load_further !is null) {
            //xxx: should try to prevent possible recursion
            loadResources(load_further);
        }

        //load new introduced resources (not really load them themselves...)
        foreach (char[] resType, ConfigNode resNode;
            cfg.getSubNode("resources"))
        {
            foreach (char[] name, ConfigNode node; resNode) {
                createResource(resType, node, true);
            }
            foreach (ConfigValue v; resNode) {
                createResource(resType, v, true);
            }
        }

        //add aliases
        ConfigNode aliasNode = cfg.getSubNode("resource_aliases");
        foreach (char[] name; aliasNode)
        {
            char[] value = aliasNode.getPathValue(name);
            Resource* aliased = value in mResources;
            if (!aliased) {
                log("WARNING: alias '%s' not found", value);
                continue;
            }
            if (name in mResources) {
                char[] errMsg = "WARNING: alias target '"~name
                    ~"' already exists";
                log(errMsg);
                continue;
            }
            log("Alias: %s -> %s",aliasNode.filePath ~ name,value);
            mResources[aliasNode.filePath ~ name] = *aliased;
        }
    }
}

class ResourceException : Exception {
    this(char[] msg) {
        super(msg);
    }
}

static class ResFactory : StaticFactory!(Resource, Resources, char[], ConfigItem)
{
}
