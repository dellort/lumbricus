module common.restypes.sound;

import common.resources;
import framework.framework;
import framework.sound;
import utils.configfile;
import utils.misc;
import utils.stream;

class SampleResource : ResourceItem {
    this(ResourceFile context, char[] id, ConfigNode item) {
        super(context, id, item);
    }

    protected void load() {
        char[] path = mContext.fixPath(mConfig.value);
        Sample sample;
        try {
            //xxx lol etc.
            SoundType type;
            if (mConfig.parent.name == "samples") {
                type = SoundType.sfx;
            } else {
                //music is streamed
                type = SoundType.music;
            }
            sample = gSoundManager.createSample(path, type);
        } catch (CustomException e) {
            loadError(e);
            //try to load some default
            sample = gSoundManager.createSample("empty.wav", SoundType.sfx);
        }
        assert(!!sample);
        sample.preload();
        mContents = sample;
    }

    static this() {
        Resources.registerResourceType!(typeof(this))("samples");
        Resources.registerResourceType!(typeof(this))("music");
    }
}
