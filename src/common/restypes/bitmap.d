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
        auto bmp = gFramework.loadImage(mContext.fixPath(mConfig.value));
        bmp.preload();
        mContents = bmp;
    }

    static this() {
        Resources.registerResourceType!(typeof(this))("bitmaps");
    }
}
