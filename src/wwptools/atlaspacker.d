module wwptools.atlaspacker;

import wwptools.image;
import utils.stream;
import wwpdata.common;
import common.resfileformats : FileAtlas, FileAtlasTexture;
import utils.boxpacker;
import utils.configfile;
import utils.output;
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
        Image[] mPageImages;
        FileAtlasTexture[] mBlocks;
        char[] mName;
    }

    //fnBase = the name of the atlas resource
    this(char[] fnBase, Vector2i pageSize = Vector2i(512,512)) {
        mPacker = new BoxPacker;
        mPacker.pageSize = pageSize;
        mName = fnBase;
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
            auto img = new Image(mPacker.pageSize.x, mPacker.pageSize.y);
            img.clear(0, 0, 0, 0);
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
            pagefn = myformat("page_{}", i);
            pagepath = outPath ~ pathsep ~ fnBase;
            trymkdir(pagepath);
            img.save(pagepath ~ pathsep ~ pagefn ~ ".png");
            Stdout.format("Saving {}/{}   \r", i+1, mPageImages.length);
            Stdout.flush();
        }
        Stdout.newline;

        void confError(char[] msg) {
            Stdout(msg).newline;
        }

        ConfigNode confOut = (new ConfigFile("","",&confError)).rootnode;

        auto resNode = confOut.getSubNode("resources").getSubNode("atlas")
            .getSubNode(fnBase);
        auto pageNode = resNode.getSubNode("pages");
        for (int i = 0; i < mPageImages.length; i++) {
            pageNode.add("", myformat("{}/page_{}.png", fnBase, i));
        }

        if (textualMeta) {
            auto metaNode = resNode.getSubNode("meta");
            foreach (ref FileAtlasTexture t; mBlocks) {
                metaNode.add("", t.toString());
            }
        } else {
            auto metaname = fnBase ~ ".meta";
            resNode.setStringValue("meta", metaname);

            scope metaf = Stream.OpenFile(outPath ~ metaname, File.WriteCreate);
            scope(exit)metaf.close();
            //xxx: endian-safety, no one cares, etc...
            FileAtlas header;
            header.textureCount = mBlocks.length;
            metaf.writeExact(cast(ubyte[])(&header)[0..1]);
            metaf.writeExact(cast(ubyte[])mBlocks);
        }

        scope confst = Stream.OpenFile(outPath ~ fnBase ~ ".conf",
            File.WriteCreate);
        scope(exit)confst.close();
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
