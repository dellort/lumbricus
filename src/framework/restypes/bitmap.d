module framework.restypes.bitmap;

import framework.framework;
import framework.resources;
import utils.configfile;

///Resource class for bitmaps
protected class BitmapResource : ResourceItem {
    this(ResourceFile context, char[] id, ConfigItem item) {
        super(context, id, item);
    }

    protected void load() {
        ConfigValue val = cast(ConfigValue)mConfig;
        assert(val !is null);
        mContents = gFramework.loadImage(mContext.fixPath(val.value));
    }

    static this() {
        Resources.registerResourceType!(typeof(this))("bitmaps");
    }
}
