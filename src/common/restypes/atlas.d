module common.restypes.atlas;

import common.resfileformats;
import common.resources;
import framework.framework;
import utils.configfile;
import utils.misc;
import utils.vector2;

class Atlas {
    private {
        Surface[] mPages;
        FileAtlasTexture[] mTextures;
        SubSurface[] mTextureRefs;
    }

    private this() {
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
        if (indexValid(mTextureRefs, index))
            return mTextureRefs[index];
        else
            return null;
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
            mContents = new Atlas(); //dummy
        }
    }

    private void doLoad() {
        auto node = mConfig;
        auto atlas = new Atlas();

        foreach (char[] key, char[] value; node.getSubNode("pages")) {
            auto img = gFramework.loadImage(mContext.fixPath(value));
            img.preload();
            atlas.mPages ~= img;
        }

        FileAtlasTexture[] textures;
        auto meta = node.getSubNode("meta");
        if (meta.hasSubNodes()) {
            //meta node contains a list of strings with texture information
            foreach (char[] dummy, char[] metav; meta) {
                textures ~= FileAtlasTexture.parseString(metav);
            }
        } else {
            //meta data is read from a binary file
            scope f = gFS.open(mContext.fixPath(meta.value));
            scope(exit) f.close();
            //xxx I shouldn't load stuff directly (endian issues), but who cares?
            FileAtlas header;
            f.readExact(cast(ubyte[])(&header)[0..1]);
            textures.length = header.textureCount;
            f.readExact(cast(ubyte[])textures);
        }
        atlas.mTextures = textures;

        atlas.load();

        mContents = atlas;
    }

    static this() {
        Resources.registerResourceType!(typeof(this))("atlas");
    }
}
