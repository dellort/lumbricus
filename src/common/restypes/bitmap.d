module common.restypes.bitmap;

import framework.framework;
import common.resources;
import utils.configfile;

///Resource class for bitmaps
protected class BitmapResource : ResourceItem {
    this(ResourceFile context, char[] id, ConfigNode item) {
        super(context, id, item);
    }

    protected void load() {
        mContents = gFramework.loadImage(mContext.fixPath(mConfig.value));
    }

    static this() {
        Resources.registerResourceType!(typeof(this))("bitmaps");
    }
}
