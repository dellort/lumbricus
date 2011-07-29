module wwptools.animconv;

import common.animation;
import framework.drawing;
import framework.imgwrite;
import framework.surface;
import framework.texturepack;
import wwptools.image;
import utils.stream;
import str = utils.string;
import utils.configfile;
import utils.log;
import utils.math;
import utils.misc;
import utils.rect2;
import utils.strparser;
import utils.time;
import utils.vector2;
import wwpdata.animation;
import wwpdata.reader_bnk;
import std.math;

//handlers to convert a parameter to an actual frame
//  p = the source parameter
//  count = number of frames available
//  returns sth. useful between [0, count)
//wonderful type name!
alias int function(int p, int count) ParamConvert;
ParamConvert[string] gParamConverters;

//handlers to load specialized animation descriptions
//(because the generic one is too barfed)
//AniFile = where the final named & processed animations are added to
//AniLoadContext = animation source list
//ConfigNode = import description file (e.g. map animation number to name)
private alias void function(AniFile, RawAnimation[], ConfigNode)
    AnimationLoadHandler;
private AnimationLoadHandler[string] gAnimationLoadHandlers;

static this() {
    gAnimationLoadHandlers["general"] = &loadGeneralW;
    //worm holding a weapon (with weapon-angle as param2)
    gAnimationLoadHandlers["worm_weapon"] = &loadWormWeaponAnimation;
    //bitmaps
    gAnimationLoadHandlers["bitmaps"] = &loadBitmapFrames;
}

struct AnimationFrame {
    SubSurface bitmap;
    bool mirrorY;
    Vector2i center;
}

enum ParamType {
    Null,
    Time,
    P1,
    P2,
    P3,
}

enum string[] cParamTypeStr = [
    "Null",
    "Time",
    "P1",
    "P2",
    "P3"
];

struct ParamInfo {
    ParamType map;      //which parameter maps to this axis
    ParamConvert conv;  //map input parameter value to frame number
}

void defaultParamInfo(ref ParamInfo[3] p) {
    p[0].map = ParamType.Time;
    p[1].map = ParamType.P1;
    p[2].map = ParamType.Null;
    foreach (ref xp; p) {
        xp.conv = &paramConvertNone;
    }
}

class AniEntry {
    //map a param to the three axis, params = [axis-A, axis-B, axis-C]
    ParamInfo[3] params;

    bool repeat;
    int frameTimeMS = 50;

    Vector2i box; //user defined "bounding" box

    private {
        string mName;
        AnimationFrame[][][] mFrames; //indexed [c][b][a] (lol even more)
        TexturePack mPacker;
    }

    this(string a_name, TexturePack a_packer) {
        defaultParamInfo(params);
        mName = a_name;
        mPacker = a_packer;
    }

    string name() {
        return mName;
    }

    //add wwp frames; frames of each animations go into axis A,
    //if there's more than one Animation in src, they are appended along B
    //possibly modifies the bounding box (box) and frameTimeMS
    //the frame transformation functions work only on the current framelist
    //append_A: all animations from src are appended to axis A
    //  e.g. if src=[a1, a2], it's like src=[a3], where a3 is a1 and a2 played
    //  sequentially (like a2 is played after a1 has ended)
    void addFrames(RawAnimation[] src, int c_idx = 0, bool append_A = false) {
        void addAnimation(RawAnimation a, int b_idx) {
            auto len_a = a.frames.length;
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
            Vector2i bb = a.box;
            box = box.max(bb);
            a.savePacked(mPacker);
            AnimationFrame[] cframes;
            foreach (size_t idx, frame; a.frames) {
                AnimationFrame cur;
                cur.bitmap = frame.image;
                //frame.at is the offset of the bitmap within a.box
                cur.center = frame.at - a.box/2;
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
        foreach (ref cframes; mFrames) {
            foreach (ref fl; cframes) {
                auto count = fl.length;
                for (size_t i = 0; i < count; i++) {
                    //append in reverse order (the only case where we use Y_A
                    //needs it in this way)
                    auto cur = fl[count-i-1];
                    cur.mirrorY = !cur.mirrorY;
                    fl ~= cur;
                }
            }
        }
    }

    //append animations mirrored to Y axis along axis B
    void appendMirrorY_B() {
        foreach (ref cframes; mFrames) {
            auto count = cframes.length;
            for (size_t i = 0; i < count; i++) {
                auto cur = cframes[i].dup;
                foreach (ref f; cur) {
                    f.mirrorY = !f.mirrorY;
                }
                cframes ~= cur;
            }
        }
    }

    void reverseA() {
        foreach (ref cframes; mFrames) {
            foreach (ref fl; cframes) {
                for (size_t i = 0; i < fl.length/2; i++) {
                    swap(fl[i], fl[$-i-1]);
                }
            }
        }
    }

    void appendBackwardsA() {
        foreach (ref cframes; mFrames) {
            foreach (ref fl; cframes) {
                size_t count = fl.length;
                for (sizediff_t i = count-1; i >= 0; i--) {
                    fl ~= fl[i];
                }
            }
        }
    }

    //special case for jetpack; could avoid this by making framelist
    //manipulation available to the "user"
    void appendMirroredY_Backwards_B() {
        foreach (ref cframes; mFrames) {
            foreach_reverse (fl; cframes.dup) {
                //mirror them
                auto list = fl.dup;
                foreach (ref a; list) {
                    a.mirrorY = !a.mirrorY;
                }
                cframes ~= list;
            }
        }
    }

    //special case for wwp walking animation: I don't know what team17 devs
    //drank when writing their code, but forward movements seems to be
    //integrated into the animation, which is removed by this code
    void fixWwpWalkAni() {
        foreach (ref cframes; mFrames) {
            foreach (ref fl; cframes) {
                for (size_t i = 0; i < fl.length; i++) {
                    fl[i].center.x += (i*10)/15;
                }
            }
        }
    }

    //offset correction, needed for crateN_fly
    void moveFrames(Vector2i offset) {
        foreach (fl; mFrames) {
            foreach (f2; fl) {
                foreach (ref AnimationFrame f; f2) {
                    f.center += offset;
                }
            }
        }
    }

    void discardFrames(int num) {
        if (num == 0)
            return;
        foreach (ref cframes; mFrames) {
            foreach (ref fl; cframes) {
                assert(fl.length > 2*num);
                fl = fl[num..$-num];
            }
        }
    }

    int length_a() {
        return cast(int)(length_b ? mFrames[0][0].length : 0);
    }

    int length_b() {
        return cast(int)(length_c ? mFrames[0].length : 0);
    }

    int length_c() {
        return cast(int)mFrames.length;
    }

    int length(int dim) {
        final switch (dim) {
            case 0: return length_a();
            case 1: return length_b();
            case 2: return length_c();
        }
    }

    ///user defined animation bounding box
    Rect2i boundingBox() {
        Rect2i bbox;
        bbox.p1 = -box/2; //(center around (0,0))
        bbox.p2 = box + bbox.p1;
        return bbox;
    }

    ///"correct" bounding box, calculated over all frames
    ///The animation center is at (0, 0) of this box
    Rect2i frameBoundingBox() {
        Rect2i bnds = Rect2i.Abnormal();
        foreach (fl; mFrames) {
            foreach (f2; fl) {
                foreach (ref AnimationFrame f; f2) {
                    bnds.extend(f.center);
                    bnds.extend(f.center + f.bitmap.size);
                }
            }
        }
        return bnds;
    }

    ///draw a frame of this animation, selected by parameters
    ///the center of the animation will be at pos
    void drawFrame(Canvas canvas, Vector2i pos, int a, int b, int c) {
        AnimationFrame* frame = &mFrames[c][b][a];

        auto bitmap = frame.bitmap;

        BitmapEffect eff;
        eff.mirrorY = frame.mirrorY;

        auto center = frame.center;
        //fixup mirrored animation offsets (must be mirrored as well)
        //xxx would be better to have this directly in the preprocessing steps
        if (frame.mirrorY) {
            center.x = -center.x - bitmap.size.x;
        }

        canvas.drawSprite(bitmap, pos + center, &eff);
    }

    void drawFrame(Canvas c, Vector2i pos, ref AnimationParams p, int time) {

        int selectParam(int index) {
            auto map = params[index].map;

            if (map == ParamType.Time)
                return time;

            if (map >= ParamType.P1 && map <= ParamType.P3) {
                int pidx = map - ParamType.P1;
                int count = length(index);
                int r = params[index].conv(p.p[pidx], count);
                if (r < 0 || r >= count) {
                    debug gLog.minor("WARNING: parameter out of bounds");
                    r = 0;
                }
                return r;
            }

            return 0;
        }

        drawFrame(c, pos, selectParam(0), selectParam(1), selectParam(2));
    }
}

//don't know why I wanted this separate from AniEntry, maybe because Animation
//  contains lots of fields and functions
class ImportedWWPAnimation : Animation, DebugAniFrames {
    private {
        AniEntry mData;
    }

    this(AniEntry a_data) {
        argcheck(a_data);
        mData = a_data;

        //find out how long this is - needs reverse lookup
        //default value 1 in case time isn't used for a param (not animated)
        int framelen = 1;
        foreach (int idx, ref par; mData.params) {
            if (par.map == ParamType.Time) {
                framelen = mData.length(idx);
                break;
            }
        }

        doInit(framelen, mData.boundingBox, mData.frameTimeMS);

        repeat = mData.repeat;
    }

    override void drawFrame(Canvas c, Vector2i pos, ref AnimationParams p,
        Time t)
    {
        int frameIdx = getFrameIdx(t);
        if (frameIdx < 0)
            return;
        assert(frameIdx < frameCount);
        mData.drawFrame(c, pos, p, frameIdx);
    }

    //DebugAniFrames
    string[] paramInfos() {
        string[] inf;
        foreach (int i, ParamInfo p; mData.params) {
            string pconv = "?";
            foreach (name, fn; gParamConverters) {
                if (fn is p.conv)
                    pconv = name;
            }
            inf ~= myformat("  %s <- %s '%s' (%s frames)", i,
                cParamTypeStr[p.map], pconv, mData.length(i));
        }
        return inf;
    }
    int[] paramCounts() {
        return [mData.length_a(), mData.length_b(), mData.length_c()];
    }
    Rect2i frameBoundingBox() {
        return mData.frameBoundingBox();
    }
    void drawFrame(Canvas c, Vector2i pos, int p1, int p2, int p3) {
        mData.drawFrame(c, pos, p1, p2, p3);
    }
}


//list of imported animations
class AniFile {
    private {
        AniEntry[] mEntries;
        Surface[string] mBitmaps;
    }

    TexturePack packer;

    this() {
        packer = new TexturePack();
    }

    AniEntry addEntry(string name) {
        auto res = new AniEntry(name, packer);
        mEntries ~= res;
        return res;
    }

    void addBitmap(string name, Surface bmp) {
        argcheck(!(name in mBitmaps));
        mBitmaps[name] = bmp;
    }

    //the returned array is strictly read-only
    AniEntry[] entries() {
        return mEntries;
    }

    //the returned AA and data are strictly read-only
    Surface[string] bitmaps() {
        return mBitmaps;
    }
}

void importAnimations(AniFile dest, RawAnimation[] animations,
    ConfigNode config)
{
    foreach (ConfigNode item; config) {
        if (!item.hasSubNodes())
            continue;
        if (!(item.name in gAnimationLoadHandlers))
            throwError("no handler found for: %s", item.name);
        auto handler = gAnimationLoadHandlers[item.name];
        handler(dest, animations, item);
    }
}

RawAnimation getAnimation(RawAnimation[] animations, int index) {
    if (!indexValid(animations, index))
        throwError("invalid animation index: %s", index);
    auto res = animations[index];
    res.seen = true;
    return res;
}

//val must contain exactly n entries separated by whitespace
//these are parsed as numbers and the animations with these indices is returned
//x is the number of animations which are read consecutively for each entry
//so getSimple("x1 x2",2,3) returns [x1+1, x1+2, x1+3, x2+1, ...]
//actual number of returned animations is n*x
//when n is -1, n is set to the number of components found in the string
RawAnimation[] getSimple(RawAnimation[] animations, string val, int n, int x) {
    string[] strs = str.split(val);
    if (n < 0)
        n = cast(int)strs.length;
    RawAnimation[] res;
    foreach (s; strs) {
        auto z = fromStr!(int)(s);
        for (int i = 0; i < x; i++)
            res ~= getAnimation(animations, z + i);
    }
    if (res.length != n*x) {
        throw new Exception(myformat("unexpected blahblah %s/%s: %s",
            n, x, val));
    }
    return res;
}

private void loadWormWeaponAnimation(AniFile anims, RawAnimation[] animations,
    ConfigNode basenode)
{
    foreach (ConfigNode node; basenode) {
        auto anis = getSimple(animations, node.value, 2, 3);

        auto get = anims.addEntry(node.name ~ "_get");
        get.addFrames(anis[0..3]);
        get.params[0] = ParamInfo(ParamType.Time);
        get.params[1] = ParamInfo(ParamType.P1, &paramConvertStep3);
        get.appendMirrorY_B();

        auto hold = anims.addEntry(node.name ~ "_hold");
        hold.addFrames(anis[3..6]);
        hold.params[0] = ParamInfo(ParamType.P2, &paramConvertFreeRot180);
        hold.params[1] = ParamInfo(ParamType.P1, &paramConvertStep3);
        hold.appendMirrorY_B();
    }
}

//parse flags which are separated by a ",", flags end with the first ";"
//"s" is modified to contain the original string without the flags
string[] parseFlags(ref string s, bool flagnode) {
    string f;
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

enum cFlagItem = "_flags";
enum cParamItem = "_params";

ParamType paramTypeFromStr(string s) {
    foreach (int idx, string ts; cParamTypeStr) {
        if (str.icmp(ts, s) == 0)
            return cast(ParamType)idx;
    }
    throwError("unknown param type: '%s'", s);
    assert(false);
}

//s has the format x ::= <param>[ "/" <string>] , s ::= s (s ",")*
//param is one of map (below) and returned in p
void parseParams(string s, ref ParamInfo[3] p) {
    auto stuff = str.split(s, ",");
    require(stuff.length <= 3, "only 3 param mappings or less allowed");
    for (int n = 0; n < stuff.length; n++) {
        auto sub = str.split(stuff[n], "/");
        require(sub.length <= 2, "too many '/'");
        string pname = sub[0];
        ParamType param = paramTypeFromStr(pname);
        p[n].map = param;
        bool is_real_param = param >= ParamType.P1 && param <= ParamType.P3;
        if (sub.length < 2) {
            require(!is_real_param, "%s requires param mapping", pname);
            continue;
        }
        require(is_real_param, "%s can't have a param mapping", pname);
        string pmap = sub[1];
        auto pconv = pmap in gParamConverters;
        if (!pconv)
            throwError("param conv. '%s' not found", pmap);
        p[n].conv = *pconv;
    }
}

private void loadGeneralW(AniFile anims, RawAnimation[] anis, ConfigNode node) {
    void loadAnim(string[] flags, ref ParamInfo[3] params, string name,
        string value)
    {
        //actually load an animation
        auto ani = anims.addEntry(name);

        ani.params[] = params;

        bool[string] boolFlags;
        int[string] intFlags;
        string[] usedFlags; //for error reporting

        intFlags["f"] = 50; //default framerate

        foreach (string f; flags) {
            if (!f.length)
                continue;
            if (f[0] == '+') {
                boolFlags[f[1..$]] = true;
            } else if (f[0] == '-') {
                boolFlags[f[1..$]] = false;
            } else {
                //use this as an int-flag; syntax: <name> ":" <number>
                auto sp = str.find(f, ":");
                if (sp < 0)
                    throwError("name:number expected, got: %s", f);
                auto n = f[0..sp];
                auto v = f[sp+1..$];
                int i = fromStr!(int)(v); //might throw ConversionException
                intFlags[n] = i;
            }
        }

        bool boolFlag(string name, bool def = false) {
            usedFlags ~= name;
            return (name in boolFlags) ? boolFlags[name] : def;
        }
        int intFlag(string name, int def = 0) {
            usedFlags ~= name;
            return (name in intFlags) ? intFlags[name] : def;
        }

        bool bnk_backwards;

        string[] vals = str.split(value, "|");
        foreach (int c_idx, v; vals) {
            int x = intFlag("x", 1);
            auto anims = getSimple(anis, str.strip(v), intFlag("n", -1), x);
            int n = cast(int)(anims.length / x);
            assert(anims.length==n*x); //should be guaranteed by getSimple()
            if (boolFlag("fill_length")) {
                //make all animations in anims the same length
                //fill the shorter animations by appending the last frame
                int len = 0;
                foreach (a; anims) {
                    len = max(len, cast(int)a.frames.length);
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
                ani.repeat |= anims[0].repeat;
                bnk_backwards = anims[0].backwards;
            }
        }

        ani.frameTimeMS = intFlag("f");
        ani.discardFrames(intFlag("discard", 0));

        //lol, xxx reproduce thoughts of wwp devs
        if (boolFlag("walkfix"))
            ani.fixWwpWalkAni();

        if (boolFlag("repeat"))
            ani.repeat = true;

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

        ani.moveFrames(Vector2i(intFlag("offset_x"), intFlag("offset_y")));

        //check for unused flags
        foreach (used; usedFlags) {
            if (used in boolFlags)
                boolFlags.remove(used);
            if (used in intFlags)
                intFlags.remove(used);
        }
        auto unused = boolFlags.keys ~ intFlags.keys;
        if (unused.length) {
            throwError("unknown flags: %s in %s", unused, name);
        }
    }

    void loadRec(string[] flags, ref ParamInfo[3] params, ConfigNode node) {
        ParamInfo[3] nparams;
        nparams[] = params; //copy, as params is passed by-ref
        if (node.value.length == 0) {
            string flagstr = node.getStringValue(cFlagItem);
            string paramstr = node.getStringValue(cParamItem);
            auto subflags = flags ~ parseFlags(flagstr, true);
            if (flagstr.length > 0)
                throwError("unparsed flag values: %s", flagstr);
            if (paramstr.length > 0) {
                parseParams(paramstr, nparams);
            }
            foreach (ConfigNode s; node) {
                loadRec(subflags, nparams, s);
            }
        } else {
            if (node.name == cFlagItem || node.name == cParamItem)
                return;
            auto val = node.value;
            auto subflags = flags.dup;
            subflags ~= parseFlags(val, false);
            loadAnim(subflags, nparams, node.name, val);
        }
    }

    ParamInfo[3] params;
    defaultParamInfo(params);
    loadRec([], params, node);
}

private void loadBitmapFrames(AniFile anims, RawAnimation[] anis,
    ConfigNode node)
{
    foreach (ConfigNode sub; node) {
        string name = sub.name;
        //frame is "animationnumber,framenumber"
        string frame = sub.value;
        string[] x = str.split(frame, ",");
        if (x.length != 2)
            throwError("invalid frame reference: %s", frame);
        int[2] f;
        for (int i = 0; i < 2; i++) {
            f[i] = fromStr!(int)(x[i]);
        }
        auto ani = getAnimation(anis, f[0]);
        if (!indexValid(ani.frames, f[1]))
            throwError("unknown frame: %s", frame);
        auto fr = ani.frames[f[1]];
        anims.addBitmap(name, ani.frameToBitmap(fr));
    }
}

//------------- param converters

static this() {
    gParamConverters = [
        "direct": &paramConvertDirect,
        "step3": &paramConvertStep3,
        "twosided": &paramConvertTwosided,
        "twosided_inv": &paramConvertTwosidedInv,
        "rot360": &paramConvertFreeRot,
        "rot360_2": &paramConvertFreeRot_2,
        "rot360inv": &paramConvertFreeRotInv,
        "rot360_90": &paramConvertFreeRotPlus90,
        "rot180": &paramConvertFreeRot180,
        "rot180_2": &paramConvertFreeRot180_2,
        "rot90": &paramConvertFreeRot90,
        "rot60": &paramConvertFreeRot60,
        "linear100": &paramConvertLinear100,
        "none": &paramConvertNone
    ];
}

//map with wrap-around
private int map(float val, float rFrom, int rTo) {
    return cast(int)(realmod(val + 0.5f*rFrom/rTo,rFrom)/rFrom * rTo);
}

//map without wrap-around, assuming val will not exceed rFrom
private int map2(float val, float rFrom, int rTo) {
    return cast(int)((val + 0.5f*rFrom/rTo)/rFrom * (rTo-1));
}

//and finally the DWIM (Do What I Mean) version of map: anything can wrap around
private int map3(float val, float rFrom, int rTo) {
    return cast(int)(realmod(val + 0.5f*rFrom/rTo + rFrom,rFrom)/rFrom * rTo);
}

//default
private int paramConvertNone(int angle, int count) {
    return 0;
}
//no change
private int paramConvertDirect(int angle, int count) {
    return clampRangeO(angle, 0, count);
}
//expects count to be 6 (for the 6 angles)
private int paramConvertStep3(int angle, int count) {
    static int[] angles = [180,180+45,180-45,0,0-45,0+45];
    return pickNearestAngle(angles, angle);
}
//expects count to be 2 (two sides)
private int paramConvertTwosided(int angle, int count) {
    return angleLeftRight(cast(float)(angle/180.0f*PI), 0, 1);
}
private int paramConvertTwosidedInv(int angle, int count) {
    return angleLeftRight(cast(float)(angle/180.0f*PI), 1, 0);
}
//360 degrees freedom
private int paramConvertFreeRot(int angle, int count) {
    return map(-angle+270, 360.0f, count);
}
//360 degrees, different angle alignment in animation
//(mostly for animations with discrete angles)
private int paramConvertFreeRot_2(int angle, int count) {
    return cast(int)(realmod(-angle + 270.0f, 360.0f)/360.0f * count);
}
//360 degrees freedom, inverted spinning direction
private int paramConvertFreeRotInv(int angle, int count) {
    return map(-(-angle+270), 360.0f, count);
}

private int paramConvertFreeRotPlus90(int angle, int count) {
    return map(angle, 360.0f, count);
}

//180 degrees, -90 (down) to +90 (up)
//(overflows, used for weapons, it's hardcoded that it can use 180 degrees only)
private int paramConvertFreeRot180(int angle, int count) {
    //assert(angle <= 90);
    //assert(angle >= -90);
    return map2(angle+90.0f,180.0f,count);
}

//for the aim not-animation
private int paramConvertFreeRot180_2(int angle, int count) {
    return map3(angle+180,180.0f,count);
}

//90 degrees, -45 (down) to +45 (up)
private int paramConvertFreeRot90(int angle, int count) {
    angle = clampRangeC(angle, -45, 45);
    return map2(angle+45.0f,90.0f,count);
}

//60 degrees, -30 (down) to +30 (up)
private int paramConvertFreeRot60(int angle, int count) {
    angle = clampRangeC(angle, -30, 30);
    return map2(angle+30.0f,60.0f,count);
}

//0-100 mapped directly to animation frames with clipping
//(the do-it-yourself converter)
private int paramConvertLinear100(int value, int count) {
    value = clampRangeC(value, 0, 100);
    return cast(int)(cast(float)value/101.0f * count);
}

