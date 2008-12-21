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

void do_extractdata(char[] importDir, char[] wormsDir, char[] outputDir,
    bool nolevelthemes)
{
    wormsDir = wormsDir ~ path.sep;
    auto wormsDataDir = wormsDir ~ "data" ~ path.sep;
    importDir = importDir ~ path.sep;

    ConfigNode loadWImportConfig(char[] file) {
        return (new ConfigFile(new File(importDir ~ file),
        file, (char[] msg) { writefln(msg); } )).rootnode;
    }
    void writeConfig(ConfigNode node, char[] dest) {
        scope confst = new File(dest, FileMode.OutNew);
        auto textstream = new StreamOutput(confst);
        node.writeFile(textstream);
    }

    char[] gfxdirp = wormsDataDir~"Gfx"~path.sep~"Gfx.dir";
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
    //prepare directory for weapon set "default"
    wepDir ~= path.sep~"default";
    trymkdir(wepDir);
    //extract weapon icons
    //(NOTE: using namefile, so no filename for basename)
    do_untile(iconlo, "", wepDir~path.sep, "icons", "icon_", "",
        "_icons.conf",iconnames);

    //****** Sounds ******
    ConfigNode sndConf = loadWImportConfig("sounds.txt");
    foreach (ConfigNode sub; sndConf.getSubNode("sounds")) {
        writefln("Copying sounds '%s'", sub.name());
        auto newres = new ConfigNode();
        auto reslist = newres.getPath("resources.samples", true);
        char[] destp = sub["dest_path"]~path.sep;
        char[] destp_out = outputDir~path.sep~destp;
        trymkdir(destp_out);
        char[] sourcep = wormsDataDir~path.sep~sub["source_path"]~path.sep;
        foreach (char[] name, char[] value; sub.getSubNode("files")) {
            //doesn't really work if value contains a path
            auto ext = tolower(path.getExt(value));
            auto outfname = name~"."~ext;
            stdf.copy(sourcep~value, destp_out~path.sep~outfname);
            reslist.setStringValue(name, destp~outfname);
        }
        writeConfig(newres, outputDir~path.sep~sub["conffile"]);
    }

    //****** Convert mainspr.bnk / water.bnk using animconv ******
    Stream mainspr = gfxdir.open("mainspr.bnk");

    ConfigNode animConf = loadWImportConfig("animations.txt");

    //run animconv
    do_extractbnk("mainspr", mainspr, animConf.getSubNode("mainspr"),
        outputDir~path.sep);

    //extract water sets (uses animconv too)
    //xxx: like level set, enum subdirectories (code duplication?)
    char[] waterpath = wormsDataDir~"Water";
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
    if (nolevelthemes)
        return;
    char[] levelspath = wormsDataDir~"Level";
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
    bool usageerror;
    bool nolevelthemes;
    while (args.length > 1) {
        auto opt = args[1];
        if (opt.length == 0 || opt[0] != '-')
            break;
        args = args[0] ~ args[2..$];
        if (opt == "-T") {
            nolevelthemes = true;
        } else if (opt == "--") {
            //stop argument parsing, standard on Linux
            break;
        } else {
            writefln("unknown option: %s", opt);
            usageerror = true;
        }
    }
    if (args.length < 3 || usageerror) {
        writefln("Syntax: extractdata [options] <importDir> <wormsMainDir>"
            " [<outputDir>]");
        writefln("  <importDir>: your-svn-root/trunk/lumbricus/data/wimport");
        writefln("  <wormsMainDir>: worms main dir, e.g. where your wwp.exe is");
        writefln("  <outputDir>: where to write stuff to (default is current"
            " dir, but it really");
        writefln("               should be your-svn-root/trunk/lumbricus/data/data2");
        writefln("Options:");
        writefln("  -T  don't extract/convert/write level themes");
        return 1;
    }
    char[] outputDir;
    if (args.length >= 4)
        outputDir = args[3];
    else
        outputDir = ".";
    trymkdir(outputDir);
    try {
        do_extractdata(args[1], args[2], outputDir, nolevelthemes);
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
