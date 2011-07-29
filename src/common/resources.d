module common.resources;

import framework.config;
import framework.filesystem;
import utils.configfile;
import utils.log;
import utils.misc;
import utils.factory;
import utils.time;
import utils.path;
import utils.perf;

import common.resset;

//ConfigNode = the node under load_hacks
//ResourceFile = file operating in
alias void delegate(ConfigNode, ResourceFile) ResLoadHackDg;
ResLoadHackDg[string] gResLoadHacks;

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
    string id;

    //error reporting?
    string fallbackLocation = "?";

    protected {
        Object mContents;
        ResourceFile mContext;
        ConfigNode mConfig;
    }

    final bool isLoaded() {
        return !!mContents;
    }

    string location() {
        return mConfig ? mConfig.locationString() : fallbackLocation;
    }

    //only available before preload() is done
    protected ConfigNode config() {
        return mConfig;
    }

    package this(ResourceFile context, string id, ConfigNode item)
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
        //already loaded?
        if (mContents)
            return;
        try {
            Resources.log("Loading resource "~id);
            load();
            assert(!!mContents, "was not loaded?");
            //save a little bit of memory
            mConfig = null;
        } catch (CustomException e) {
            string errMsg = "Resource " ~ id ~ " (" ~ toString()
                ~ ") failed to load: "~e.toString~"  - location: "
                ~ location();
            Resources.log(errMsg);
            //xxx destroys backtrace, should use Exception.next member
            throw new ResourceException(id, errMsg);
        }
    }

    ///destroy contents and make resource reload on next use
    package void invalidate() {
        if (mContents)
            doUnload();
    }

    ///implement this to actually load the data
    ///store result in mContents, throw exception on error
    abstract protected void load();

    protected void doUnload() {
        mContents = null; //let the GC do the work
    }

    string fullname() {
        return mContext.resource_id ~ "::" ~ id;
    }

    //display non-fatal load error (non-fatal as in, we can continue with a
    //  dummy replacement, such as an error graphic for bitmaps)
    void loadError(T...)(string fmt, T args) {
        Resources.log.error("Loading resource '%s' specified in %s failed: %s",
            id, location(), myformat(fmt, args));
    }
    void loadError()(CustomException e) {
        loadError("%s", e);
    }
}

class PseudoResource : ResourceItem {
    this(ResourceFile context, string id, Object obj) {
        super(context, id, null);
        mContents = obj;
    }

    //lol.
    override void load() {
    }
}

//special resource type for aliases
//it is a hack and requires special handling: an alias resource won't return the
//  aliased resource (it returns only a meaningless dummy object); instead
//  aliases are resolved when the resources are added to the ResourceSet in
//  addToResourceSet
private class AliasResource : ResourceItem {
    string alias_name;

    this(ResourceFile context, string id, ConfigNode item) {
        super(context, id, item);
        alias_name = item.getCurValue!(string)();
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
        string res, new_name;
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
        string resource_id; //mostly the filename, but see loadResources()
        string filepath; //path where the resource files are
        ResourceFile[] requires;
        ResourceItem[] resources;
    }

    private this(string id, string path) {
        resource_id = id;
        filepath = path;
    }

    //add an already loaded object as resource and work around the usual
    //  loading mechanism
    void addPseudoResource(string name, Object obj) {
        resources ~= new PseudoResource(this, name, obj);
    }

    void addResource(ResourceItem res) {
        resources ~= res;
    }

    //correct loading of relative files
    public string fixPath(string orgVal) {
        if (orgVal.length == 0)
            return orgVal;
        if (orgVal[0] == '/')
            return orgVal;
        return filepath ~ orgVal;
    }

    //this is for resources which are refered by other resources
    //obviously only works within a resource file, from now on
    //NOTE: infinitely slow; if needed rewrite it
    ResourceItem find(string id) {
        foreach (i; getAll()) {
            if (i.id == id) {
                return i;
            }
        }
        throw new ResourceException(id, "resource not found");
    }

    //like cast(T)(find(id).get())
    //throws an exception if the result has the wrong type
    T findAndGetT(T)(string id) {
        T res = cast(T)(find(id).get());
        if (!res)
            throw new ResourceException(id, "resource has wrong type");
        return res;
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
    private ResourceFile[string] mLoadedResourceFiles;

    private alias StaticFactory!("Ressoures", ResourceItem, ResourceFile,
        string, ConfigNode) ResFactory;

    this() {
        log = registerLog("resources");
    }

    ///register a class derived from Resource for the internal factory under
    ///the given name
    ///the class T to register must have this constructor:
    ///     this(Resources parent, string name, ConfigNode from)
    ///else compilation will fail somewhere in factory.d
    static void registerResourceType(T : ResourceItem)(string name) {
        ResFactory.register!(T)(name);
    }

    //"fullname" is the resource ID, prefixed by the filename
    void enumResources(scope void delegate(string fullname, ResourceItem res) cb) {
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
    private ResourceItem createResource(ResourceFile context, string type,
        ConfigNode it)
    {
        try {
            return ResFactory.instantiate(type,context,it.name,it);
        } catch (ClassNotFoundException e) {
            throwError("when loading resource in '%s': resource type '%s'"
                " unknown", it.locationString, type);
            assert(false);
        }
    }

    enum cResourcePathName = "resource_path";

    ///load a resource file and add them to dest
    ///config itself or any parent must contain a value named "resource_path"
    ///(Resources.cResourcePathName) which contains the full filename to the
    ///configfile (meh, probably bring back the old hack in configfile.d)
    ///also, the following nodes from config are read:
    ///"resources" nodes contain real resources; if they weren't loaded yet, new
    ///     ResourceItems are created for them so you can actually load them
    ///"require_resources" nodes lead to recursive loading of other files which
    ///     are loaded with loadResources(); using the "fixed" path
    ///the function returns an object with has the getAll() method to get all
    ///resources which were found in that file (including dependencies).
    public ResourceFile loadResources(ConfigNode config, bool virtual = false) {
        assert(!!config);

        //find the path value
        auto parent = config;
        while (parent && !parent.findNode(cResourcePathName)) {
            parent = parent.parent();
        }

        if (!parent)
            throwError("not a resource file: %s", config.locationString());

        //using VFSPath will normalize the path too (includes adding a separator
        //  as first element of the path: "bla.conf" => "/bla.conf")
        //xxx: VFSPath will throw exceptions in invalid paths; should try to
        //  put these exceptions "in context" (so that the user know where the
        //  path came from, e.g. which resource file / config node)
        auto filepath = VFSPath(parent[cResourcePathName]);
        auto path = filepath.path();

        if (!virtual && !gFS.pathExists(path)) {
            throwError("resource file %s contains invalid path: %s",
                config.locationString(), path);
        }

        //create a ConfigNode path to have a unique ID for this resource section
        //(when several resource sections are in one file)
        string config_path = "/";
        auto cur = config;
        while (cur !is parent) {
            assert(!!cur);
            config_path ~= cur.name ~ "/";
            cur = cur.parent;
        }

        //arbitrary but for this resource file/section unique ID
        auto id = filepath.get() ~ '#' ~ config_path;

        log.trace("loading resource file '%s'", id);

        try {
            processIncludes(config, path);
        } catch (CustomException e) {
            log.trace("error loading includes for resource file '%s'", id);
        }

        if (auto file = id in mLoadedResourceFiles) {
            if (file.loading) {
                //don't know which file caused this; still try to be of help
                string[] offenders;
                foreach (string o_id, o_file; mLoadedResourceFiles) {
                    if (o_file.loading && o_id != id)
                        offenders ~= o_id;
                }
                throwError("circular dependency when loading resource file '%s'"
                    ", possible offenders: %s", id, offenders);
            }
            return *file;
        }

        auto res = new ResourceFile(id, path);
        mLoadedResourceFiles[res.resource_id] = res;

        //xxx I would prefer to filter this on CustomException, not Exception
        scope(failure) {
            //roll back; delete the file
            //because there are no circular references, recursively loaded files
            //are either loaded OK, or will be removed recursively
            mLoadedResourceFiles.remove(res.resource_id);
        }

        foreach (ConfigNode sub; config.getSubNode("load_hacks")) {
            auto cb = sub.name in gResLoadHacks;
            if (!cb) {
                throwError("error loading resource file '%s', can't load via"
                    " '%s'", id, sub.name);
            }
            try {
                (*cb)(sub, res);
            } catch (CustomException e) {
                e.msg = myformat("when loading '%s' via '%s': %s", id, sub.name,
                    e.msg);
                throw e;
            }
        }

        try {

            foreach (ConfigNode sub; config.getSubNode("require_resources")) {
                try {
                    res.requires ~= loadResources(res.fixPath(sub.value));
                } catch (CustomException e) {
                    e.msg = myformat("when loading '%s' from '%s': %s",
                        sub.value, sub.locationString, e.msg);
                    throw e;
                }
            }

            foreach (ConfigNode r; config.getSubNode("resources")) {
                auto type = r.name;
                foreach (ConfigNode i; r) {
                    res.resources ~= createResource(res, type, i);
                }
            }

        } catch (CustomException e) {
            log.trace("error loading resource file '%s'", id);
            throw e;
        }

        log.trace("done loading resource file '%s'", id);

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
    public ResourceFile loadResources(string conffile) {
        return loadResources(loadConfigForRes(conffile));
    }

    ///also just for simplicity
    public static ConfigNode loadConfigForRes(string path) {
        ConfigNode config = loadConfig(path);
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
    public ResourceSet loadResSet(string file) {
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
        private PerfTimer mTime;

        this(ResourceItem[] list) {
            doload(list);
        }

        private void doload(ResourceItem[] list) {
            mTime = new PerfTimer(true);
            log.minor("Preloading %s resources", list.length);

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
            return cast(int)(mOffset + mToLoad.length);
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
        ///error handling: ResourceItem.load should catch exceptions itself,
        /// and load a dummy object in case of errors
        ///=> this method shouldn't throw
        void progressSteps(int count) {
            while (count-- > 0 && !done) {
                mTime.start();
                scope (exit) mTime.stop();
                mToLoad[mCurrent].get();
                mCurrent++;
                if (done) {
                    //still check for maybe newly created resources
                    //(normally shouldn't happen, but it's simple to handle it)
                    //updateToLoad();

                    if (done)
                        log.minor("Finished preloading, time=%s",
                            mTime.time.toString());
                }
            }
        }

        ///load as much stuff as possible, but return if time was exceeded
        ///this is useful to i.e. update the screen while loading
        void progressTimed(Time return_after) {
            Time start = timeCurrentTime;
            while (!done && timeCurrentTime() - start <= return_after)
            {
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

    ///release all resources (which means the resource is left to the GC)
    ///this means if a resource isn't GCed, reloading it next time will
    ///actually duplicate it
    void unloadAll() {
        mLoadedResourceFiles = null; //blergh
    }
}

//process include directives of the form "include { "file1" "file2" }"
//the files are loaded from gFS, relative to the passed path
//the config nodes from the include files are merged into node itself
//for more half-assedness, includes aren't processed recursively
void processIncludes(ConfigNode node, string path) {
    string[] files = node.getValue!(string[])("include");
    foreach (f; files) {
        ConfigNode inc = loadConfig(path ~ "/" ~ f);
        node.mixinNode(inc);
    }
}
