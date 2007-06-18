module game.resources;

import framework.framework;
import game.common;
import str = std.string;
import utils.configfile;
import utils.log;
import utils.output;

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

    package this(Resources parent, char[] id) {
        mParent = parent;
        this.id = id;
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

alias Resource!(Surface) BitmapResource;

//import here to not to have forward reference to BitmapResource in animation.d!
import game.animation;
alias Resource!(Animation) AnimationResource;

///the resource manager
///currently manages:
///  - bitmap (Surface)
///  - animations (Animation)
public class Resources {
    private AnimationResource[char[]] mAnimations;
    private BitmapResource[char[]] mBitmaps;
    private Log log;
    private bool[char[]] mLoadedAnimationConfigFiles;

    this() {
        log = registerLog("Res");
        //log.setBackend(DevNullOutput.output, "null");
    }

    ///create new animation resource from a ConfigNode containing animation
    ///infos
    ///store resource at id for later use
    public AnimationResource createAnimation(ConfigNode node, char[] id,
        char[] relPath = "", bool allowFail = false)
    {
        assert(id != "","createAnimation with empty id");
        if (id in mAnimations) {
            //animation has already been loaded
            return anims(id, allowFail);
        }
        //haha
        ConfigNode animData = node;
        AnimationResource r = new AnimationResourceImpl(this,id,relPath,
            animData);
        mAnimations[id] = r;
        return r;
    }

    //cutnpaste from above
    public BitmapResource createProcessedBitmap(char[] sourceId,
        char[] id, bool mirroredY, bool allowFail = false)
    {
        assert(id != "","createProcessedBitmap with empty id");
        if (id in mBitmaps) {
            return bitmaps(id, allowFail);
        }
        BitmapResource r = new BitmapResourceProcessed(this, id, sourceId,
            mirroredY);
        mBitmaps[id] = r;
        return r;
    }

    ///retrieve an animation resource by id
    public AnimationResource anims(char[] id, bool allowFail = false) {
        assert(id != "","anims with empty id");
        AnimationResource* r = id in mAnimations;
        if (!r) {
            char[] errMsg = "Animation "~id~" not loaded";
            log(errMsg);
            if (!allowFail)
                throw new ResourceException(errMsg);
            return null;
        } else {
            return *r;
        }
    }

    public AnimationResource animsMaybe(char[] id) {
        if (!id.length)
            return null;
        return anims(id);
    }

    ///create new bitmap resource from a graphics file
    ///store resource at id for later use
    public BitmapResource createBitmap(char[] imgPath, char[] id,
        char[] relPath = "", bool allowFail = false)
    {
        assert(id != "","createBitmap with empty id");
        if (id in mBitmaps) {
            //animation has already been loaded
            return bitmaps(id, allowFail);
        }
        BitmapResource r = new BitmapResourceImpl(this,id,relPath,
            imgPath);
        mBitmaps[id] = r;
        return r;
    }

    ///retrieve a bitmap resource by id
    public BitmapResource bitmaps(char[] id, bool allowFail = false) {
        assert(id != "","bitmaps with empty id");
        BitmapResource* r = id in mBitmaps;
        if (!r) {
            char[] errMsg = "Bitmap "~id~" not loaded";
            log(errMsg);
            if (!allowFail)
                throw new ResourceException(errMsg);
            return null;
        } else {
            return *r;
        }
    }

    ///preload all cached resources from disk
    ///Attention: this will load really ALL resources, not just needed ones
    //xxx add progress callback
    public void preloadAll() {
        foreach (aniRes; mAnimations) {
            aniRes.get();
        }
        foreach (bmpRes; mBitmaps) {
            bmpRes.get();
        }
    }

    //load animations as requested in "item"
    //currently, item shall be a ConfigValue which contains the configfile name
    //note that this name shouldn't contain a ".conf", argh.
    //also can be an animation configfile directly
    void loadAnimations(ConfigItem item) {
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
                loadAnimations(cfg);
            }
            return;
        } else if (cast(ConfigNode)item) {
            cfg = cast(ConfigNode)item;
        } else {
            assert(false);
        }

        assert(cfg !is null);

        auto load_further = cfg.find("require_animations");
        if (load_further !is null) {
            //xxx: should try to prevent possible recursion
            loadAnimations(load_further);
        }

        //load new introduced animations (not really load them themselves...)
        foreach (char[] name, ConfigNode node; cfg.getSubNode("animations")) {
            createAnimation(node, name, "", true);
        }

        //add aliases
        foreach (char[] name, char[] value;
            cfg.getSubNode("animation_aliases"))
        {
            AnimationResource aliased = anims(value, true);
            if (!aliased) {
                log("WARNING: alias '%s' not found", value);
                continue;
            }
            if (anims(name, true)) {
                char[] errMsg = "WARNING: alias target '"~name~"' already exists";
                log(errMsg);
                continue;
            }
            mAnimations[name] = aliased;
        }
    }
}

///Resource class that holds an animation loaded from a config node
protected class AnimationResourceImpl : AnimationResource {
    private ConfigNode mAnimData;
    protected char[] mRelativePath;

    this(Resources parent, char[] id, char[] relPath, ConfigNode animData) {
        super(parent, id);
        mRelativePath = relPath;
        mAnimData = animData;
    }

    protected void load() {
        mParent.log("Load animation %s",id);
        //wtf is mRelativePath? not used here.
        //NOTE: creating an animation shouldn't cost too much
        //  Animation now loads bitmaps lazily
        //  (it uses BitmapResource and BitmapResourceProcessed)
        mContents = loadAnimation(mAnimData);
    }
}

protected class BitmapResourceProcessed : BitmapResource {
    private bool mMirroredY;
    private char[] mSourceId;

    this(Resources parent, char[] id, char[] sourceId,
        bool mirroredY)
    {
        super(parent, id);
        mMirroredY = mirroredY;
        mSourceId = sourceId;
    }

    protected void load() {
        BitmapResource src = mParent.bitmaps(mSourceId);
        if (mMirroredY) {
            mContents = src.get().createMirroredY();
        }
    }
}

///Resource class for bitmaps
protected class BitmapResourceImpl : BitmapResource {
    protected char[] mRelativePath;
    protected char[] mGraphicFile;

    this(Resources parent, char[] id, char[] relPath, char[] graphicFile) {
        super(parent, id);
        mRelativePath = relPath;
        mGraphicFile = graphicFile;
    }

    protected void load() {
        mContents = globals.loadGraphic(mGraphicFile);
    }
}

class ResourceException : Exception {
    this(char[] msg) {
        super(msg);
    }
}
