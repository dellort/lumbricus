module wwptools.animconv;

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

//just for AniFile.add() (not used anywhere else)
enum AniFlags {
    None = 0,
    Repeat = 1, //==Animation.repeat
    Backwards_A = 2, //reverse the whole source animation (for axis A)
    AppendBackwards_A = 4, //first normal and then backwards (axis A)
    KeepLast = 8, //==Animation.keepLastFrame
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
    //same as above, but reversed
    gAnimationLoadHandlers["simple_backwards"] = &loadSimpleAnimationBackwards;
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

    //flags is a bitfield of AniFlags members
    void add(char[] name, Animation[] src, Param[2] params, Mirror mirror,
        char[][] param_conv, int flags = AniFlags.None)
    {
        //xxx force repeat (will change someday)
        flags |= AniFlags.Repeat;
        //this writes it to a file and sets the animation's frames .blockIndex
        FileAnimationFrame[][] frames; //indexed [b][a] (lol)
        frames.length = src.length;
        int len_a = src[0].frames.length;
        Vector2i box = Vector2i(src[0].boxWidth, src[0].boxHeight);
        foreach (int index, s; src) {
            assert(s.frames.length == len_a, "same direction => same length");
            //this assert is not really important, but what about consistency?
            assert(box.x == s.boxWidth && box.y == s.boxHeight);
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

        if (flags & AniFlags.Backwards_A) {
            foreach (inout fl; frames) {
                for (int i = 0; i < fl.length/2; i++) {
                    swap(fl[i], fl[$-i-1]);
                }
            }
        }

        //if the animation should be played reversed every second time, simply
        //append the framelist again in a reversed way
        if (flags & AniFlags.AppendBackwards_A) {
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
                    //append in reverse order (the only case where we use Y_A
                    //needs it in this way)
                    auto cur = fl[count-i-1];
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
        ani.size[0] = box.x;
        ani.size[1] = box.y;
        ani.frameCount[0] = len_a;
        ani.frameCount[1] = frames.length;
        if (flags & AniFlags.Repeat)
            ani.flags |= FileAnimationFlags.Repeat;
        if (flags & AniFlags.KeepLast)
            ani.flags |= FileAnimationFlags.KeepLastFrame;
        //dump as rectangular array
        FileAnimationFrame[] out_frames;
        out_frames.length = ani.frameCount[0] * ani.frameCount[1];
        int index = 0;
        foreach (fl; frames) {
            foreach (f; fl) {
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

void do_animconv(ConfigNode animConf, char[] workPath) {
    if (workPath.length == 0) {
        workPath = "."~path.sep;
    }

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
    return doLoadWormAnimation(node, false, true);
}

private void doLoadWormAnimation(ConfigItem node, bool loop,
    bool backwards = false)
{
    gAnims.add(node.name, getSimple(node, 1, 3), [Param.Time, Param.P1],
        Mirror.Y_B, ["step3"],
            (loop ? AniFlags.Repeat | AniFlags.AppendBackwards_A : 0)
            | (backwards?AniFlags.Backwards_A:0));
}

private void loadWormWeaponAnimation(ConfigItem node) {
    //xxx can't yet use both animations, one of the outputs is unused
    //  will be fixed with "Sequences" (which can contain several animations)

    auto anis = getSimple(node, 2, 3);

    gAnims.add(node.name, anis[0..3], [Param.Time, Param.P1], Mirror.Y_B,
        ["step3"]);

    gAnims.add(node.name ~ "_2", anis[3..6], [Param.P2, Param.P1], Mirror.Y_B,
        ["step3", "rot180"]);
}

private void loadWormWeaponFixedAnimation(ConfigItem node) {
    gAnims.add(node.name, getSimple(node, 1, 3), [Param.Time, Param.P1],
        Mirror.Y_B, ["step3"]);
}

private void loadTwoSidedAnimation(ConfigItem node) {
    gAnims.add(node.name, getSimple(node, 1, 1), [Param.Time, Param.P1],
        Mirror.Y_B, ["twosided"]);
}

private void loadSimpleAnimation(ConfigItem node) {
    auto ani = getSimple(node, 1, 1);

    gAnims.add(node.name, ani, [Param.Time, Param.P1],
        Mirror.None, [], (ani[0].repeat ? AniFlags.Repeat : 0)
            | (ani[0].backwards ? AniFlags.AppendBackwards_A : 0));
}

private void loadSimpleAnimationBackwards(ConfigItem node) {
    auto ani = getSimple(node, 1, 1);

    gAnims.add(node.name, ani, [Param.Time, Param.P1],
        Mirror.None, [], (ani[0].repeat ? AniFlags.Repeat : 0)
            | (ani[0].backwards ? AniFlags.AppendBackwards_A : 0)
            | AniFlags.Backwards_A);
}

private void load360Animation(ConfigItem node) {
    gAnims.add(node.name, getSimple(node, -1, 1), [Param.P1, Param.Time],
        Mirror.None, ["rot360"]);
}

private void load360MAnimation(ConfigItem node) {
    gAnims.add(node.name, getSimple(node, -1, 1), [Param.P1, Param.Time],
        Mirror.Y_A, ["rot360"]);
}

private void load360InvAnimation(ConfigItem node) {
    gAnims.add(node.name, getSimple(node, 1, 1), [Param.P1, Param.Time],
        Mirror.None, ["rot360inv"]);
}

private void load180Animation(ConfigItem node) {
    gAnims.add(node.name, getSimple(node, 1, 1), [Param.P1, Param.Time],
        Mirror.None, ["rot180"]);
}
