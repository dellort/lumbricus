module framework.restypes.sound;

import framework.resources;
import framework.filesystem;
import framework.framework;
import framework.sound;
import std.stream;
import utils.configfile;

class SampleResource : ResourceItem {
    this(ResourceFile context, char[] id, ConfigItem item) {
        super(context, id, item);
    }

    protected void load() {
        ConfigValue val = cast(ConfigValue)mConfig;
        assert(val !is null);
        char[] path = mContext.fixPath(val.value);
        mContents = gFramework.sound.createSample(path);
    }

    static this() {
        Resources.registerResourceType!(typeof(this))("samples");
    }
}

class MusicResource : ResourceItem {
    this(ResourceFile context, char[] id, ConfigItem item) {
        super(context, id, item);
    }

    protected void load() {
        ConfigValue val = cast(ConfigValue)mConfig;
        assert(val !is null);
        char[] path = mContext.fixPath(val.value);
        mContents = gFramework.sound.createMusic(path);
    }

    static this() {
        Resources.registerResourceType!(typeof(this))("music");
    }
}
