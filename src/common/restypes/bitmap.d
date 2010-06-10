module common.restypes.bitmap;

import framework.framework;
import common.resources;
import utils.configfile;
import utils.misc;

///Resource class for bitmaps
protected class BitmapResource : ResourceItem {
    this(ResourceFile context, char[] id, ConfigNode item) {
        super(context, id, item);
    }

    protected void load() {
        Surface bmp;
        try {
            bmp = gFramework.loadImage(mContext.fixPath(mConfig.value));
        } catch (CustomException e) {
            loadError(e);
            bmp = gFramework.loadImage("error.png");
        }
        bmp.preload();
        mContents = bmp;
    }

    static this() {
        Resources.registerResourceType!(typeof(this))("bitmaps");
    }
}
