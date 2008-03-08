module wwptools.animconv;

import aconv.atlaspacker;
import std.stdio;
import std.stream;
import stdf = std.file;
import std.string;
import std.conv;
import path = std.path;
import utils.configfile;
import utils.misc;
import utils.vector2;
import utils.output;
import wwpdata.animation;
import wwpdata.reader_bnk;

public import framework.resfileformats;

alias FileAnimationParamType Param;

AnimList gAnimList;  //source animations
AtlasPacker gPacker; //where the bitmaps go to
AniFile gAnims;      //where the animation (+ frame descriptors) go to

//default frame duration (set to 0 to prevent writing a default when time is
//unknown)
const int cDefFrameTimeMS = 0;

//handlers to load specialized animation descriptions
//(because the generic one is too barfed)
private alias void function(ConfigNode node) AnimationLoadHandler;
private AnimationLoadHandler[char[]] gAnimationLoadHandlers;

static this() {
    gAnimationLoadHandlers["general"] = &loadGeneralW;
    //worm holding a weapon (with weapon-angle as param2)
    gAnimationLoadHandlers["worm_weapon"] = &loadWormWeaponAnimation;
}

class AniEntry {
    //map a param to the two axis, params = [axis-A, axis-B]
    Param[2] params = [Param.Time, Param.P1];
    char[][] param_conv;
    FileAnimationFlags flags = cast(FileAnimationFlags)0;
    int frameTimeMS;
    Vector2i box; //user defined "bounding" box
    Vector2i offset; //offset correction, needed for crateN_fly

    private {
        char[] mName;
        FileAnimationFrame[][] mFrames; //indexed [b][a] (lol)
        AniFile mOwner;
    }

    this(AniFile a_owner, char[] a_name) {
        mName = a_name;
        mOwner = a_owner;
        //xxx this is not nice
        mOwner.mEntries ~= this;
    }

    char[] name() {
        return mName;
    }

    //add wwp frames; frames of each animations go into axis A,
    //if there's more than one Animation in src, they are appended along B
    //possibly modifies the bounding box (box) and frameTimeMS
    //the frame transformation functions work only on the current framelist
    void addFrames(Animation[] src) {
        void addAnimation(Animation a) {
            int len_a = a.frames.length;
            if (length_b() > 0 && len_a != length_a()) {
                //the joined animations always must form a square
                assert(false, "animations have different lengths");
            }
            auto ft = src[0].frameTimeMS;
            //is that the right thing?
            if (ft != 0)
                frameTimeMS = ft;
            auto bb = Vector2i(a.boxWidth, a.boxHeight);
            box = box.max(bb);
            a.savePacked(mOwner.atlas);
            FileAnimationFrame[] cframes;
            foreach (frame; a.frames) {
                FileAnimationFrame cur;
                cur.bitmapIndex = frame.blockIndex;
                //frame.x/y is the offset of the bitmap within boxWidth/Height
                cur.centerX = frame.x - a.boxWidth/2;
                cur.centerY = frame.y - a.boxHeight/2;
                cframes ~= cur;
            }
            mFrames ~= cframes;
        }

        foreach (s; src) {
            addAnimation(s);
        }
    }

    void appendMirrorY_A() {
        foreach (inout fl; mFrames) {
            int count = fl.length;
            for (int i = 0; i < count; i++) {
                //append in reverse order (the only case where we use Y_A
                //needs it in this way)
                auto cur = fl[count-i-1];
                cur.drawEffects ^= FileDrawEffects.MirrorY;
                fl ~= cur;
            }
        }
    }

    //append animations mirrored to Y axis along axis B
    void appendMirrorY_B() {
        int count = mFrames.length;
        for (int i = 0; i < count; i++) {
            auto cur = mFrames[i].dup;
            foreach (inout f; cur) {
                f.drawEffects ^= FileDrawEffects.MirrorY;
            }
            mFrames ~= cur;
        }
    }

    void reverseA() {
        foreach (inout fl; mFrames) {
            for (int i = 0; i < fl.length/2; i++) {
                swap(fl[i], fl[$-i-1]);
            }
        }
    }

    void appendBackwardsA() {
        foreach (inout fl; mFrames) {
            int count = fl.length;
            for (int i = count-1; i >= 0; i--) {
                fl ~= fl[i];
            }
        }
    }

    //special case for jetpack; could avoid this by making framelist
    //manipulation available to the "user"
    void appendMirroredY_Backwards_B() {
        foreach_reverse (fl; mFrames.dup) {
            //mirror them
            auto list = fl.dup;
            foreach (inout a; list) {
                a.drawEffects ^= FileDrawEffects.MirrorY;
            }
            mFrames ~= list;
        }
    }

    //length of axis A, return 0 if empty framearray
    int length_a() {
        return mFrames.length ? mFrames[0].length : 0;
    }

    int length_b() {
        return mFrames.length;
    }
}


class AniFile {
    char[] anifile_name, aniframes_name;
    AtlasPacker atlas;
    ConfigNode output_conf, output_anims;
    FileAnimation[] animations;
    FileAnimationFrame[][] animations_frames;
    private char[] mName;
    private int mDefFrameTimeMS;
    private AniEntry[] mEntries;

    this(char[] fnBase, AtlasPacker a_atlas, int frameTimeDef = 0) {
        atlas = a_atlas;
        mName = fnBase;
        anifile_name = fnBase ~ ".meta";
        aniframes_name = fnBase ~ "_aniframes";
        mDefFrameTimeMS = frameTimeDef;

        output_conf = new ConfigNode();
        auto first = output_conf.getSubNode("require_resources");
        first.setStringValue("", atlas.name ~ ".conf");
        auto top = output_conf.getSubNode("resources");
        auto anifile = top.getSubNode("aniframes").getSubNode(aniframes_name);
        anifile.setStringValue("atlas", atlas.name);
        anifile.setStringValue("datafile", anifile_name);

        output_anims = top.getSubNode("animations");

        first.comment = "//automatically created by animconv\n"
                        "//change animations.txt instead of this file";
    }

    void write(char[] outPath, bool writeConf = true) {
        foreach (e; mEntries) {
            FileAnimation ani;

            ani.mapParam[] = cast(int[])e.params;
            ani.size[0] = e.box.x;
            ani.size[1] = e.box.y;
            ani.frameCount[0] = e.length_a();
            ani.frameCount[1] = e.length_b();
            ani.flags = e.flags;
            //dump as rectangular array
            FileAnimationFrame[] out_frames;
            out_frames.length = ani.frameCount[0] * ani.frameCount[1];
            int index = 0;
            foreach (fl; e.mFrames) {
                foreach (f; fl) {
                    //offset correction
                    f.centerX += e.offset.x;
                    f.centerY += e.offset.y;
                    //just btw.: fixup mirrored animation offsets
                    //(must be mirrored as well)
                    if (f.drawEffects & FileDrawEffects.MirrorY) {
                        int w = atlas.block(f.bitmapIndex).w;
                        f.centerX = -f.centerX - w;
                    }
                    out_frames[index++] = f;
                }
            }

            animations ~= ani;
            animations_frames ~= out_frames;

            auto node = output_anims.getSubNode(e.name);
            assert(node["index"] == "", "double entry?: "~e.name);
            node.setIntValue("index", animations.length-1);
            node.setStringValue("aniframes", aniframes_name);
            if (e.frameTimeMS == 0)
                e.frameTimeMS = mDefFrameTimeMS;
            node.setIntValue("frametime",e.frameTimeMS);
            node.setStringValue("type", "complicated");
            foreach (int i, s; e.param_conv) {
                if (s.length)
                    node.setStringValue(format("param_%s", i+1), s);
            }
        }

        auto fnBase = mName;

        scope dataout = new File(outPath ~ fnBase ~ ".meta", FileMode.OutNew);
        //again, endian issues etc....
        FileAnimations header;
        header.animationCount = animations.length;
        dataout.writeExact(&header, header.sizeof);
        for (int i = 0; i < animations.length; i++) {
            auto ani = animations[i];
            dataout.writeExact(&ani, ani.sizeof);
            FileAnimationFrame[] frames = animations_frames[i];
            dataout.writeExact(frames.ptr, typeof(frames[0]).sizeof
                * frames.length);
        }

        if (writeConf) {
            scope confst = new File(outPath ~ fnBase ~ ".conf", FileMode.OutNew);
            auto textstream = new StreamOutput(confst);
            output_conf.writeFile(textstream);
        }
    }
}

void do_animconv(ConfigNode animConf, char[] workPath) {
    auto batch = animConf.getSubNode("batch_bnks");

    foreach (char[] bnkname, ConfigNode bnkNode; batch) {
        do_extractbnk(bnkname, workPath ~ bnkname ~ ".bnk", bnkNode, workPath);
    }
}

void do_extractbnk(char[] bnkname, char[] bnkfile, ConfigNode bnkNode,
    char[] workPath)
{
    if (workPath.length == 0) {
        workPath = "."~path.sep;
    }

    writefln("Working on %s",bnkname);
    scope bnkf = new File(bnkfile);
    auto anis = readBnkFile(bnkf);
    do_write_anims(anis, bnkNode, bnkname, workPath);
}

void do_write_anims(AnimList anims, ConfigNode config, char[] name,
    char[] workPath)
{
    //wtf?
    gAnimList = anims;

    //NOTE: of course one could use one atlas or even one AniFile for all
    // animations, didn't just do that yet to avoid filename collisions
    gPacker = new AtlasPacker(name ~ "_atlas");
    gAnims = new AniFile(name, gPacker, config.getIntValue("frametime_def",
        cDefFrameTimeMS));

    writefln("...writing %s...", name);

    //if this is true, _all_ bitmaps are loaded from the .bnk-file, even if
    //they're not needed
    const bool cLoadAll = false;
    if (cLoadAll) {
        foreach (ani; gAnimList.animations) {
            ani.savePacked(gPacker);
        }
    }

    foreach (ConfigNode item; config) {
        if (!(item.name in gAnimationLoadHandlers))
            throw new Exception("no handler found for: "~item.name);
        auto handler = gAnimationLoadHandlers[item.name];
        handler(item);
    }

    gPacker.write(workPath);
    gAnims.write(workPath);

    gPacker = null;
    gAnims = null;
}

//item must be a ConfigValue and contain exactly n entries
//these are parsed as numbers and the animations with these indices is returned
//x is the number of animations which are read consecutively for each entry
//so getSimple(ConfigValue("x1 x2"),2,3) returns [x1.1, x1.2, x1.3, x2.1, ...]
//actual number of returned animations is n*x
//when n is -1, n is set to the number of components found in the string
Animation[] getSimple(char[] val, int n, int x) {
    char[][] strs = str.split(val);
    if (n < 0)
        n = strs.length;
    Animation[] res;
    foreach (s; strs) {
        auto z = conv.toInt(s);
        for (int i = 0; i < x; i++)
            res ~= gAnimList.animations[z+i];
    }
    if (res.length != n*x) {
        throw new Exception(format("unexpected blahblah %d/%d: %s",
            n, x, val));
    }
    return res;
}

private void loadWormWeaponAnimation(ConfigNode basenode) {
    foreach (ConfigValue node; basenode) {
        auto anis = getSimple(node.value, 2, 3);

        auto get = new AniEntry(gAnims, node.name ~ "_get");
        get.addFrames(anis[0..3]);
        get.params[] = [Param.Time, Param.P1];
        get.param_conv = ["step3"];
        get.appendMirrorY_B();

        auto hold = new AniEntry(gAnims, node.name ~ "_hold");
        hold.addFrames(anis[3..6]);
        hold.params[] = [Param.P2, Param.P1];
        hold.param_conv = ["step3", "rot180"];
        hold.appendMirrorY_B();
        hold.flags = FileAnimationFlags.KeepLastFrame;
    }
}

//parse flags which are seperated by a ",", flags end with the first ";"
//"s" is modified to contain the original string without the flags
char[][] parseFlags(inout char[] s, bool flagnode) {
    char[] f;
    if (!flagnode) {
        auto start = str.find(s, ';');
        if (start < 0)
            return [];
        f = s[0..start];
        s = s[start+1..$];
    } else {
        f = s;
        s = "";
    }
    return str.split(f, ",");
}

const cFlagItem = "_flags";
const cParamItem = "_params";

struct AniParams {
    Param[2] p = [Param.Time, Param.Null];
    char[][] conv;
}

//s has the format x ::= <param>[ "/" <string>] , s ::= s (s ",")*
//param is one of map (below) and returned in p
void parseParams(char[] s, out AniParams p) {
    Param[char[]] map;
    map["null"] = Param.Null;
    map["p1"] = Param.P1;
    map["p2"] = Param.P2;
    map["time"] = Param.Time;
    auto stuff = str.split(s, ",");
    assert(stuff.length <= 2, "only 2 params or less");
    char[][2] conv = ["",""];
    for (int n = 0; n < stuff.length; n++) {
        auto sub = str.split(stuff[n], "/");
        assert(sub.length == 1 || sub.length == 2);
        auto param = map[sub[0]];
        p.p[n] = param;
        int intp;
        if (sub.length < 2)
            continue;
        switch (param) {
            case Param.P1: intp = 0; break;
            case Param.P2: intp = 1; break;
            default: intp = -1;
        }
        if (intp >= 0) {
            conv[intp] = sub[1];
        } else {
            assert(false, "param ignored");
        }
    }
    p.conv = conv.dup;
}

private void loadGeneralW(ConfigNode node) {
    void loadAnim(char[][] flags, AniParams params, char[] name, char[] value) {
        //actually load an animation
        auto ani = new AniEntry(gAnims, name);

        ani.params[] = params.p;
        ani.param_conv = params.conv;

        bool[char[]] boolFlags;
        int[char[]] intFlags;
        char[][] usedFlags; //for error reporting

        foreach (char[] f; flags) {
            if (!f.length)
                continue;
            if (f[0] == '+') {
                boolFlags[f[1..$]] = true;
            } else if (f[0] == '-') {
                boolFlags[f[1..$]] = false;
            } else {
                //use this as an int-flag; syntax: <name> ":" <number>
                int sp = str.find(f, ":");
                if (sp < 0)
                    assert(false, "name:number expected, got: " ~ f);
                auto n = f[0..sp];
                auto v = f[sp+1..$];
                int i = 0;
                if (!parseInt(v, i)) {
                    assert(false, "no integer: "~v);
                }
                intFlags[n] = i;
            }
        }

        bool boolFlag(char[] name, bool def = false) {
            usedFlags ~= name;
            return (name in boolFlags) ? boolFlags[name] : def;
        }
        int intFlag(char[] name, int def = 0) {
            usedFlags ~= name;
            return (name in intFlags) ? intFlags[name] : def;
        }

        Animation[] anims = getSimple(value, intFlag("n", -1), intFlag("x", 1));
        ani.addFrames(anims);

        ani.frameTimeMS = intFlag("f");

        if (boolFlag("repeat"))
            ani.flags |= FileAnimationFlags.Repeat;

        if (boolFlag("keeplast"))
            ani.flags |= FileAnimationFlags.KeepLastFrame;

        bool bnk_backwards;

        //add the original flags from the .bnk file (or-wise)
        if (boolFlag("use_bnk_flags") && anims.length > 0) {
            ani.flags |= (anims[0].repeat ? FileAnimationFlags.Repeat : 0);
            bnk_backwards = anims[0].backwards;
        }

        if (boolFlag("backwards_a") | bnk_backwards)
            ani.reverseA();

        if (boolFlag("append_backwards_a") | bnk_backwards)
            ani.appendBackwardsA();

        if (boolFlag("append_mirror_y_backwards_b"))
            ani.appendMirroredY_Backwards_B();

        if (boolFlag("mirror_y_a"))
            ani.appendMirrorY_A();

        if (boolFlag("mirror_y_b"))
            ani.appendMirrorY_B();

        //sigh
        if (boolFlag("backwards2_a"))
            ani.reverseA();

        ani.offset.x = intFlag("offset_x");
        ani.offset.y = intFlag("offset_y");

        //check for unused flags
        foreach (used; usedFlags) {
            if (used in boolFlags)
                boolFlags.remove(used);
            if (used in intFlags)
                intFlags.remove(used);
        }
        auto unused = boolFlags.keys ~ intFlags.keys;
        if (unused.length) {
            assert(false, str.format("unknown flags: %s in %s", unused, name));
        }
    }

    void loadRec(char[][] flags, AniParams params, ConfigItem node) {
        auto subnode = cast(ConfigNode)node;
        auto value = cast(ConfigValue)node;
        if (subnode) {
            char[] flagstr = subnode.getStringValue(cFlagItem);
            char[] paramstr = subnode.getStringValue(cParamItem);
            auto subflags = flags.dup;
            subflags ~= parseFlags(flagstr, true);
            if (flagstr.length > 0)
                assert(false, "unparsed flag values: "~flagstr);
            if (paramstr.length > 0) {
                parseParams(paramstr, params);
            }
            foreach (ConfigItem s; subnode) {
                loadRec(subflags, params, s);
            }
        } else if (value) {
            if (value.name == cFlagItem || value.name == cParamItem)
                return;
            auto val = value.value;
            auto subflags = flags.dup;
            subflags ~= parseFlags(val, false);
            loadAnim(subflags, params, value.name, val);
        }
    }

    AniParams params;
    loadRec([], params, node);
}
