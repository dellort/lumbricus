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
        //xxx lol etc.
        if (mConfig.parent.name == "samples") {
            auto sample = gFramework.sound.createSample(path, 0);
            sample.preload();
            mContents = sample;
        } else {
            //music is streamed
            mContents = gFramework.sound.createSample(path, 1, true);
        }
    }

    static this() {
        Resources.registerResourceType!(typeof(this))("samples");
        Resources.registerResourceType!(typeof(this))("music");
    }
}
