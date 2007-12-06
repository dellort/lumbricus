module animconv;

import aconv.metadata;
import std.stdio;
import std.stream;
import std.file;
import std.string;
import std.conv;

struct Animation {
    bool boxPacked = false;
    MyAnimationDescriptor desc;
    MyFrameDescriptorBoxPacked[] frames;
}

Animation[] loadMeta(char[] filename) {
    Animation[] res;
    writefln("open: %s", filename);
    Stream meta = new File(filename, FileMode.In);
    int pixels;
    while (!meta.eof) {
        MyAnimationDescriptor ad;
        meta.readExact(&ad, ad.sizeof);
        pixels += ad.w*ad.framecount*ad.h;
        MyFrameDescriptorBoxPacked[] frames;
        frames.length = ad.framecount;
        bool boxPacked = !!(ad.flags && ANIMDESC_FLAGS_BOXPACKED);
        //clear box-packed flag
        ad.flags &= (ANIMDESC_FLAGS_BOXPACKED ^ 0xffff);

        foreach (inout MyFrameDescriptorBoxPacked frame; frames) {
            if (boxPacked)
                //box-packed -> read complete structure
                meta.readExact(&frame, MyFrameDescriptorBoxPacked.sizeof);
            else
                //not box-packed -> read only basic fields
                meta.readExact(&frame, MyFrameDescriptor.sizeof);
        }

        res.length = res.length + 1;
        res[$-1].boxPacked = boxPacked;
        res[$-1].desc = ad;
        res[$-1].frames = frames;
    }
    writefln("pixelsum: %s", pixels);
    return res;
}

void main(char[][] args) {
    char[][] lines = splitlines(cast(char[])read("./animations.txt"));
    char[] cur;
    void nextLine() {
        cur = lines[0];
        lines = lines[1..$];
    }
    nextLine();

    char[] curfilepat; //something which contains %s
    char[] confname;
    char[][] confout;
    Animation[] curanims;
    char[] section;

    void closeCurrent() {
        if (confname.length > 0) {
            confout ~= "}}";
            char[] flap;
            foreach (foo; confout) {
                flap ~= foo ~ "\n";
            }
            write(confname, flap);
            curfilepat = null;
            confname = null;
            confout = null;
            curanims = null;
            section = null;
        }
    }

    for (;;) {
        if (cur == "=end") {
            closeCurrent();
            break;
        } else if (cur[0] == '=') {
            closeCurrent();
            //new anim file or directory/name (produced by unworms)
            curfilepat = cur[1..$] ~ "/anim_#.png";
            curanims = loadMeta(cur[1..$] ~ ".meta");
	    confout ~= "//automatically created by animconv/convani.d";
	    confout ~= "//edit animations.txt instead";
            confout ~= "resources { animations {";
            confname = cur[1..$] ~ ".conf";
        } else if (cur[0] == '+') {
            section = cur[1..$];
        } else if (cur[0] == '.') {
            //name offset1 offset2 ...
            char[][] params = split(cur[1..$]);
            assert(params.length >= 2);
            int[] images;
            foreach(char[] p; params[1..$]) {
                images ~= toInt(p);
            }
            int ani1 = images[0];
            confout ~= "    " ~ params[0] ~ " {";
            confout ~= "        handler = \"" ~ section ~ "\"";
            confout ~= "        width = \"" ~ toString(curanims[ani1].desc.w) ~ "\"";
            confout ~= "        height = \"" ~ toString(curanims[ani1].desc.h) ~ "\"";
            confout ~= "        flags = \"" ~ toString(curanims[ani1].desc.flags) ~ "\"";
            confout ~= "        path = \"" ~ curfilepat ~ "\"";
            confout ~= "        imagecount = \"" ~ toString(images.length) ~ "\"";
            foreach(int index, int i; images) {
                confout ~= "        image_" ~ toString(index) ~ " = \""
                    ~ toString(i) ~ "\"";
                confout ~= "        frames_" ~ toString(index) ~ " = \""
                    ~ toString(curanims[i].desc.framecount) ~ "\"";
            }
            confout ~= "    }";
	} else if (cur[0] == '#') {
	    //skip comment
        } else {
            assert(false);
        }

        nextLine();
    }
}
