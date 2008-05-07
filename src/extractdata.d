module extractdata;

import devil.image;
import stdf = std.file;
import path = std.path;
import std.process;
import std.stdio;
import std.stream;
import std.string : tolower, split, format, replace;
import std.conv: toUbyte;
import utils.filetools;
import utils.configfile;
import wwpdata.animation;
import wwpdata.common;
import wwpdata.reader_img;
import wwpdata.reader_dir;
import wwpdata.reader_spr;
import wwptools.levelconverter;
import wwptools.untile;
import wwptools.unworms;
import wwptools.animconv;

void do_extractdata(char[] importDir, char[] wormsDir, char[] outputDir) {
    wormsDir = wormsDir ~ path.sep;
    importDir = importDir ~ path.sep;

    char[] gfxdirp = wormsDir~"data"~path.sep~"Gfx"~path.sep~"Gfx.dir";
    if (!stdf.exists(gfxdirp)) {
        throw new Exception("Invalid directory! Gfx.dir not found.");
    }
    scope iconnames = new File(importDir ~ "iconnames.txt",FileMode.In);

    //****** Extract WWP .dir files ******
    //extract Gfx.dir to current directory (creating a new dir "Gfx")
    Dir gfxdir = new Dir(gfxdirp);

    //****** Weapon icons ******
    //xxx box packing?
    //convert iconlo.img to png (creates "iconlo.png" in tmp dir)
    Image iconlo = readImgFile(gfxdir.open("iconlo.img"));
    //apply icons mask
    Image icMask = new Image(importDir ~ "iconmask.png");
    iconlo.applyAlphaMask(icMask);
    //prepare directory "weapons"
    char[] wepDir = outputDir~path.sep~"weapons";
    trymkdir(wepDir);
    //extract weapon icons
    //(NOTE: icons_masked.png isn't opened as file, it's only for the basename)
    //(NOTE 2: actually, the parameter isn't used at all, lol)
    do_untile(iconlo, "icons_masked.png",wepDir~path.sep,"icons",
        "icon_","", "_icons.conf",iconnames);

    //****** Convert mainspr.bnk / water.bnk using animconv ******
    Stream mainspr = gfxdir.open("mainspr.bnk");

    ConfigNode animConf = (new ConfigFile(new File(importDir ~ "animations.txt"),
        "animations.txt", (char[] msg) { writefln(msg); } )).rootnode;

    //run animconv
    do_extractbnk("mainspr", mainspr, animConf.getSubNode("mainspr"),
        outputDir~path.sep);

    //extract water sets (uses animconv too)
    //xxx: like level set, enum subdirectories (code duplication?)
    char[] waterpath = wormsDir~"data"~path.sep~"Water";
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
            Dir waterdir = new Dir(wpath~path.sep~"Water.dir");
            do_extractbnk("water_anims", waterdir.open("water.bnk"),
                animConf.getSubNode("water_anims"), waterout);

            auto spr = waterdir.open("layer.spr");
            AnimList water = readSprFile(spr);
            do_write_anims(water, animConf.getSubNode("water_waves"), "waves",
                waterout);
            water.free();

            scope colourtxt = new File(wpath~path.sep~"colour.txt", FileMode.In);
            char[][] colRGB = split(colourtxt.readLine());
            assert(colRGB.length == 3);
            auto r = cast(float)toUbyte(colRGB[0])/255.0f;
            auto g = cast(float)toUbyte(colRGB[1])/255.0f;
            auto b = cast(float)toUbyte(colRGB[2])/255.0f;
            auto conf = WATER_P1 ~ format("%.2f %.2f %.2f", r, g, b) ~ WATER_P2;
            stdf.write(waterout~"water.conf", conf);
        }
    }

    //****** Level sets ******
    char[] levelspath = wormsDir~"data"~path.sep~"Level";
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
            convert_level(setpath~path.sep,destpath~path.sep,importDir);
        }
    }
}

int main(char[][] args)
{
    if (args.length < 3) {
        writefln("Syntax: extractdata <importDir> <wormsMainDir> [<outputDir>]");
        writefln("  <importDir>: your-svn-root/trunk/lumbricus/data/wimport");
        writefln("  <wormsMainDir>: worms main dir, e.g. where your wwp.exe is");
        writefln("  <outputDir>: where to write stuff to (default is current"
            " dir, but it really");
        writefln("               should be your-svn-root/trunk/lumbricus/data/data2");
        return 1;
    }
    char[] outputDir;
    if (args.length >= 4)
        outputDir = args[3];
    else
        outputDir = ".";
    trymkdir(outputDir);
    try {
        do_extractdata(args[1], args[2], outputDir);
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
