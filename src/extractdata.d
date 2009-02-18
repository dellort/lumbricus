module extractdata;

import devil.image;
import tangofile = tango.io.device.File;
import tango.io.FilePath;
import tango.io.model.IFile : FileConst;
import tango.util.Convert;
import tango.io.Stdout;
import stream = stdx.stream;
import stdx.stream;
import stdx.string : tolower, split, replace;

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

const pathsep = FileConst.PathSeparatorChar;

void do_extractdata(char[] importDir, char[] wormsDir, char[] outputDir,
    bool nolevelthemes)
{
    wormsDir = wormsDir ~ pathsep;
    auto wormsDataDir = wormsDir ~ "data" ~ pathsep;
    importDir = importDir ~ pathsep;

    void conferr(char[] msg) { Stdout(msg).newline; }

    ConfigNode loadWImportConfig(char[] file) {
        return (new ConfigFile(new File(importDir ~ file),
        file, &conferr)).rootnode;
    }
    void writeConfig(ConfigNode node, char[] dest) {
        scope confst = new File(dest, FileMode.OutNew);
        auto textstream = new StreamOutput(confst);
        node.writeFile(textstream);
    }

    char[] gfxdirp = wormsDataDir~"Gfx"~pathsep~"Gfx.dir";
    if (!FilePath(gfxdirp).exists()) {
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
    char[] wepDir = outputDir~pathsep~"weapons";
    trymkdir(wepDir);
    //prepare directory for weapon set "default"
    wepDir ~= pathsep~"default";
    trymkdir(wepDir);
    //extract weapon icons
    //(NOTE: using namefile, so no filename for basename)
    do_untile(iconlo, "", wepDir~pathsep, "icons", "icon_", "",
        "_icons.conf",iconnames);

    //****** Sounds ******
    ConfigNode sndConf = loadWImportConfig("sounds.txt");
    foreach (ConfigNode sub; sndConf.getSubNode("sounds")) {
        Stdout.format("Copying sounds '{}'", sub.name()).newline;
        auto newres = new ConfigNode();
        auto reslist = newres.getPath("resources.samples", true);
        char[] destp = sub["dest_path"]~pathsep;
        char[] destp_out = outputDir~pathsep~destp;
        trymkdir(destp_out);
        char[] sourcep = wormsDataDir~pathsep~sub["source_path"]~pathsep;
        foreach (char[] name, char[] value; sub.getSubNode("files")) {
            //doesn't really work if value contains a path
            auto ext = tolower(FilePath(value).ext());
            auto outfname = name~"."~ext;
            FilePath(destp_out~pathsep~outfname).copy(sourcep~value);
            reslist.setStringValue(name, destp~outfname);
        }
        writeConfig(newres, outputDir~pathsep~sub["conffile"]);
    }

    //****** Convert mainspr.bnk / water.bnk using animconv ******
    Stream mainspr = gfxdir.open("mainspr.bnk");

    ConfigNode animConf = loadWImportConfig("animations.txt");

    //run animconv
    do_extractbnk("mainspr", mainspr, animConf.getSubNode("mainspr"),
        outputDir~pathsep);

    //extract water sets (uses animconv too)
    //xxx: like level set, enum subdirectories (code duplication?)
    char[] waterpath = wormsDataDir~"Water";
    char[] all_waterout = outputDir~pathsep~"water";
    trymkdir(all_waterout);
    foreach (fi; FilePath(waterpath)) {
        char[] wdir = fi.name;
        char[] wpath = waterpath~pathsep~wdir;
        char[] id = tolower(wdir);
        char[] waterout = outputDir~pathsep~"water"~pathsep~id~pathsep;
        trymkdir(waterout);
        //lame check if it's a water dir
        FilePath wpath2 = FilePath(wpath);
        if (wpath2.isFolder() && FilePath(wpath~pathsep~"Water.dir").exists()) {
            Stdout("Converting water set '%{}'", id).newline;
            Dir waterdir = new Dir(wpath~pathsep~"Water.dir");
            do_extractbnk("water_anims", waterdir.open("water.bnk"),
                animConf.getSubNode("water_anims"), waterout);

            auto spr = waterdir.open("layer.spr");
            AnimList water = readSprFile(spr);
            do_write_anims(water, animConf.getSubNode("water_waves"), "waves",
                waterout);
            water.free();

            scope colourtxt = new File(wpath~pathsep~"colour.txt", FileMode.In);
            char[][] colRGB = split(colourtxt.readLine());
            assert(colRGB.length == 3);
            auto r = cast(float)to!(ubyte)(colRGB[0])/255.0f;
            auto g = cast(float)to!(ubyte)(colRGB[1])/255.0f;
            auto b = cast(float)to!(ubyte)(colRGB[2])/255.0f;
            auto conf = WATER_P1 ~ myformat("r={}, g={}, b= {}", r, g, b)
                ~ WATER_P2;
            tangofile.File.set(waterout~"water.conf", conf);
        }
    }

    //****** Level sets ******
    if (nolevelthemes)
        return;
    char[] levelspath = wormsDataDir~"Level";
    //prepare output dir
    char[] levelDir = outputDir~pathsep~"level";
    trymkdir(levelDir);
    //iterate over all directories in path "WWP/data/Levels"
    foreach (fi; FilePath(levelspath)) {
        auto setdir = fi.name;
        //full source path
        char[] setpath = levelspath~pathsep~setdir;
        //level set identifier
        char[] id = tolower(setdir);
        //xxx hack for -blabla levels
        if (id[0] == '-')
            id = "old" ~ id[1..$];
        //destination path (named by identifier)
        char[] destpath = levelDir~pathsep~id;
        trymkdir(destpath);
        if (FilePath(setpath).isFolder()) {
            Stdout("Converting level set '{}'",id).newline;
            convert_level(setpath~pathsep,destpath~pathsep,importDir);
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
            Stdout("unknown option: {}", opt).newline;
            usageerror = true;
        }
    }
    if (args.length < 3 || usageerror) {
        Stdout(
`Syntax: extractdata [options] <importDir> <wormsMainDir> [<outputDir>]
    <importDir>: your-svn-root/trunk/lumbricus/data/wimport
    <wormsMainDir>: worms main dir, e.g. where your wwp.exe is
    <outputDir>: where to write stuff to (default is current dir, but it really
                 should be your-svn-root/trunk/lumbricus/data/data2
Options:
    -T  don't extract/convert/write level themes`).newline;
        return 1;
    }
    char[] outputDir;
    if (args.length >= 4)
        outputDir = args[3];
    else
        outputDir = ".";
    trymkdir(outputDir);
    //try {
        do_extractdata(args[1], args[2], outputDir, nolevelthemes);
    //} catch (Exception e) {
    //    writefln("Error: %s",e.msg);
    //}
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
