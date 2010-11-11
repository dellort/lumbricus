module wwptools.atlaspacker;

import framework.surface;
import wwptools.image;
import utils.stream;
import wwpdata.common;
import common.resfileformats : FileAtlas, FileAtlasTexture;
import utils.boxpacker;
import utils.configfile;
import utils.vector2;
import utils.filetools;
import utils.misc;

import tango.io.Stdout;

import tango.io.model.IFile : FileConst;
const pathsep = FileConst.PathSeparatorChar;

public import utils.boxpacker : Block;

class AtlasPacker {
    private {
        BoxPacker mPacker;
        Surface[] mPageImages;
        FileAtlasTexture[] mBlocks;
    }

    //fnBase = the name of the atlas resource
    this(Vector2i ps = Vector2i(0)) {
        mPacker = new BoxPacker;
        mPacker.pageSize = ps.quad_length == 0 ? Surface.cStdSize : ps;
    }

    //strictly read-only
    FileAtlasTexture[] blocks() { return mBlocks; }
    Surface[] images() { return mPageImages; }

    int blockCount() {
        return mBlocks.length;
    }

    Surface page(int index) {
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
            auto img = new Surface(mPacker.pageSize);
            clearImage(img);
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
    //  outPath = target directory, where various files will be created
    //  fnBase = name of the atlas; used config nodes and as base for filenames
    void write(char[] outPath, char[] fnBase) {
        foreach (int i, img; mPageImages) {
            char[] pagefn, pagepath;
            pagefn = myformat("page_{}", i);
            pagepath = outPath ~ pathsep ~ fnBase;
            trymkdir(pagepath);
            saveImageToFile(img, pagepath ~ pathsep ~ pagefn ~ ".png");
            Stdout.format("Saving {}/{}   \r", i+1, mPageImages.length);
            Stdout.flush();
        }
        Stdout.newline;

        void confError(char[] msg) {
            Stdout(msg).newline;
        }

        ConfigNode confOut = new ConfigNode();

        auto resNode = confOut.getSubNode("resources").getSubNode("atlas")
            .getSubNode(fnBase);
        auto pageNode = resNode.getSubNode("pages");
        for (int i = 0; i < mPageImages.length; i++) {
            pageNode.add("", myformat("{}/page_{}.png", fnBase, i));
        }

        auto metaname = fnBase ~ ".meta";
        resNode.setStringValue("meta", metaname);

        scope metaf = Stream.OpenFile(outPath ~ metaname, File.WriteCreate);
        scope(exit)metaf.close();
        //xxx: endian-safety, no one cares, etc...
        FileAtlas header;
        header.textureCount = mBlocks.length;
        metaf.writeExact(cast(ubyte[])(&header)[0..1]);
        metaf.writeExact(cast(ubyte[])mBlocks);

        scope confst = Stream.OpenFile(outPath ~ fnBase ~ ".conf",
            File.WriteCreate);
        scope(exit)confst.close();
        confOut.writeFile(confst.pipeOut());
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

    //don't free images
    void freeMetaData() {
        delete mPacker;
        delete mBlocks;
    }
}
