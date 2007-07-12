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
            unload();
        mValid = false;
    }

    ///implement this to actually load the data
    ///store result in mContents, throw exception on error
    abstract protected void load();

    protected void unload() {
        //implement if you need this
    }

    //Wrapper for Resources.createResource to keep this private
    protected void createSubResource(char[] type, ConfigItem it,
        bool allowFail = false, char[] id = "")
    {
        mParent.createResource(type,it,allowFail,id);
    }
}

private class ResourceBase(T) : Resource {
    protected T mContents;

    package this(Resources parent, char[] id, ConfigItem item) {
        super(parent, id, item);
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
    private bool[char[]] mResourceRefs;
    //used to assign uids
    private long mCurUid;

    this() {
        log = registerLog("Res");
        //log.setBackend(DevNullOutput.output, "null");
    }

    long getUid() {
        return ++mCurUid;
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
            id = n.filePath~it.name;
        if (!(id in mResources)) {
            Resource r = ResFactory.instantiate(type,this,id,it);
            mResources[id] = r;
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
            mResources[id] = r;
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
        if (doref) {
            mResourceRefs[ret.id] = true;
        }
        return ret;
    }

    private T doFindResource(T)(char[] id, bool allowFail = false) {
        assert(id != "","called resource() with empty id");
        Resource* r = id in mResources;
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

    ///preload all cached resources from disk
    ///Attention: this will load really ALL resources, not just needed ones
    public void preloadAll(ResourceLoadProgress prog) {
        int count = mResources.length;
        log("Preloading ALL resources");
        int i = 0;
        foreach (Resource res; mResources) {
            res.get();
            i++;
            if (prog)
                prog(i, count);
        }
        log("Finished preloading ALL");
    }

    public void preloadUsed(ResourceLoadProgress prog) {
        int count = mResourceRefs.length;
        log("Preloading USED resources");
        int i = 0;
        foreach (char[] id, bool tmp; mResourceRefs) {
            Resource res = mResources[id];
            res.get();
            i++;
            if (prog)
                prog(i, count);
        }
        log("Finished preloading USED");
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
