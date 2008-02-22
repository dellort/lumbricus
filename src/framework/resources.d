module framework.resources;

import framework.framework;
import framework.filesystem;
import str = std.string;
import utils.configfile;
import utils.log;
import utils.output;
import utils.misc;
import utils.factory;
import utils.time;
import utils.path;

import framework.resset;

///base template for any resource that is held ready for being loaded
///resources are loaded on the first call to get(), not when loading them from
///file
class ResourceItem : ResourceObject {
    ///unique id of resource
    char[] id;

    protected Object mContents;
    private bool mValid = false;
    protected ResourceFile mContext;
    protected ConfigItem mConfig;

    final bool isLoaded() {
        return mValid;
    }

    public ConfigItem config() {
        return mConfig;
    }

    package this(ResourceFile context, char[] id, ConfigItem item)
    {
        mContext = context;
        this.id = id;
        mConfig = item;
        Resources.log("Preparing resource "~id);
    }

    ///get the contents of this resource
    Object get() {
        if (!mContents) {
            preload();
        }
        return mContents;
    }

    //preloads the resource from disk
    package void preload() {
        try {
            Resources.log("Loading resource "~id);
            load();
            assert(!!mContents, "was not loaded?");
            mValid = true;
        } catch (Exception e) {
            char[] errMsg = "Resource " ~ id ~ " (" ~ toString()
                ~ ") failed to load: "~e.msg;
            Resources.log(errMsg);
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
        mContents = null; //let the GC do the work
    }

    char[] fullname() {
        return mContext.filename ~ "::" ~ id;
    }
}

//huh trivial
void addToResourceSet(ResourceSet rs, ResourceItem[] items) {
    foreach (i; items) {
        rs.addResource(i, i.id);
    }
}

alias void delegate(int cur, int total) ResourceLoadProgress;

class ResourceFile {
    private {
        bool loading = true;
        char[] filename, filepath;
        ResourceFile[] requires;
        ResourceItem[] resources;
    }

    private this(char[] fn) {
        filename = fn;
        filepath = getFilePath(filename);
    }

    //correct loading of relative files
    public char[] fixPath(char[] orgVal) {
        if (orgVal.length == 0)
            return orgVal;
        if (orgVal[0] == '/')
            return orgVal;
        return filepath ~ orgVal;
    }

    //this is for resources which are refered by other resources
    //obviously only works within a resource file, from now on
    //NOTE: infinitely slow; if needed rewrite it
    ResourceItem find(char[] id) {
        foreach (i; getAll()) {
            if (i.id == id) {
                return i;
            }
        }
        throw new ResourceException("resource not found: " ~ id);
    }

    //all resources including ones from transitive dependencies
    ResourceItem[] getAll() {
        ResourceItem[] res;
        foreach (r; requires) {
            res ~= r.getAll();
        }
        res ~= resources;
        return res;
    }
}

///the resource manager
///this centrally manages all loaded resources; for accessing resources, use
///ResourceSet from module framework.resset
public class Resources {
    static Log log;
    private ResourceFile[char[]] mLoadedResourceFiles;

    private static class ResFactory : StaticFactory!(ResourceItem, ResourceFile,
        char[], ConfigItem)
    {
    }

    this() {
        log = registerLog("Res");
        //log.setBackend(DevNullOutput.output, "null");
    }

    ///register a class derived from Resource for the internal factory under
    ///the given name
    ///the class T to register must have this constructor:
    ///     this(Resources parent, char[] name, ConfigItem from)
    ///else compilation will fail somewhere in factory.d
    static void registerResourceType(T : ResourceItem)(char[] name) {
        ResFactory.register!(T)(name);
    }

    //"fullname" is the resource ID, prefixed by the filename
    void enumResources(void delegate(char[] fullname, ResourceItem res) cb) {
        foreach (file; mLoadedResourceFiles) {
            foreach (ResourceItem res; file.resources) {
                cb(res.fullname, res);
            }
        }
    }

    //Create a resource directly from a configitem, knowing the
    //resource type identifier
    //This is an internal method and should only used from this class
    //and from Resource implementations
    //*** Internal: Use loadResources() instead ***
    private ResourceItem createResource(ResourceFile context, char[] type,
        ConfigItem it)
    {
        return ResFactory.instantiate(type,context,it.name,it);
    }

    ///load a resource file and add them to dest
    ///configfile_path must be the path to a config file containing nodes like
    ///"resources" and "require_resources"
    ///"resources" nodes contain real resources; if they weren't loaded yet, new
    ///     ResourceItems are created for them so you can actually load them
    ///"require_resources" nodes lead to recursive loading of other files which
    ///     are loaded with loadResources(); using the "fixed" path
    ///the function returnsan object with has the getAll() method to get all
    ///resources which were found in that file (including dependencies).
    public ResourceFile loadResources(char[] configfile_path) {
        //xxx: possibly normalize the filename here!
        auto fn = configfile_path.dup;

        if (fn in mLoadedResourceFiles) {
            auto f = mLoadedResourceFiles[fn];
            if (f.loading) {
                assert(false, "is dat sum circular dependency?");
            }
            return f;
        }

        auto res = new ResourceFile(fn);
        mLoadedResourceFiles[res.filename] = res;

        auto config = gFramework.loadConfig(fn, true);

        foreach (char[] name, char[] value;
            config.getSubNode("require_resources"))
        {
            res.requires ~= loadResources(res.fixPath(value));
        }

        foreach (ConfigNode r; config.getSubNode("resources")) {
            auto type = r.name;
            foreach (ConfigItem i; r) {
                res.resources ~= createResource(res, type, i);
            }
        }

        res.loading = false;

        return res;
    }

    ///just for convenience
    public ResourceSet loadResSet(char[] configfile_path) {
        auto res = loadResources(configfile_path).getAll();
        preloadAll(res);
        auto ret = new ResourceSet();
        addToResourceSet(ret, res);
        return ret;
    }

    public Preloader createPreloader(ResourceItem[] list) {
        return new Preloader(list);
    }

    public Preloader createPreloader(ResourceSet list) {
        return new Preloader(list);
    }

    public void preloadAll(ResourceItem[] list) {
        foreach (r; list) {
            r.preload();
        }
    }

    ///support for preloading stuff incrementally (step-by-step)
    ///since D doesn't support coroutines, pack state in an extra class and call
    ///a "progress...()" method periodically
    public final class Preloader {
        private int mOffset; //already loaded stuff that isn't in mToLoad
        private ResourceItem[] mToLoad;
        private int mCurrent; //next res. to load, index into mToLoad

        this(ResourceItem[] list) {
            doload(list);
        }

        private void doload(ResourceItem[] list) {
            log("Preloading %s resources", list.length);

            mToLoad = list.dup;
        }

        //does some work to get a ResourceItem[] from a ResourceSet again, meh
        this(ResourceSet list) {
            ResourceItem[] rilist;
            foreach (entry; list.resourceList()) {
                auto ri = cast(ResourceItem)(entry.wrapper());
                if (ri)
                    rilist ~= ri;
            }
            doload(rilist);
        }

        ResourceItem[] list() {
            return mToLoad;
        }

        ///for convenience
        ResourceSet createSet() {
            auto ret = new ResourceSet();
            addToResourceSet(ret, list);
            return ret;
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
                    //updateToLoad();

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

    ///Unload all "unnused" resources (whatever that means)
    ///xxx: currently can crash, because surfaces are always freed by force
    ///   actually, Resource or Surface should be refcounted or so to prevent
    //    this; i.e. unload Resource only if underlying object isn't in use
    void unloadUnneeded() {
        //foreach (r; mResources) {
        //    r.invalidate();
        //}
    }
}

class ResourceException : Exception {
    this(char[] msg) {
        super(msg);
    }
}
