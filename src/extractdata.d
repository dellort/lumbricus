module extractdata;

import devil.image;
import stdf = std.file;
import path = std.path;
import std.process;
import std.stdio;
import std.stream;
import std.string : tolower, split, format;
import std.conv: toUbyte;
import utils.filetools;
import utils.configfile;
import wwpdata.animation;
import wwpdata.common;
import wwpdata.reader_spr;
import wwptools.levelconverter;
import wwptools.untile;
import wwptools.unworms;
import wwptools.animconv;

void do_extractdata(char[] wormsDir, char[] outputDir) {
    char[] tmpdir = ".";

    char[] gfxdirp = wormsDir~path.sep~"data"~path.sep~"Gfx"~path.sep~"Gfx.dir";
    if (!stdf.exists(gfxdirp)) {
        throw new Exception("Invalid directory! Gfx.dir not found.");
    }
    scope iconnames = new File("./iconnames.txt",FileMode.In);

    //****** Extract WWP .dir files ******
    //extract Gfx.dir to current directory (creating a new dir "Gfx")
    do_unworms(gfxdirp, tmpdir);
    scope(exit) remove_dir(tmpdir~path.sep~"Gfx");
    char[] gfxextr = tmpdir~path.sep~"Gfx"~path.sep;

    //****** Weapon icons ******
    //xxx box packing?
    //convert iconlo.img to png (creates "iconlo.png" in tmp dir)
    do_unworms(gfxextr~"iconlo.img", tmpdir);
    scope(exit) stdf.remove(tmpdir~path.sep~"iconlo.png");
    //apply icons mask
    Image icMask = new Image("./iconmask.png");
    Image iconImg = new Image(tmpdir~path.sep~"iconlo.png");
    iconImg.applyAlphaMask(icMask);
    iconImg.save(tmpdir~path.sep~"icons_masked.png");
    scope(exit) stdf.remove(tmpdir~path.sep~"icons_masked.png");
    //prepare directory "weapons"
    char[] wepDir = outputDir~path.sep~"weapons";
    trymkdir(wepDir);
    //extract weapon icons
    do_untile(tmpdir~path.sep~"icons_masked.png",wepDir~path.sep,"icons",
        "icon_","", "_icons.conf",iconnames);

    //****** Convert mainspr.bnk / water.bnk using animconv ******
    //move mainspr.bnk to output dir
    stdf.rename(gfxextr~"mainspr.bnk",outputDir~path.sep~"mainspr.bnk");
    scope(exit) stdf.remove(outputDir~path.sep~"mainspr.bnk");
    //move water.bnk to output dir

    ConfigNode animConf = (new ConfigFile(new File("./animations.txt"),
        "animations.txt", (char[] msg) { writefln(msg); } )).rootnode;

    //run animconv
    do_animconv(animConf, outputDir~path.sep);

    //extract water sets (uses animconv too)
    //xxx: like level set, enum subdirectories (code duplication?)
    char[] waterpath = wormsDir~path.sep~"data"~path.sep~"Water";
    char[] all_waterout = outputDir~path.sep~"water";
    trymkdir(all_waterout);
    char[][] waters = stdf.listdir(waterpath);
    foreach (wdir; waters) {
        char[] wpath = waterpath~path.sep~wdir;
        char[] id = tolower(wdir);
        char[] waterout = outputDir~path.sep~"water"~path.sep~id~path.sep;
        trymkdir(waterout);
        //lame check if it's a water dir
        if (stdf.isdir(wpath) && stdf.exists(wpath~path.sep~"Water.dir")) {
            writefln("Converting water set '%s'", id);
            char[] tmp = tmpdir~path.sep~"watertmp"~path.sep;
            char[] extrp = tmp~"Water"~path.sep;
            trymkdir(tmp);
            do_unworms(wpath~path.sep~"Water.dir", tmp);
            do_extractbnk("water_anims", extrp~"water.bnk",
                animConf.getSubNode("water_anims"), waterout);

            auto spr = new File(extrp~"layer.spr", FileMode.In);
            AnimList water = readSprFile(spr);
            spr.close();
            do_write_anims(water, animConf.getSubNode("water_waves"), "waves",
                waterout);

            scope colourtxt = new File(wpath~path.sep~"colour.txt", FileMode.In);
            char[][] colRGB = split(colourtxt.readLine());
            assert(colRGB.length == 3);
            auto r = cast(float)toUbyte(colRGB[0])/255.0f;
            auto g = cast(float)toUbyte(colRGB[1])/255.0f;
            auto b = cast(float)toUbyte(colRGB[2])/255.0f;
            auto conf = WATER_P1 ~ format("%.2f %.2f %.2f", r, g, b) ~ WATER_P2;
            stdf.write(waterout~"water.conf", conf);

            //remove temporary files
            remove_dir(tmp);
        }
    }

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

//water.conf; parts before and after the water color
char[] WATER_P1 = `//automatically created by extractdata
require_resources {
    "water_anims.conf"
    "waves.conf"
}
color = "`;
char[] WATER_P2 = `"
`;
