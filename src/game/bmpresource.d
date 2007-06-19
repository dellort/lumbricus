module game.bmpresource;

import framework.framework;
import game.common;
import game.resources;
import utils.configfile;


protected class BitmapResourceProcessed : BitmapResource {
    char[] mSrcId;
    bool mMirrorY;

    this(Resources parent, char[] id, ConfigItem item)
    {
        super(parent, id, item);
        ConfigNode node = (cast(ConfigNode)item);
        mSrcId = node.getStringValue("id");
        mMirrorY = node.getBoolValue("mirror_y");
        assert(mSrcId != id);
    }

    protected void load() {
        BitmapResource src = mParent.resource!(BitmapResource)(mSrcId);
        if (mMirrorY)
            mContents = src.get().createMirroredY();
        else  //room for more processing (default case doesn't make much sense)
            mContents = src.get();
    }

    static this() {
        ResFactory.register!(typeof(this))("bitmaps_processed");
    }
}

///Resource class for bitmaps
protected class BitmapResource : ResourceBase!(Surface) {
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
        mContents = globals.loadGraphic(fn);
    }

    BitmapResource createMirror() {
        //xxx hack to pass parameters to BitmapResourceProcessed
        ConfigNode n = new ConfigNode();
        char[] newid = id~"mirrored";
        n.setStringValue("id",id);
        n.setBoolValue("mirror_y",true);
        createSubResource("bitmaps_processed",n,false,newid);
        return mParent.resource!(BitmapResource)(newid);
    }

    static this() {
        ResFactory.register!(typeof(this))("bitmaps");
    }
}
