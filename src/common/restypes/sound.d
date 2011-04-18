module common.restypes.sound;

import common.resources;
import framework.main;
import framework.sound;
import utils.configfile;
import utils.misc;
import utils.stream;

class SampleResource : ResourceItem {
    SoundType type;
    string path;

    this(ResourceFile context, string id, ConfigNode item) {
        super(context, id, item);

        //xxx lol etc.
        if (mConfig.parent.name == "samples") {
            type = SoundType.sfx;
        } else {
            //music is streamed
            type = SoundType.music;
        }

        path = mContext.fixPath(mConfig.value);
    }

    this(ResourceFile context, string id, SoundType a_type, string a_path) {
        super(context, id, null);
        type = a_type;
        path = a_path;
    }

    protected void load() {
        Sample sample;
        try {

            sample = gSoundManager.createSample(path, type);
        } catch (CustomException e) {
            loadError(e);
            //try to load some default
            sample = gSoundManager.createSample("empty.wav", SoundType.sfx);
        }
        assert(!!sample);
        gFramework.preloadResource(sample);
        mContents = sample;
    }

    static this() {
        Resources.registerResourceType!(typeof(this))("samples");
        Resources.registerResourceType!(typeof(this))("music");
    }
}
