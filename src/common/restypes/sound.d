module common.restypes.sound;

import common.resources;
import framework.framework;
import framework.sound;
import utils.stream;
import utils.configfile;

class SampleResource : ResourceItem {
    this(ResourceFile context, char[] id, ConfigNode item) {
        super(context, id, item);
    }

    protected void load() {
        char[] path = mContext.fixPath(mConfig.value);
        mContents = gFramework.sound.createSample(path);
    }

    static this() {
        Resources.registerResourceType!(typeof(this))("samples");
    }
}

class MusicResource : ResourceItem {
    this(ResourceFile context, char[] id, ConfigNode item) {
        super(context, id, item);
    }

    protected void load() {
        char[] path = mContext.fixPath(mConfig.value);
        mContents = gFramework.sound.createMusic(path);
    }

    static this() {
        Resources.registerResourceType!(typeof(this))("music");
    }
}
