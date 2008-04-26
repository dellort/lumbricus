module framework.restypes.sound;

import framework.resources;
import framework.filesystem;
import framework.framework;
import framework.sound;
import std.stream;
import utils.configfile;

class SampleResource : ResourceBase!(Sample) {
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
        Stream st = gFramework.fs.open(fn, FileMode.In);
        mContents = gFramework.sound.createSample(st);
    }

    static this() {
        ResFactory.register!(typeof(this))("samples");
        setResourceNamespace!(typeof(this))("sample");
    }
}

class MusicResource : ResourceBase!(Music) {
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
        Stream st = gFramework.fs.open(fn, FileMode.In);
        mContents = gFramework.sound.createMusic(st);
    }

    static this() {
        ResFactory.register!(typeof(this))("music");
        setResourceNamespace!(typeof(this))("music");
    }
}
