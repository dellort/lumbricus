module framework.restypes.atlas;

import framework.framework;
import framework.resfileformats;
import framework.resources;
import utils.configfile;
import utils.vector2;

public import framework.texturepack : TextureRef;

class Atlas {
    private {
        Surface[] mPages;
        FileAtlasTexture[] mTextures;
    }

    TextureRef texture(int index) {
        auto tex = &mTextures[index];
        TextureRef res;
        res.origin.x = tex.x;
        res.origin.y = tex.y;
        res.size.x = tex.w;
        res.size.y = tex.h;
        res.surface = mPages[tex.page];
        return res;
    }

    int count() {
        return mTextures.length;
    }
}

class AtlasResource : ResourceBase!(Atlas) {
    this(Resources parent, char[] id, ConfigItem item) {
        super(parent, id, item);
    }

    protected void load() {
        auto node = cast(ConfigNode)mConfig;
        auto atlas = new Atlas();

        foreach (char[] key, char[] value; node.getSubNode("pages")) {
            atlas.mPages ~= gFramework.loadImage(node.fixPathValue(value));
        }

        FileAtlasTexture[] textures;
        if (node.hasNode("meta")) {
            //meta node contains a list of strings with texture information
            foreach (char[] dummy, char[] metav; node.getSubNode("meta")) {
                textures ~= FileAtlasTexture.parseString(metav);
            }
        } else {
            //meta data is read from a binary file
            scope f = gFramework.fs.open(node.getPathValue("meta"));
            //xxx I shouldn't load stuff directly (endian issues), but who cares?
            FileAtlas header;
            f.readExact(&header, header.sizeof);
            textures.length = header.textureCount;
            f.readExact(textures.ptr,
                typeof(textures[0]).sizeof*textures.length);
        }
        atlas.mTextures = textures;

        mContents = atlas;
    }

    override protected void doUnload() {
        //if (mContents)
        //    mContents.free();
        mContents = null; //let the GC do the work
        super.doUnload();
    }

    static this() {
        Resources.registerResourceType!(typeof(this))("atlas");
    }
}
