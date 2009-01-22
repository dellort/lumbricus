module aconv.atlaspacker;

import devil.image;
import path = stdx.path;
import str = stdx.string;
import stdx.file;
import stdx.stream;
import stdx.stdio;
import wwpdata.common;
import framework.resfileformats : FileAtlas, FileAtlasTexture;
import utils.boxpacker;
import utils.configfile;
import utils.output;
import utils.vector2;

public import utils.boxpacker : Block;

class AtlasPacker {
    private {
        BoxPacker mPacker;
        Image[] mPageImages;
        FileAtlasTexture[] mBlocks;
        char[] mName;
        bool mImgAlpha;
    }

    //fnBase = the name of the atlas resource
    this(char[] fnBase, Vector2i pageSize = Vector2i(512,512),
        bool alpha = false)
    {
        mPacker = new BoxPacker;
        mPacker.pageSize = pageSize;
        mName = fnBase;
        mImgAlpha = alpha;
    }

    char[] name() {
        return mName;
    }

    int blockCount() {
        return mBlocks.length;
    }

    Image page(int index) {
        return mPageImages[index];
    }

    FileAtlasTexture block(int index) {
        return mBlocks[index];
    }

    //create new space on any page
    //you can get the block number by calling blockCount() before alloc()
    //it is guaranteed that new blocks are always just appended to the block-
    //list (and so blockCount() is enough to know the next block number)
    Block alloc(Vector2i size) {
        Block* newBlock = mPacker.getBlock(size);

        while (newBlock.page >= mPageImages.length) {
            //a new page has been started, create a new image
            auto img = new Image(mPacker.pageSize.x, mPacker.pageSize.y,
                mImgAlpha);
            if (mImgAlpha)
                img.clear(0, 0, 0, 0);
            else
                img.clear(COLORKEY.r, COLORKEY.g, COLORKEY.b, 1);
            mPageImages ~= img;
        }

        FileAtlasTexture fat;
        fat.x = newBlock.origin.x;
        fat.y = newBlock.origin.y;
        fat.w = newBlock.size.x;
        fat.h = newBlock.size.y;
        fat.page = newBlock.page;
        mBlocks ~= fat;

        return *newBlock;
    }

    //save all generated block images to disk
    //also creates a corresponding resource .conf
    void write(char[] outPath, bool textualMeta = false) {
        char[] fnBase = mName;

        foreach (int i, img; mPageImages) {
            char[] pagefn, pagepath;
            pagefn = "page_" ~ str.toString(i);
            pagepath = outPath ~ path.sep ~ fnBase;
            try { mkdir(pagepath); } catch {};
            img.save(pagepath ~ path.sep ~ pagefn ~ ".png");
            writef("Saving %d/%d   \r",i+1, mPageImages.length);
            //fflush(stdout);
        }
        writefln();

        void confError(char[] msg) {
            writefln(msg);
        }

        ConfigNode confOut = (new ConfigFile("","",&confError)).rootnode;

        auto resNode = confOut.getSubNode("resources").getSubNode("atlas")
            .getSubNode(fnBase);
        auto pageNode = resNode.getSubNode("pages");
        for (int i = 0; i < mPageImages.length; i++) {
            pageNode.setStringValue("",fnBase ~ "/page_" ~ str.toString(i)
                ~ ".png");
        }

        if (textualMeta) {
            auto metaNode = resNode.getSubNode("meta");
            foreach (ref FileAtlasTexture t; mBlocks) {
                metaNode.setStringValue("",t.toString());
            }
        } else {
            auto metaname = fnBase ~ ".meta";
            resNode.setStringValue("meta", metaname);

            scope metaf = new File(outPath ~ metaname, FileMode.OutNew);
            //xxx: endian-safety, no one cares, etc...
            FileAtlas header;
            header.textureCount = mBlocks.length;
            metaf.writeExact(&header, header.sizeof);
            metaf.writeExact(mBlocks.ptr, typeof(mBlocks[0]).sizeof * mBlocks.length);
        }

        scope confst = new File(outPath ~ fnBase ~ ".conf", FileMode.OutNew);
        auto textstream = new StreamOutput(confst);
        confOut.writeFile(textstream);
    }

    //also frees the images (violently)
    void free() {
        mPacker = null;
        foreach (i; mPageImages) {
            i.free();
        }
        delete mPageImages;
        delete mBlocks;
    }
}
