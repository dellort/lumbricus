module extractdata;

import wwptools.levelconverter;
import utils.filetools;
import stdf = std.file;
import path = std.path;
import std.process;
import std.stdio;
import std.stream;
import std.string : tolower;
import wwptools.untile;
import wwptools.unworms;

void do_extractdata(char[] wormsDir, char[] outputDir) {
    char[] tmpdir = ".";

    char[] gfxdirp = wormsDir~path.sep~"data"~path.sep~"Gfx"~path.sep~"Gfx.dir";
    if (!stdf.exists(gfxdirp)) {
        throw new Exception("Invalid directory! Gfx.dir not found.");
    }
    char[] waterdirp = wormsDir~path.sep~"data"~path.sep~"Water"~path.sep
        ~"Blue"~path.sep~"Water.dir";
    if (!stdf.exists(gfxdirp)) {
        throw new Exception("Invalid directory! Water.dir not found.");
    }
    scope iconnames = new File("iconnames.txt",FileMode.In);

    //****** mainspr.bnk ******
    //extract Gfx.dir to current directory (creating a new dir "Gfx")
    do_unworms(gfxdirp, tmpdir);
    scope(exit) remove_dir(tmpdir~path.sep~"Gfx");
    char[] gfxextr = tmpdir~path.sep~"Gfx"~path.sep;
    //extract mainspr.bnk to output dir (creating a dir "mainspr" and
    //"mainspr.meta")
    do_unworms(gfxextr~"mainspr.bnk", outputDir);

    //****** Weapon icons ******
    //xxx this produces icons with black background, fix needed
    //convert iconlo.img to png (creates "iconlo.png" in tmp dir)
    do_unworms(gfxextr~"iconlo.img", tmpdir);
    scope(exit) stdf.remove(tmpdir~path.sep~"iconlo.png");
    //prepare directory "weapons"
    char[] wepDir = outputDir~path.sep~"weapons";
    trymkdir(wepDir);
    //extract weapon icons
    do_untile(tmpdir~path.sep~"iconlo.png",wepDir~path.sep,"icons","icon_","_lo",
        "_icons.conf",iconnames);

    //****** Water ******
    //extract water (creating dir "Water")
    do_unworms(waterdirp, tmpdir);
    scope(exit) remove_dir(tmpdir~path.sep~"Water");
    char[] waterextr = tmpdir~path.sep~"Water"~path.sep;
    //xxx rename water.bnk to water_blue.bnk, layer.spr to waves.spr
    stdf.rename(waterextr~"water.bnk",waterextr~"water_blue.bnk");
    stdf.rename(waterextr~"layer.spr",waterextr~"waves_blue.spr");
    //extract water_blue.bnk to output dir
    do_unworms(waterextr~"water_blue.bnk",outputDir);
    //extract waves_blue.spr to output dir
    do_unworms(waterextr~"waves_blue.spr",outputDir);

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
