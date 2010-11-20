module wwptools.animconv;

import framework.imgwrite;
import framework.surface;
import wwptools.atlaspacker;
import wwptools.image;
import utils.stream;
import str = utils.string;
import utils.configfile;
import conv = tango.util.Convert;
import utils.misc;
import utils.vector2;
import utils.strparser;
import wwpdata.animation;
import wwpdata.reader_bnk;

public import common.resfileformats;

import tango.io.Stdout;
import tango.io.model.IFile : FileConst;
const pathsep = FileConst.PathSeparatorChar;

alias FileAnimationParamType Param;


//handlers to load specialized animation descriptions
//(because the generic one is too barfed)
//AniFile = where the final named & processed animations are added to
//AniLoadContext = animation source list
//ConfigNode = import description file (e.g. map animation number to name)
private alias void function(AniFile, AniLoadContext, ConfigNode)
    AnimationLoadHandler;
private AnimationLoadHandler[char[]] gAnimationLoadHandlers;

static this() {
    gAnimationLoadHandlers["general"] = &loadGeneralW;
    //worm holding a weapon (with weapon-angle as param2)
    gAnimationLoadHandlers["worm_weapon"] = &loadWormWeaponAnimation;
    //bitmaps
    gAnimationLoadHandlers["bitmaps"] = &loadBitmapFrames;
}

//specific to the task of loading a WWP animation list from a .bnk file (e.g.
//  animations are not named)
//this class could be just an Animation[], but there's also some crap to be
//  able to report unused animations
class AniLoadContext {
    Animation[] animations;
    bool[] used; //used entries from animations

    this(Animation[] anis) {
        animations = anis;
        used = new bool[animations.length];
    }

    Animation get(int index) {
        if (!indexValid(animations, index))
            throwError("invalid animation index: {}", index);
        assert(used.length == animations.length);
        used[index] = true;
        return animations[index];
    }

    //just for reporting this to the developers
    int[] unused() {
        int[] res;
        foreach (size_t idx, bool used; used) {
            if (!used)
                res ~= idx;
        }
        return res;
    }
}

class AniEntry {
    //map a param to the two axis, params = [axis-A, axis-B, axis-C]
    Param[3] params = [Param.Time, Param.P1, Param.Null];
    char[][] param_conv;
    FileAnimationFlags flags = cast(FileAnimationFlags)0;
    int frameTimeMS = 50;
    Vector2i box; //user defined "bounding" box
    Vector2i offset; //offset correction, needed for crateN_fly

    private {
        char[] mName;
        FileAnimationFrame[][][] mFrames; //indexed [c][b][a] (lol even more)
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
    //append_A: all animations from src are appended to axis A
    //  e.g. if src=[a1, a2], it's like src=[a3], where a3 is a1 and a2 played
    //  sequentially (like a2 is played after a1 has ended)
    void addFrames(Animation[] src, int c_idx = 0, bool append_A = false) {
        void addAnimation(Animation a, int b_idx) {
            int len_a = a.frames.length;
            //xxx: using append_A could lead to deformed "non-square"
            //  rectangular array, if used incorrectly (maybe)
            if (!append_A && (length_b() > 0 && len_a != length_a())) {
                //the joined animations always must form a square
                throwError("animations have different lengths");
            }
            auto ft = src[0].frameTimeMS;
            //is that the right thing?
            if (ft != 0)
                frameTimeMS = ft;
            auto bb = Vector2i(a.boxWidth, a.boxHeight);
            box = box.max(bb);
            a.savePacked(mOwner.atlas);
            FileAnimationFrame[] cframes;
            foreach (int idx, frame; a.frames) {
                FileAnimationFrame cur;
                cur.bitmapIndex = a.blockOffset + idx;
                //frame.x/y is the offset of the bitmap within boxWidth/Height
                cur.centerX = frame.at.x - a.boxWidth/2;
                cur.centerY = frame.at.y - a.boxHeight/2;
                cframes ~= cur;
            }
            if (append_A) {
                //append array contents
                mFrames[c_idx][b_idx] ~= cframes;
            } else {
                //append array
                mFrames[c_idx] ~= cframes;
            }
        }

        if (mFrames.length <= c_idx)
            mFrames.length = c_idx + 1;
        foreach (int idx, s; src) {
            addAnimation(s, idx);
        }
    }

    void appendMirrorY_A() {
        foreach (inout cframes; mFrames) {
            foreach (inout fl; cframes) {
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
    }

    //append animations mirrored to Y axis along axis B
    void appendMirrorY_B() {
        foreach (inout cframes; mFrames) {
            int count = cframes.length;
            for (int i = 0; i < count; i++) {
                auto cur = cframes[i].dup;
                foreach (inout f; cur) {
                    f.drawEffects ^= FileDrawEffects.MirrorY;
                }
                cframes ~= cur;
            }
        }
    }

    void reverseA() {
        foreach (inout cframes; mFrames) {
            foreach (inout fl; cframes) {
                for (int i = 0; i < fl.length/2; i++) {
                    swap(fl[i], fl[$-i-1]);
                }
            }
        }
    }

    void appendBackwardsA() {
        foreach (inout cframes; mFrames) {
            foreach (inout fl; cframes) {
                int count = fl.length;
                for (int i = count-1; i >= 0; i--) {
                    fl ~= fl[i];
                }
            }
        }
    }

    //special case for jetpack; could avoid this by making framelist
    //manipulation available to the "user"
    void appendMirroredY_Backwards_B() {
        foreach (inout cframes; mFrames) {
            foreach_reverse (fl; cframes.dup) {
                //mirror them
                auto list = fl.dup;
                foreach (inout a; list) {
                    a.drawEffects ^= FileDrawEffects.MirrorY;
                }
                cframes ~= list;
            }
        }
    }

    //special case for wwp walking animation: I don't know what team17 devs
    //drank when writing their code, but forward movements seems to be
    //integrated into the animation, which is removed by this code
    void fixWwpWalkAni() {
        foreach (inout cframes; mFrames) {
            foreach (inout fl; cframes) {
                for (int i = 0; i < fl.length; i++) {
                    fl[i].centerX += (i*10)/15;
                }
            }
        }
    }

    void discardFrames(int num) {
        if (num == 0)
            return;
        foreach (inout cframes; mFrames) {
            foreach (inout fl; cframes) {
                assert(fl.length > 2*num);
                fl = fl[num..$-num];
            }
        }
    }

    int length_a() {
        return length_b ? mFrames[0][0].length : 0;
    }

    int length_b() {
        return length_c ? mFrames[0].length : 0;
    }

    int length_c() {
        return mFrames.length;
    }

    AnimationData createAnimationData() {
        FileAnimation ani;
        FileAnimationFrame[] frames;

        ani.mapParam[] = cast(int[])params;
        ani.size[0] = box.x;
        ani.size[1] = box.y;
        ani.frameCount[0] = length_a();
        ani.frameCount[1] = length_b();
        ani.frameCount[2] = length_c();
        ani.flags = flags;
        ani.frametime_ms = frameTimeMS;

        //dump as rectangular array
        frames.length = ani.frameCount[0] * ani.frameCount[1]
            * ani.frameCount[2];
        int index = 0;
        foreach (fl; mFrames) {
            foreach (f2; fl) {
                foreach (FileAnimationFrame f; f2) {
                    //offset correction
                    f.centerX += offset.x;
                    f.centerY += offset.y;
                    //just btw.: fixup mirrored animation offsets
                    //(must be mirrored as well)
                    if (f.drawEffects & FileDrawEffects.MirrorY) {
                        int w = mOwner.atlas.block(f.bitmapIndex).w;
                        f.centerX = -f.centerX - w;
                    }
                    frames[index++] = f;
                }
            }
        }

        AnimationData res;
        res.info = ani;
        res.frames = frames;
        assert(param_conv.length <= 3);
        foreach (int idx, char[] p; param_conv) {
            res.param_conv[idx] = p;
        }
        return res;
    }
}

//list of imported animations
class AniFile {
    private {
        AniEntry[] mEntries;
        Surface[char[]] mBitmaps;
    }

    AtlasPacker atlas;

    this() {
        atlas = new AtlasPacker();
    }

    static char[] atlasName(char[] fnBase) {
        return fnBase ~ "_atlas";
    }

    void addBitmap(char[] name, Surface bmp) {
        argcheck(!(name in mBitmaps));
        mBitmaps[name] = bmp;
    }

    //the returned array is strictly read-only
    AniEntry[] entries() {
        return mEntries;
    }

    //the returned AA and data is strictly read-only
    Surface[char[]] bitmaps() {
        return mBitmaps;
    }

    AnimationData[] createAnimationData() {
        AnimationData[] res;
        res.length = mEntries.length;

        foreach (int idx, e; mEntries) {
            res[idx] = e.createAnimationData();
        }

        return res;
    }

    ConfigNode createConfig(char[] fnBase) {
        auto anifile_name = fnBase ~ ".meta";
        auto aniframes_name = fnBase ~ "_aniframes";

        auto output_conf = new ConfigNode();
        auto first = output_conf.getSubNode("require_resources");
        first.add("", atlasName(fnBase) ~ ".conf");
        auto output_res = output_conf.getSubNode("resources");
        auto anifile = output_res.getSubNode("aniframes")
            .getSubNode(aniframes_name);
        anifile.setStringValue("atlas", atlasName(fnBase));
        anifile.setStringValue("datafile", anifile_name);

        first.comment = "//automatically created by animconv\n"
                        "//change import_wwp/animations.conf instead of this file";

        auto output_anims = output_res.getSubNode("animations");

        foreach (int idx, e; mEntries) {
            auto node = output_anims.getSubNode(e.name);
            if (node["index"] != "")
                throwError("double entry?: {}", e.name);
            node.setIntValue("index", idx);
            node.setStringValue("aniframes", aniframes_name);
            node.setStringValue("type", "complicated");
        }

        auto output_bmps = output_res.getSubNode("bitmaps");

        foreach (char[] name, Surface bmp; mBitmaps) {
            //xxx assuming png
            output_bmps[name] = name ~ ".png";
        }

        return output_conf;
    }

    void write(char[] outPath, char[] fnBase, bool writeConf = true) {
        writeBitmaps(outPath, fnBase);

        auto base = outPath ~ fnBase;

        scope dataout = Stream.OpenFile(base ~ ".meta", File.WriteCreate);
        scope(exit) dataout.close();
        writeAnimations(dataout, createAnimationData());

        if (writeConf) {
            auto output_conf = createConfig(fnBase);
            scope confst = Stream.OpenFile(base ~ ".conf", File.WriteCreate);
            output_conf.writeFile(confst.pipeOut());
            confst.close();
        }
    }

    private void writeBitmaps(char[] outPath, char[] fnBase) {
        //normal animation frames
        atlas.write(outPath, atlasName(fnBase));

        //hack for free standing bitmaps
        foreach (char[] name, Surface bmp; mBitmaps) {
            //xxx assuming png
            saveImageToFile(bmp, outPath ~ name ~ ".png");
        }
    }

    void free() {
        atlas.free();
        atlas = null;
        //rest isn't probably worth to delete?
    }
}

void do_extractbnk(char[] bnkname, Stream bnkfile, ConfigNode bnkNode,
    char[] workPath)
{
    if (workPath.length == 0) {
        workPath = "."~pathsep;
    }

    Stdout.formatln("Working on {}", bnkname);
    auto anis = readBnkFile(bnkfile);
    do_write_anims(anis, bnkNode, bnkname, workPath);
    freeAnimations(anis);
}

void importAnimations(AniFile dest, AniLoadContext ctx, ConfigNode config) {
    foreach (ConfigNode item; config) {
        if (!item.hasSubNodes())
            continue;
        if (!(item.name in gAnimationLoadHandlers))
            throwError("no handler found for: {}", item.name);
        auto handler = gAnimationLoadHandlers[item.name];
        handler(dest, ctx, item);
    }
}

void do_write_anims(Animation[] ani_list, ConfigNode config, char[] name,
    char[] workPath)
{
    auto anims = new AniFile();
    auto ctx = new AniLoadContext(ani_list);

    Stdout.formatln("...writing {}...", name);

    importAnimations(anims, ctx, config);

    anims.write(workPath, name);

    auto unused = ctx.unused();
    if (unused.length)
        Stdout.formatln("Unused animations (indices): {}", unused);

    anims.free();
}

//val must contain exactly n entries separated by whitespace
//these are parsed as numbers and the animations with these indices is returned
//x is the number of animations which are read consecutively for each entry
//so getSimple("x1 x2",2,3) returns [x1+1, x1+2, x1+3, x2+1, ...]
//actual number of returned animations is n*x
//when n is -1, n is set to the number of components found in the string
Animation[] getSimple(AniLoadContext ctx, char[] val, int n, int x) {
    char[][] strs = str.split(val);
    if (n < 0)
        n = strs.length;
    Animation[] res;
    foreach (s; strs) {
        auto z = conv.to!(int)(s);
        for (int i = 0; i < x; i++)
            res ~= ctx.get(z+i);
    }
    if (res.length != n*x) {
        throw new Exception(myformat("unexpected blahblah {}/{}: {}",
            n, x, val));
    }
    return res;
}

private void loadWormWeaponAnimation(AniFile anims, AniLoadContext ctx,
    ConfigNode basenode)
{
    foreach (ConfigNode node; basenode) {
        auto anis = getSimple(ctx, node.value, 2, 3);

        auto get = new AniEntry(anims, node.name ~ "_get");
        get.addFrames(anis[0..3]);
        get.params[] = [Param.Time, Param.P1, Param.Null];
        get.param_conv = ["step3"];
        get.appendMirrorY_B();

        auto hold = new AniEntry(anims, node.name ~ "_hold");
        hold.addFrames(anis[3..6]);
        hold.params[] = [Param.P2, Param.P1, Param.Null];
        hold.param_conv = ["step3", "rot180"];
        hold.appendMirrorY_B();
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
    Param[3] p = [Param.Time, Param.Null, Param.Null];
    char[][] conv;
}

//s has the format x ::= <param>[ "/" <string>] , s ::= s (s ",")*
//param is one of map (below) and returned in p
void parseParams(char[] s, out AniParams p) {
    Param[char[]] map;
    map["null"] = Param.Null;
    map["p1"] = Param.P1;
    map["p2"] = Param.P2;
    map["p3"] = Param.P3;
    map["time"] = Param.Time;
    auto stuff = str.split(s, ",");
    softAssert(stuff.length <= 3, "only 3 params or less");
    char[][3] conv = ["","",""];
    for (int n = 0; n < stuff.length; n++) {
        auto sub = str.split(stuff[n], "/");
        softAssert(sub.length == 1 || sub.length == 2, "only 1 or 2 stuffies");
        auto param = map[sub[0]];
        p.p[n] = param;
        int intp;
        if (sub.length < 2)
            continue;
        switch (param) {
            case Param.P1: intp = 0; break;
            case Param.P2: intp = 1; break;
            case Param.P3: intp = 2; break;
            default: intp = -1;
        }
        if (intp >= 0) {
            conv[intp] = sub[1];
        } else {
            throwError("param ignored");
        }
    }
    p.conv = conv.dup;
}

private void loadGeneralW(AniFile anims, AniLoadContext ctx, ConfigNode node) {
    void loadAnim(char[][] flags, AniParams params, char[] name, char[] value) {
        //actually load an animation
        auto ani = new AniEntry(anims, name);

        ani.params[] = params.p;
        ani.param_conv = params.conv;

        bool[char[]] boolFlags;
        int[char[]] intFlags;
        char[][] usedFlags; //for error reporting

        intFlags["f"] = 50; //default framerate

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
                    throwError("name:number expected, got: {}", f);
                auto n = f[0..sp];
                auto v = f[sp+1..$];
                int i = fromStr!(int)(v); //might throw ConversionException
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

        bool bnk_backwards;

        char[][] vals = str.split(value, "|");
        foreach (int c_idx, v; vals) {
            int x = intFlag("x", 1);
            auto anims = getSimple(ctx, str.strip(v), intFlag("n", -1), x);
            int n = anims.length / x;
            assert(anims.length==n*x); //should be guaranteed by getSimple()
            if (boolFlag("fill_length")) {
                //make all animations in anims the same length
                //fill the shorter animations by appending the last frame
                int len = 0;
                foreach (a; anims) {
                    len = max(len, a.frames.length);
                }
                foreach (a; anims) {
                    while (a.frames.length < len) {
                        a.frames ~= a.frames[$-1].dup;
                    }
                }
            }
            if (!boolFlag("append_a_hack", false)) {
                //normal case
                ani.addFrames(anims, c_idx);
            } else {
                //sorry, another "I just needed this quickly" hack
                //append all further animations (n>1) along axis A
                ani.addFrames(anims[0..x], c_idx, false);
                int cur = x;
                for (int ni = 1; ni < n; ni++) {
                    ani.addFrames(anims[cur..cur+x], c_idx, true);
                    cur += x;
                }
            }

            //add the original flags from the .bnk file (or-wise)
            if (boolFlag("use_bnk_flags") && anims.length > 0) {
                ani.flags |= (anims[0].repeat ? FileAnimationFlags.Repeat : 0);
                bnk_backwards = anims[0].backwards;
            }
        }

        ani.frameTimeMS = intFlag("f");
        ani.discardFrames(intFlag("discard", 0));

        //lol, xxx reproduce thoughts of wwp devs
        if (boolFlag("walkfix"))
            ani.fixWwpWalkAni();

        if (boolFlag("repeat"))
            ani.flags |= FileAnimationFlags.Repeat;

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
            throwError("unknown flags: {} in {}", unused, name);
        }
    }

    void loadRec(char[][] flags, AniParams params, ConfigNode node) {
        if (node.value.length == 0) {
            char[] flagstr = node.getStringValue(cFlagItem);
            char[] paramstr = node.getStringValue(cParamItem);
            auto subflags = flags.dup;
            subflags ~= parseFlags(flagstr, true);
            if (flagstr.length > 0)
                throwError("unparsed flag values: {}", flagstr);
            if (paramstr.length > 0) {
                parseParams(paramstr, params);
            }
            foreach (ConfigNode s; node) {
                loadRec(subflags, params, s);
            }
        } else {
            if (node.name == cFlagItem || node.name == cParamItem)
                return;
            auto val = node.value;
            auto subflags = flags.dup;
            subflags ~= parseFlags(val, false);
            loadAnim(subflags, params, node.name, val);
        }
    }

    AniParams params;
    loadRec([], params, node);
}

private void loadBitmapFrames(AniFile anims, AniLoadContext ctx,
    ConfigNode node)
{
    foreach (ConfigNode sub; node) {
        char[] name = sub.name;
        //frame is "animationnumber,framenumber"
        char[] frame = sub.value;
        char[][] x = str.split(frame, ",");
        if (x.length != 2)
            throwError("invalid frame reference: {}", frame);
        int[2] f;
        for (int i = 0; i < 2; i++) {
            f[i] = fromStr!(int)(x[i]);
        }
        auto ani = ctx.get(f[0]);
        if (!indexValid(ani.frames, f[1]))
            throwError("unknown frame: {}", frame);
        auto fr = ani.frames[f[1]];
        anims.addBitmap(name, ani.frameToBitmap(fr));
    }
}
