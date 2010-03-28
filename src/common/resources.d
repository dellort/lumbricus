module common.resources;

import framework.config;
import framework.filesystem;
import utils.configfile;
import utils.log;
import utils.output;
import utils.misc;
import utils.factory;
import utils.time;
import utils.path;
import utils.perf;

import common.resset;

///manages a single resource
class ResourceObject {
    ///the resource, must return always the same object
    abstract Object get();
}

///base template for any resource that is held ready for being loaded
///resources are loaded on the first call to get(), not when loading them from
///file
class ResourceItem : ResourceObject {
    ///unique id of resource
    char[] id;

    protected Object mContents;
    private bool mValid = false;
    protected ResourceFile mContext;
    protected ConfigNode mConfig;

    final bool isLoaded() {
        return mValid;
    }

    public ConfigNode config() {
        return mConfig;
    }

    package this(ResourceFile context, char[] id, ConfigNode item)
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
        //commented out the try-catch, because it catches even assert()s and
        //  stuff, which is annoying at best
        //try {
            Resources.log("Loading resource "~id);
            debug gResources.ls_start(this);
            load();
            debug gResources.ls_stop(this);
            assert(!!mContents, "was not loaded?");
            mValid = true;
        /+} catch (Exception e) {
            char[] errMsg = "Resource " ~ id ~ " (" ~ toString()
                ~ ") failed to load: "~e.toString~"  - location: "
                ~ mConfig.locationString();
            Resources.log(errMsg);
            throw new ResourceException(id, errMsg);
        }+/
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
        return mContext.resource_id ~ "::" ~ id;
    }
}

//special resource type for aliases
//it is a hack and requires special handling: an alias resource won't return the
//  aliased resource (it returns only a meaningless dummy object); instead
//  aliases are resolved when the resources are added to the ResourceSet in
//  addToResourceSet
private class AliasResource : ResourceItem {
    char[] alias_name;

    this(ResourceFile context, char[] id, ConfigNode item) {
        super(context, id, item);
        alias_name = item.getCurValue!(char[])();
    }

    protected void load() {
        //set dummy; not that having null as content breaks
        mContents = new Object();
    }

    static this() {
        Resources.registerResourceType!(typeof(this))("aliases");
    }
}

void addToResourceSet(ResourceSet rs, ResourceItem[] items) {
    struct Entry {
        char[] res, new_name;
    }

    Entry[] aliases;

    foreach (ResourceItem i; items) {
        if (auto al = cast(AliasResource)i) {
            aliases ~= Entry(al.alias_name, al.id);
            continue;
        }
        rs.addResource(i.get, i.id);
    }

    //aliases are done after all stuff is added to avoid forward ref issues
    foreach (e; aliases) {
        //rs.addResource(rs.get!(Object)(e.res), e.new_name);
        rs.addAlias(e.res, e.new_name);
    }
}

alias void delegate(int cur, int total) ResourceLoadProgress;

class ResourceFile {
    private {
        bool loading = true;
        char[] resource_id; //mostly the filename, but see loadResources()
        char[] filepath; //path where the resource files are
        ResourceFile[] requires;
        ResourceItem[] resources;
    }

    private this(char[] id, char[] path) {
        resource_id = id;
        filepath = path;
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
        throw new ResourceException(id, "resource not found");
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

//lol, another global singleton
Resources gResources;

static this() {
    gResources = new Resources();
}

///the resource manager
///this centrally manages all loaded resources; for accessing resources, use
///ResourceSet from module common.resset
public class Resources {
    static Log log;
    private ResourceFile[char[]] mLoadedResourceFiles;

    private alias StaticFactory!("Ressoures", ResourceItem, ResourceFile,
        char[], ConfigNode) ResFactory;

    this() {
        log = registerLog("Res");
    }

    debug {
        struct LoadStat {
            int count;
            Time time;
            bool timing;
            Time last_time;
        }
        LoadStat[char[]] mLoadingStats;

        LoadStat* ls_get(T)(T x) {
            char[] k = myformat("{}", x);
            if (auto p = k in mLoadingStats)
                return p;
            mLoadingStats[k] = LoadStat.init;
            return k in mLoadingStats;
        }
        void ls_start(T)(T x, bool inc = true) {
            auto ls = ls_get(x);
            assert(!ls.timing);
            ls.timing = true;
            ls.last_time = timeCurrentTime();
            if (inc)
                ls_inc(x);
        }
        void ls_stop(T)(T x) {
            auto ls = ls_get(x);
            assert(ls.timing);
            ls.timing = false;
            ls.time += timeCurrentTime() - ls.last_time;
        }
        void ls_inc(T)(T x) {
            auto ls = ls_get(x);
            ls.count++;
        }
        void showStats() {
            auto outp = registerLog("resource_stats");
            outp("Loading stats:");
            foreach (char[] k, ref LoadStat s; mLoadingStats) {
                assert(!s.timing);
                outp("  {}: x{} sum={}", k, s.count, s.time);
            }
            outp("done.");
            mLoadingStats = null;
        }
    }

    ///register a class derived from Resource for the internal factory under
    ///the given name
    ///the class T to register must have this constructor:
    ///     this(Resources parent, char[] name, ConfigNode from)
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
        ConfigNode it)
    {
        return ResFactory.instantiate(type,context,it.name,it);
    }

    const cResourcePathName = "resource_path";

    ///load a resource file and add them to dest
    ///config itself or any parent must contain a value named "resource_path"
    ///(Resources.cResourcePathName) which contains the full path to the
    ///configfile (meh, probably bring back the old hack in configfile.d)
    ///also, the following nodes from config are read:
    ///"resources" nodes contain real resources; if they weren't loaded yet, new
    ///     ResourceItems are created for them so you can actually load them
    ///"require_resources" nodes lead to recursive loading of other files which
    ///     are loaded with loadResources(); using the "fixed" path
    ///the function returns an object with has the getAll() method to get all
    ///resources which were found in that file (including dependencies).
    public ResourceFile loadResources(ConfigNode config) {
        assert(!!config);

        //find the path value
        auto parent = config;
        while (parent && !parent.findNode(cResourcePathName)) {
            parent = parent.parent();
        }

        if (!parent) {
            throw new LoadException("?", "not a resource configfile");
        }

        char[] filepath = parent[cResourcePathName];
        //xxx: possibly normalize the filepath here!
        auto path = getFilePath(filepath);
        //for root-dir filenames like "bla.conf"
        if (path == "")
            path = "/";

        if (!gFS.pathExists(path)) {
            throw new LoadException(filepath, "loadResources(): bad parameters");
        }

        //create a ConfigNode path to have a unique ID for this resource section
        //(when several resource sections are in one file)
        char[] config_path = "/";
        auto cur = config;
        while (cur !is parent) {
            assert(!!cur);
            config_path ~= cur.name ~ "/";
            cur = cur.parent;
        }

        //arbitrary but for this resource file/section unique ID
        auto id = filepath ~ '#' ~ config_path;

        if (id in mLoadedResourceFiles) {
            auto f = mLoadedResourceFiles[id];
            if (f.loading) {
                assert(false, "is dat sum circular dependency?");
            }
            return f;
        }

        auto res = new ResourceFile(id, path);
        mLoadedResourceFiles[res.resource_id] = res;

        try {

            foreach (char[] name, char[] value;
                config.getSubNode("require_resources"))
            {
                res.requires ~= loadResources(res.fixPath(value));
            }

            foreach (ConfigNode r; config.getSubNode("resources")) {
                auto type = r.name;
                foreach (ConfigNode i; r) {
                    res.resources ~= createResource(res, type, i);
                }
            }

        } catch (LoadException e) {
            //roll back; delete the file
            //because there are no circular references, recursively loaded files
            //are either loaded OK, or will be removed recursively
            mLoadedResourceFiles.remove(res.resource_id);
            throw e;
        }

        res.loading = false;

        return res;
    }

    public bool isResourceFile(ConfigNode config) {
        if (!config) {
            return false;
        }
        auto parent = config;
        while (parent && !parent.findNode(cResourcePathName)) {
            parent = parent.parent();
        }
        return !!parent;
    }

    ///provided for simplicity
    public ResourceFile loadResources(char[] conffile) {
        return loadResources(loadConfigForRes(conffile));
    }

    ///also just for simplicity
    public static ConfigNode loadConfigForRes(char[] path) {
        ConfigNode config = loadConfig(path, true);
        config[cResourcePathName] = path;
        return config;
    }

    ///just for convenience
    ///config needs to fulfil the same requirements as in loadResources()
    public ResourceSet loadResSet(ConfigNode config) {
        auto res = loadResources(config).getAll();
        preloadAll(res);
        auto ret = new ResourceSet();
        addToResourceSet(ret, res);
        return ret;
    }

    //meh
    public ResourceSet loadResSet(char[] file) {
        return loadResSet(loadConfigForRes(file));
    }

    public Preloader createPreloader(ResourceItem[] list) {
        return new Preloader(list);
    }

    public Preloader createPreloader(ResourceFile[] files) {
        return new Preloader(files);
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
        private LoadException mError; //error state
        private PerfTimer mTime;

        this(ResourceItem[] list) {
            doload(list);
        }

        private void doload(ResourceItem[] list) {
            mTime = new PerfTimer(true);
            log("Preloading {} resources", list.length);

            mToLoad = list.dup;
        }

        this(ResourceFile[] files) {
            ResourceItem[] rilist;
            foreach (file; files) {
                rilist ~= file.getAll();
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
            return !mError && loadedCount >= totalCount;
        }

        /+ ///if there was a loader error, throw the catched exception
        ///(always of type LoadException)
        void checkError() {
            if (mError)
                throw mError;
        }+/

        ///load count-many resources
        void progressSteps(int count) {
            while (count-- > 0 && !done && !mError) {
                try {
                    mTime.start();
                    scope(exit) mTime.stop();
                    mToLoad[mCurrent].get();
                } catch (LoadException e) {
                    //remember error, throw it anyway
                    mError = e;
                    throw e;
                }
                mCurrent++;
                if (done) {
                    //still check for maybe newly created resources
                    //(normally shouldn't happen, but it's simple to handle it)
                    //updateToLoad();

                    if (done)
                        log("Finished preloading, time="~mTime.time.toString());
                }
            }
        }

        ///load as much stuff as possible, but return if time was exceeded
        ///this is useful to i.e. update the screen while loading
        void progressTimed(Time return_after) {
            Time start = timeCurrentTime;
            while (!done && timeCurrentTime() - start <= return_after
                && !mError)
            {
                progressSteps(1);
            }
        }

        ///load everything in one go, no incremental loading (old behaviour)
        void loadAll(ResourceLoadProgress progress = null) {
            while (!done && !mError) {
                progressSteps(1);
                if (progress)
                    progress(loadedCount, totalCount);
            }
        }
    }

    ///release all resources (which means the resource is left to the GC)
    ///this means if a resource isn't GCed, reloading it next time will
    ///actually duplicate it
    void unloadAll() {
        mLoadedResourceFiles = null; //blergh
    }
}
