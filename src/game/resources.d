module game.resources;

import framework.framework;
import framework.filesystem;
import game.common;
import game.animation;
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
protected class Resource(T) {
    ///unique id of resource
    char[] id;
    ///unique numeric id
    ///useful for networking, has the same meaning across all nodes
    ///yyy actually initialize it etc.
    int uid;

    private T mContents;
    private bool mValid = false;
    private Resources mParent;
    private ConfigItem mConfig;

    package this(Resources parent, char[] id, ConfigItem item)
    {
        mParent = parent;
        this.id = id;
        mConfig = item;
    }

    ///get the contents of this resource
    ///allowFail to ignore load errors (not recommended)
    T get(bool allowFail = false) {
        if (!mValid)
            preload(allowFail);
        return mContents;
    }

    //preloads the resource from disk, allowFail controls if an exception
    //is thrown on error
    package void preload(bool allowFail = false) {
        try {
            load();
            mValid = true;
        } catch (Exception e) {
            char[] errMsg = toString() ~ " failed to load: "~e.msg;
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
}

///the resource manager
///currently manages:
///  - bitmap (Surface)
///  - animations (Animation)
public class Resources {
    private Object[char[]] mResources;
    private Log log;
    private bool[char[]] mLoadedAnimationConfigFiles;
    private bool[char[]] mResourceRefs;

    this() {
        log = registerLog("Res");
        //log.setBackend(DevNullOutput.output, "null");
    }

    private void createResource(char[] type, ConfigItem it,
        bool allowFail = false, char[] id = "")
    {
        ConfigNode n = cast(ConfigNode)it;
        if (!n)
            n = it.parent;
        if (id.length == 0)
            id = n.filePath~it.name;
        if (!(id in mResources)) {
            log("Create(%s): %s",type,id);
            Object r = ResFactory.instantiate(type,this,id,it);
            mResources[id] = r;
        }
    }

    ///hacky: create a resource from a plain filename (only for resources
    ///supporting it, currently just BitmapResource)
    ///id will be the filename
    public T createResourceFromFile(T)(char[] filename,
        bool allowFail = false)
    {
        char[] id = filename;
        if (!(id in mResources)) {
            ConfigValue v = new ConfigValue;
            v.value = filename;
            Object r = new T(this,id,v);
            mResources[id] = r;
        }
        return resource!(T)(id,allowFail);
    }

    ///get a reference to a resource by its id
    public T resource(T)(char[] id, bool allowFail = false) {
        assert(id != "","resource with empty id");
        Object* r = id in mResources;
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
        mResourceRefs[ret.id] = true;
        return ret;
    }

    ///preload all cached resources from disk
    ///Attention: this will load really ALL resources, not just needed ones
    //xxx add progress callback
    public void preloadAll() {
        foreach (char[] id, bool tmp; mResourceRefs) {
            std.stdio.writefln("Ref: %s",id);
        }
        /*foreach (aniRes; mAnimations) {
            aniRes.get();
        }
        foreach (bmpRes; mBitmaps) {
            bmpRes.get();
        }*/
    }

    //load animations as requested in "item"
    //currently, item shall be a ConfigValue which contains the configfile name
    //note that this name shouldn't contain a ".conf", argh.
    //also can be an animation configfile directly
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
                if (file in mLoadedAnimationConfigFiles)
                    continue;

                mLoadedAnimationConfigFiles[file] = true;
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

        //load new introduced animations (not really load them themselves...)
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
            Object* aliased = value in mResources;
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
            //std.stdio.writefln("Alias: %s -> %s",aliasNode.filePath
            //    ~ name,value);
            mResources[aliasNode.filePath ~ name] = *aliased;
        }
    }
}

///Resource class that holds an animation loaded from a config node
protected class AnimationResource : Resource!(Animation) {
    private ProcessedAnimationData mAniData;

    this(Resources parent, char[] id, ConfigItem item) {
        super(parent, id, item);
        mAniData = parseAnimation(cast(ConfigNode)item);
    }

    protected void load() {
        mParent.log("Load animation %s",id);
        //wtf is mRelativePath? not used here.
        //NOTE: creating an animation shouldn't cost too much
        //  Animation now loads bitmaps lazily
        //  (it uses BitmapResource and BitmapResourceProcessed)
        mContents = loadAnimation(mAniData);
    }

    static this() {
        ResFactory.register!(typeof(this))("animations");
    }
}

protected class BitmapResourceProcessed : BitmapResource {
    char[] mSrcId;
    this(Resources parent, char[] id, ConfigItem item)
    {
        super(parent, id, item);
        mSrcId = (cast(ConfigNode)item).getStringValue("id");
        assert(mSrcId != id);
    }

    protected void load() {
        BitmapResource src = mParent.resource!(BitmapResource)(mSrcId);
        mContents = src.get().createMirroredY();
    }

    static this() {
        ResFactory.register!(typeof(this))("bitmaps_processed");
    }
}

///Resource class for bitmaps
protected class BitmapResource : Resource!(Surface) {
    this(Resources parent, char[] id, ConfigItem item) {
        super(parent, id, item);
    }

    protected void load() {
        ConfigValue val = cast(ConfigValue)mConfig;
        assert(val !is null);
        char[] fn;
        if (mConfig.parent)
            fn = val.parent.getPathValue(val.name);
        else
            fn = val.value;
        mContents = globals.loadGraphic(fn);
    }

    BitmapResource createMirror() {
        //xxx hack to pass parameters to BitmapResourceProcessed
        ConfigNode n = new ConfigNode();
        char[] newid = id~"mirrored";
        n.setStringValue("id",id);
        mParent.createResource("bitmaps_processed",n,false,newid);
        return mParent.resource!(BitmapResource)(newid);
    }

    static this() {
        ResFactory.register!(typeof(this))("bitmaps");
    }
}

class ResourceException : Exception {
    this(char[] msg) {
        super(msg);
    }
}

static class ResFactory : StaticFactory!(Object, Resources, char[], ConfigItem)
{
}

static this() {
    initAnimations();
}
