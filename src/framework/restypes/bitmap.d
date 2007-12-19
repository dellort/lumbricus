module framework.restypes.bitmap;

import framework.framework;
import framework.resources;
import utils.configfile;

///Resource class for bitmaps
protected class BitmapResource : ResourceBase!(Surface) {
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
        mContents = gFramework.loadImage(fn);
    }

    override protected void doUnload() {
        //if (mContents)
        //    mContents.free();
        mContents = null; //let the GC do the work
        super.doUnload();
    }

    static this() {
        ResFactory.register!(typeof(this))("bitmaps");
        setResourceNamespace!(typeof(this))("bitmap");
    }
}
