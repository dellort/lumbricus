module common.restypes.atlas;

import common.resfileformats;
import common.resources;
import framework.framework;
import framework.imgread;
import utils.configfile;
import utils.log;
import utils.misc;
import utils.vector2;

class Atlas {
    private {
        Surface[] mPages;
        FileAtlasTexture[] mTextures;
        SubSurface[] mTextureRefs;
        bool mErrorFlag;

        //the image is not game/graphicsset dependent, so this is ok (but ugly)
        static SubSurface mErrorImage;
    }

    private this() {
        if (!mErrorImage) {
            mErrorImage = loadImage("error.png").fullSubSurface();
        }
    }

    //create the SubSurfaces corresponding to the atlas parts
    private void load() {
        assert(mTextureRefs.length == 0);
        foreach (t; mTextures) {
            Surface s = mPages[t.page];
            mTextureRefs ~= s.createSubSurface(Rect2i.Span(t.x, t.y, t.w, t.h));
        }
    }

    final SubSurface texture(int index) {
        if (indexValid(mTextureRefs, index)) {
            return mTextureRefs[index];
        } else {
            if (!mErrorFlag) {
                //have fun tracking down the error cause
                gLog.error("invalid index in atlas");
                mErrorFlag = true;
            }
            return mErrorImage;
        }
    }

    int count() {
        return mTextures.length;
    }
}

class AtlasResource : ResourceItem {
    this(ResourceFile context, char[] id, ConfigNode item) {
        super(context, id, item);
    }

    protected void load() {
        try {
            doLoad();
        } catch (CustomException e) {
            loadError(e);
            auto dummy = new Atlas();
            dummy.mErrorFlag = true;
            mContents = dummy;
        }
    }

    private void doLoad() {
        auto node = mConfig;
        auto atlas = new Atlas();

        foreach (char[] key, char[] value; node.getSubNode("pages")) {
            auto img = loadImage(mContext.fixPath(value));
            gFramework.preloadResource(img);
            atlas.mPages ~= img;
        }

        FileAtlasTexture[] textures;
        auto meta = node.getSubNode("meta");
        //meta data is read from a binary file
        scope f = gFS.open(mContext.fixPath(meta.value));
        scope(exit) f.close();
        //xxx I shouldn't load stuff directly (endian issues), but who cares?
        FileAtlas header;
        f.readExact(cast(ubyte[])(&header)[0..1]);
        textures.length = header.textureCount;
        f.readExact(cast(ubyte[])textures);
        atlas.mTextures = textures;

        atlas.load();

        mContents = atlas;
    }

    static this() {
        Resources.registerResourceType!(typeof(this))("atlas");
    }
}
