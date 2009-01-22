module framework.restypes.sound;

import framework.resources;
import framework.filesystem;
import framework.framework;
import framework.sound;
import stdx.stream;
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
