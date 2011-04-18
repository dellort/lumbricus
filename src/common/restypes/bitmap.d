module common.restypes.bitmap;

import framework.imgread;
import framework.surface;
import framework.main;
import common.resources;
import utils.configfile;
import utils.misc;

///Resource class for bitmaps
protected class BitmapResource : ResourceItem {
    this(ResourceFile context, string id, ConfigNode item) {
        super(context, id, item);
    }

    protected void load() {
        Surface bmp;
        try {
            bmp = loadImage(mContext.fixPath(mConfig.value));
        } catch (CustomException e) {
            loadError(e);
            bmp = loadImage("error.png");
        }
        gFramework.preloadResource(bmp);
        mContents = bmp;
    }

    static this() {
        Resources.registerResourceType!(typeof(this))("bitmaps");
    }
}
