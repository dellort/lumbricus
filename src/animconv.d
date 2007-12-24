module animconv;

import aconv.atlaspacker;
import aconv.metadata;
import framework.resfileformats;
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

alias FileAnimationParamType Param;

enum Mirror {
    None,
    Y_A,  //axis A mirrored vertically
    Y_B,  //same for axis B
}

AnimList gAnimList;  //source animations
AtlasPacker gPacker; //where the bitmaps go to
AniFile gAnims;      //where the animation (+ frame descriptors) go to

//handlers to load specialized animation descriptions
//(because the generic one is too barfed)
private alias void function(ConfigItem node) AnimationLoadHandler;
private AnimationLoadHandler[char[]] gAnimationLoadHandlers;

static this() {
    //simple animation
    gAnimationLoadHandlers["simple"] = &loadSimpleAnimation;
    //mirror animation on Y axis
    gAnimationLoadHandlers["twosided"] = &loadTwoSidedAnimation;
    //normal worm, standing or walking
    gAnimationLoadHandlers["worm"] = &loadWormAnimation;
    //same as above, but not looping
    gAnimationLoadHandlers["worm_noloop"] = &loadWormNoLoopAnimation;
    //special case
    gAnimationLoadHandlers["worm_noloop_backwards"] =
        &loadWormNoLoopAnimationBack;
    //worm holding a weapon (with weapon-angle as param2)
    gAnimationLoadHandlers["worm_weapon"] = &loadWormWeaponAnimation;
    //worm holding a weapon that has no aiming animation
    gAnimationLoadHandlers["worm_weapon_fixed"] = &loadWormWeaponFixedAnimation;
    //360 degrees graphic, possibly animated
    gAnimationLoadHandlers["360"] = &load360Animation;
    //360 deg, inverted rotation
    gAnimationLoadHandlers["360inv"] = &load360InvAnimation;
    //graphic contains only 180 degrees, to be mirrored
    gAnimationLoadHandlers["360m"] = &load360MAnimation;
    //180 degrees graphic, not animated
    gAnimationLoadHandlers["180"] = &load180Animation;
}

class AniFile {
    char[] anifile_name, aniframes_name;
    AtlasPacker atlas;
    ConfigNode output_conf, output_anims;
    FileAnimation[] animations;
    FileAnimationFrame[][] animations_frames;
    private char[] mName;

    this(char[] fnBase, AtlasPacker a_atlas) {
        atlas = a_atlas;
        mName = fnBase;
        anifile_name = fnBase ~ ".meta";
        aniframes_name = fnBase ~ "_aniframes";

        output_conf = new ConfigNode();
        output_conf.setStringValue("require_resources", atlas.name);
        auto top = output_conf.getSubNode("resources");
        auto anifile = top.getSubNode("aniframes").getSubNode(aniframes_name);
        anifile.setStringValue("atlas", "/" ~ atlas.name);
        anifile.setStringValue("datafile", anifile_name);

        output_anims = top.getSubNode("animations");

        top.comment = "//automatically created by animconv\n"
                      "//change animations.txt instead of this file";
    }

    void add(char[] name, Animation[] src, Param[2] params, Mirror mirror,
        char[][] param_conv, bool repeat, bool backward = false)
    {
        //this writes it to a file and sets the animation's frames .blockIndex
        FileAnimationFrame[][] frames; //indexed [b][a] (lol)
        frames.length = src.length;
        int len_a = src[0].frames.length;
        foreach (int index, s; src) {
            assert(s.frames.length == len_a, "same direction => same length");
            s.savePacked(atlas);
            foreach (frame; s.frames) {
                FileAnimationFrame cur;
                cur.bitmapIndex = frame.blockIndex;
                //frame.x/y is the offset of the bitmap within boxWidth/Height
                cur.centerX = frame.x - s.boxWidth/2;
                cur.centerY = frame.y - s.boxHeight/2;
                frames[index] ~= cur;
            }
        }

        //find the axis used for the time (either A or B)
        int time = (params[0] == Param.Time ? 0 : -1);
        if (time < 0)
            time = (params[1] == Param.Time ? 1 : -1);

        //if the animation should be played reversed every second time, simply
        //append the framelist again in a reversed way
        if (time >= 0 && backward) {
            assert(time == 0); //lol, requires different code for B axis
            foreach (inout fl; frames) {
                int count = fl.length;
                for (int i = count-1; i >= 0; i--) {
                    fl ~= fl[i];
                }
            }
            len_a *= 2;
        }

        //create mirrored frames
        //duplicate the framelist in the given direction and mark the textures
        //so that they'll be drawn mirrored
        if (mirror == Mirror.Y_A) {
            foreach (inout fl; frames) {
                int count = fl.length;
                for (int i = 0; i < count; i++) {
                    auto cur = fl[i];
                    cur.drawEffects ^= FileDrawEffects.MirrorY;
                    fl ~= cur;
                }
            }
            len_a *= 2;
        }
        if (mirror == Mirror.Y_B) {
            int count = frames.length;
            for (int i = 0; i < count; i++) {
                auto cur = frames[i].dup;
                foreach (inout f; cur) {
                    f.drawEffects ^= FileDrawEffects.MirrorY;
                }
                frames ~= cur;
            }
        }

        FileAnimation ani;
        ani.mapParam[] = cast(int[])params;
        ani.frameCount[0] = len_a;
        ani.frameCount[1] = frames.length;
        ani.flags |= (repeat ? FileAnimationFlags.Repeat : 0);
        //dump as rectangular array
        FileAnimationFrame[] out_frames;
        out_frames.length = ani.frameCount[0] * ani.frameCount[1];
        int index = 0;
        foreach (fl; frames) {
            foreach (f; fl) {
                out_frames[index++] = f;
            }
        }

        animations ~= ani;
        animations_frames ~= out_frames;

        auto node = output_anims.getSubNode(name);
        assert(node["index"] == "", "double entry?: "~name);
        node.setIntValue("index", animations.length-1);
        node.setStringValue("aniframes", "/" ~ aniframes_name);
        node.setStringValue("type", "complicated");
        foreach (int i, s; param_conv) {
            node.setStringValue(format("param_%s", i+1), s);
        }
    }

    void write(char[] outPath) {
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

        scope confst = new File(outPath ~ fnBase ~ ".conf", FileMode.OutNew);
        auto textstream = new StreamOutput(confst);
        output_conf.writeFile(textstream);
    }
}

void main(char[][] args) {
    if (args.length < 2) {
        writefln("Syntax: animconv <conffile> [<workPath>]");
        return 1;
    }
    char[] conffn = args[1];
    char[] workPath = "."~path.sep;
    if (args.length >= 3) {
        workPath = args[2]~path.sep;
    }

    void confError(char[] msg) {
        writefln(msg);
    }

    ConfigNode animConf = (new ConfigFile(new File(conffn), conffn,
         &confError)).rootnode;

    foreach (char[] bnkname, ConfigNode bnkNode; animConf) {
        writefln("Working on %s",bnkname);
        scope bnkf = new File(workPath ~ bnkname ~ ".bnk");
        bnkf.seek(4, SeekPos.Set);
        gAnimList = readBnkFile(bnkf);

        //NOTE: of course one could use one atlas or even one AniFile for all
        // animations, didn't just do that yet to avoid filename collisions
        gPacker = new AtlasPacker(bnkname ~ "_atlas");
        gAnims = new AniFile(bnkname, gPacker);

        foreach (ConfigNode item; bnkNode) {
            if (!(item.name in gAnimationLoadHandlers))
                throw new Exception("no handler found for: "~item.name);
            auto handler = gAnimationLoadHandlers[item.name];
            foreach (ConfigItem sub; item) {
                handler(sub);
            }
        }

        gPacker.write(workPath);
        gAnims.write(workPath);

        gPacker = null;
        gAnims = null;
    }
}

//item must be a ConfigValue and contain exactly n entries
//these are parsed as numbers and the animations with these indices is returned
//x is the number of animations which are read consecutively for each entry
//so getSimple(ConfigValue("x1 x2"),2,3) returns [x1.1, x1.2, x1.3, x2.1, ...]
//actual number of returned animations is n*x
//when n is -1, n is set to the number of components found in the string
Animation[] getSimple(ConfigItem item, int n, int x) {
    auto val = castStrict!(ConfigValue)(item);
    char[][] strs = str.split(val.value);
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
            n, x, val.value));
    }
    return res;
}

private void loadWormNoLoopAnimation(ConfigItem node) {
    return doLoadWormAnimation(node, false);
}

private void loadWormAnimation(ConfigItem node) {
    return doLoadWormAnimation(node, true);
}

private void loadWormNoLoopAnimationBack(ConfigItem node) {
    return doLoadWormAnimation(node, true, true);
}

private void doLoadWormAnimation(ConfigItem node, bool loop,
    bool backwards = false)
{
    gAnims.add(node.name, getSimple(node, 1, 3), [Param.Time, Param.P1],
        Mirror.Y_B, ["step3"], loop, backwards);
}

private void loadWormWeaponAnimation(ConfigItem node) {
    //xxx can't yet use both animations, one of the outputs is unused
    //  will be fixed with "Sequences" (which can contain several animations)

    auto anis = getSimple(node, 2, 3);

    gAnims.add(node.name, anis[0..3], [Param.Time, Param.P1], Mirror.Y_B,
        ["step3"], false);

    gAnims.add(node.name ~ "_2", anis[3..6], [Param.P2, Param.P1], Mirror.Y_B,
        ["step3", "rot180"], false);
}

private void loadWormWeaponFixedAnimation(ConfigItem node) {
    gAnims.add(node.name, getSimple(node, 1, 3), [Param.Time, Param.P1],
        Mirror.Y_B, ["step3"], false);
}

private void loadTwoSidedAnimation(ConfigItem node) {
    gAnims.add(node.name, getSimple(node, 1, 1), [Param.Time, Param.P1],
        Mirror.Y_B, ["twosided"], false);
}

private void loadSimpleAnimation(ConfigItem node) {
    auto ani = getSimple(node, 1, 1);

    gAnims.add(node.name, ani, [Param.Time, Param.P1],
        Mirror.None, [], ani[0].repeat, ani[0].backwards);
}

private void load360Animation(ConfigItem node) {
    gAnims.add(node.name, getSimple(node, -1, 1), [Param.P1, Param.Time],
        Mirror.None, ["rot360"], false);
}

private void load360MAnimation(ConfigItem node) {
    gAnims.add(node.name, getSimple(node, -1, 1), [Param.P1, Param.Time],
        Mirror.Y_A, ["rot360"], false);
}

private void load360InvAnimation(ConfigItem node) {
    gAnims.add(node.name, getSimple(node, 1, 1), [Param.P1, Param.Time],
        Mirror.None, ["rot360inv"], false);
}

private void load180Animation(ConfigItem node) {
    gAnims.add(node.name, getSimple(node, 1, 1), [Param.P1, Param.Time],
        Mirror.None, ["rot180"], false);
}
