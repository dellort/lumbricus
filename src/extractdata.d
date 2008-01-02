module extractdata;

import devil.image;
import stdf = std.file;
import path = std.path;
import std.process;
import std.stdio;
import std.stream;
import std.string : tolower, split;
import std.conv: toUbyte;
import utils.filetools;
import utils.configfile;
import wwpdata.common;
import wwptools.levelconverter;
import wwptools.untile;
import wwptools.unworms;
import wwptools.animconv;

struct WaterDef {
    char[] dirName, id;
    char[] path = "";
    float r = 0.0f, g = 0.0f, b = 1.0f;
}

WaterDef[] waterColors = [{"Blue", "blue"}, {"Blue2", "blue2"},
    {"Green", "green"}, {"Purple", "purple"}, {"Red", "red"},
    {"yellow", "yellow"}];

void do_extractdata(char[] wormsDir, char[] outputDir) {
    char[] tmpdir = ".";

    char[] gfxdirp = wormsDir~path.sep~"data"~path.sep~"Gfx"~path.sep~"Gfx.dir";
    if (!stdf.exists(gfxdirp)) {
        throw new Exception("Invalid directory! Gfx.dir not found.");
    }
    foreach (ref WaterDef w; waterColors) {
        w.path = wormsDir~path.sep~"data"~path.sep~"Water"~path.sep
            ~w.dirName~path.sep;
        if (!stdf.exists(w.path)) {
            throw new Exception("Invalid directory! Water.dir not found.");
        }
    }
    scope iconnames = new File("iconnames.txt",FileMode.In);

    //****** Extract WWP .dir files ******
    //extract Gfx.dir to current directory (creating a new dir "Gfx")
    do_unworms(gfxdirp, tmpdir);
    scope(exit) remove_dir(tmpdir~path.sep~"Gfx");
    char[] gfxextr = tmpdir~path.sep~"Gfx"~path.sep;
    //extract water (creating dir "Water")
    foreach (ref WaterDef w; waterColors) {
        do_unworms(w.path~"Water.dir", tmpdir);
        scope(exit) remove_dir(tmpdir~path.sep~"Water");
        char[] waterextr = tmpdir~path.sep~"Water"~path.sep;
        //rename water.bnk to water_<color>.bnk, layer.spr to waves_<color>.spr
        stdf.rename(waterextr~"water.bnk",
            outputDir~path.sep~"water_"~w.id~".bnk");
        stdf.rename(waterextr~"layer.spr",
            tmpdir~path.sep~"waves_"~w.id~".spr");
        scope colourtxt = new File(w.path~"colour.txt", FileMode.In);
        char[][] colRGB = split(colourtxt.readLine());
        assert(colRGB.length == 3);
        w.r = cast(float)toUbyte(colRGB[0])/255.0f;
        w.g = cast(float)toUbyte(colRGB[1])/255.0f;
        w.b = cast(float)toUbyte(colRGB[2])/255.0f;
    }
    scope(exit) foreach (ref WaterDef w; waterColors) {
        stdf.remove(outputDir~path.sep~"water_"~w.id~".bnk");
        stdf.remove(tmpdir~path.sep~"waves_"~w.id~".spr");
    }

    //****** Weapon icons ******
    //xxx box packing?
    //convert iconlo.img to png (creates "iconlo.png" in tmp dir)
    do_unworms(gfxextr~"iconlo.img", tmpdir);
    scope(exit) stdf.remove(tmpdir~path.sep~"iconlo.png");
    //apply icons mask
    Image icMask = new Image("iconmask.png");
    Image iconImg = new Image(tmpdir~path.sep~"iconlo.png");
    iconImg.applyAlphaMask(icMask);
    iconImg.save(tmpdir~path.sep~"iconlo_masked.png");
    scope(exit) stdf.remove(tmpdir~path.sep~"iconlo_masked.png");
    //prepare directory "weapons"
    char[] wepDir = outputDir~path.sep~"weapons";
    trymkdir(wepDir);
    //extract weapon icons
    do_untile(tmpdir~path.sep~"iconlo_masked.png",wepDir~path.sep,"icons",
        "icon_","_lo", "_icons.conf",iconnames);

    //****** Convert mainspr.bnk / water.bnk using animconv ******
    //move mainspr.bnk to output dir
    stdf.rename(gfxextr~"mainspr.bnk",outputDir~path.sep~"mainspr.bnk");
    scope(exit) stdf.remove(outputDir~path.sep~"mainspr.bnk");
    //move water.bnk to output dir

    ConfigNode animConf = (new ConfigFile(new File("animations.txt"),
        "animations.txt", (char[] msg) { writefln(msg); } )).rootnode;

    //run animconv
    do_animconv(animConf, outputDir~path.sep);

    //xxx box packing, water.conf
    //extract waves_blue.spr to output dir
    //do_unworms(waterextr~"waves_blue.spr",outputDir);

    //****** Level sets ******
    char[] levelspath = wormsDir~path.sep~"data"~path.sep~"Level";
    //prepare output dir
    char[] levelDir = outputDir~path.sep~"level";
    trymkdir(levelDir);
    //iterate over all directories in path "WWP/data/Levels"
    char[][] sets = stdf.listdir(levelspath);
    foreach (setdir; sets) {
        //full source path
        char[] setpath = levelspath~path.sep~setdir;
        //level set identifier
        char[] id = tolower(setdir);
        //xxx hack for -blabla levels
        if (id[0] == '-')
            id = "old" ~ id[1..$];
        //destination path (named by identifier)
        char[] destpath = levelDir~path.sep~id;
        trymkdir(destpath);
        if (stdf.isdir(setpath)) {
            writefln("Converting level set '%s'",id);
            convert_level(setpath~path.sep,destpath~path.sep,tmpdir);
        }
    }
}

int main(char[][] args)
{
    if (args.length < 2) {
        writefln("Syntax: extractdata <wormsMainDir> [<outputDir>]");
        return 1;
    }
    char[] outputDir;
    if (args.length >= 3)
        outputDir = args[2];
    else
        outputDir = ".";
    trymkdir(outputDir);
    try {
        do_extractdata(args[1], outputDir);
    } catch (Exception e) {
        writefln("Error: %s",e.msg);
    }
    return 0;
}
