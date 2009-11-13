module extractdata;

import devil.image;
import tango.io.FilePath;
import tango.io.model.IFile : FileConst;
import tango.util.Convert;
import tango.io.Stdout;
import tango.io.vfs.ZipFolder : ZipFolder;
import tango.io.compress.Zip : ZipBlockWriter, ZipEntryInfo, createArchive, Method;
import tango.io.vfs.FileFolder;
import tango.io.stream.Text;
debug import tango.core.stacktrace.TraceExceptions;
import stream = utils.stream;
import utils.stream;
import str = utils.string;

import utils.filetools;
import utils.configfile;
import utils.path;
import utils.misc;
import utils.output : TangoStreamOutput;
import utils.color;
import utils.archive;
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
    char[] gfxOutputDir = outputDir ~ "/wwp/";
    trymkdir(gfxOutputDir);
    auto wormsDataDir = wormsDir ~ "/data/";
    importDir = importDir ~ "/";
    auto outFolder = new FileFolder(gfxOutputDir);

    void conferr(char[] msg) { Stdout(msg).newline; }

    ConfigNode loadWImportConfig(char[] file) {
        return (new ConfigFile(Stream.OpenFile(importDir ~ file),
            file, &conferr)).rootnode;
    }
    void writeConfig(ConfigNode node, char[] dest) {
        scope confst = outFolder.file(dest).create.output;
        auto textstream = new TangoStreamOutput(confst);
        node.writeFile(textstream);
    }

    char[] gfxdirp = wormsDataDir ~ "Gfx/Gfx.dir";
    if (!FilePath(gfxdirp).exists()) {
        throw new Exception("Invalid directory! Gfx.dir not found.");
    }
    scope iconnames = Stream.OpenFile(importDir ~ "iconnames.txt");

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
    /+
    //prepare directory "weapons"
    scope wbasef = outFolder.folder("weapons").create;
    scope wepFolder = outFolder.folder("weapons/default").create;
    +/
    //extract weapon icons
    //(NOTE: using namefile, so no filename for basename)
    do_untile(iconlo, "", outFolder, "icons", "icon_", "",
        "icons.conf",iconnames);

    //****** Sounds ******
    ConfigNode sndConf = loadWImportConfig("sounds.txt");
    foreach (ConfigNode sub; sndConf.getSubNode("sounds")) {
        Stdout.format("Copying sounds '{}'", sub.name()).newline;
        auto newres = new ConfigNode();
        auto reslist = newres.getPath("resources.samples", true);
        char[] destp = sub["dest_path"];
        scope destFolder = outFolder.folder(destp).create;
        scope sourceFolder = new FileFolder(wormsDataDir ~ sub["source_path"]);
        foreach (char[] name, char[] value; sub.getSubNode("files")) {
            //doesn't really work if value contains a path
            auto ext = str.tolower(FilePath(value).ext());
            auto outfname = name~"."~ext;
            destFolder.file(outfname).copy(sourceFolder.file(value));
            reslist.setStringValue(name, destp~"/"~outfname);
        }
        writeConfig(newres, sub["conffile"]);
    }

    //****** Convert mainspr.bnk / water.bnk using animconv ******
    Stream mainspr = gfxdir.open("mainspr.bnk");

    ConfigNode animConf = loadWImportConfig("animations.txt");

    //run animconv
    do_extractbnk("mainspr", mainspr, animConf.getSubNode("mainspr"),
        gfxOutputDir~"/");

    //extract water sets (uses animconv too)
    //xxx: like level set, enum subdirectories (code duplication?)
    char[] waterpath = wormsDataDir ~ "Water";
    char[] all_waterout = gfxOutputDir~"/water";
    trymkdir(all_waterout);
    foreach (fi; FilePath(waterpath)) {
        char[] wdir = fi.name;
        char[] wpath = waterpath~"/"~wdir;
        char[] id = str.tolower(wdir);
        char[] waterout = gfxOutputDir~"/water/"~id~"/";
        trymkdir(waterout);
        //lame check if it's a water dir
        FilePath wpath2 = FilePath(wpath);
        if (wpath2.isFolder() && FilePath(wpath~"/Water.dir").exists()) {
            Stdout.formatln("Converting water set '{}'", id);
            Dir waterdir = new Dir(wpath~"/Water.dir");
            do_extractbnk("water_anims", waterdir.open("water.bnk"),
                animConf.getSubNode("water_anims"), waterout);

            auto spr = waterdir.open("layer.spr");
            AnimList water = readSprFile(spr);
            do_write_anims(water, animConf.getSubNode("water_waves"), "waves",
                waterout);
            water.free();

            //colour.txt contains the water background color as RGB
            //  ex.: 47 55 123 for a blue color
            scope colourtxt = new TextInput(
                new File(wpath~"/colour.txt", File.ReadExisting));
            char[] colLine;
            assert(colourtxt.readln(colLine));
            ubyte[] colRGB = to!(ubyte[])(str.split(colLine));
            assert(colRGB.length == 3);
            auto col = Color.fromBytes(colRGB[0], colRGB[1], colRGB[2]);
            auto conf = WATER_P1 ~ col.toString() ~ WATER_P2;
            File.set(waterout~"water.conf", conf);
        }
    }

    //****** Level sets ******
    if (nolevelthemes)
        return;
    char[] levelspath = wormsDataDir~"Level";
    //prepare output dir
    char[] levelDir = outputDir~"/level";
    trymkdir(levelDir);
    //iterate over all directories in path "WWP/data/Levels"
    foreach (fi; FilePath(levelspath)) {
        auto setdir = fi.name;
        //full source path
        char[] setpath = levelspath~"/"~setdir;
        //level set identifier
        char[] id = str.tolower(setdir);
        //xxx hack for -blabla levels
        if (id[0] == '-')
            id = "old" ~ id[1..$];
        //destination path (named by identifier)
        char[] destpath = levelDir~"/"~id;
        trymkdir(destpath);
        if (FilePath(setpath).isFolder()) {
            Stdout.formatln("Converting level set '{}'",id);
            convert_level(setpath~"/",destpath~"/",importDir);
        }
    }
}

int main(char[][] args)
{
    bool usageerror;
    bool nolevelthemes;
    int archive_fmt;  //0: don't pack; 1: zip; 2: tar
    while (args.length > 1) {
        auto opt = args[1];
        if (opt.length == 0 || opt[0] != '-')
            break;
        args = args[0] ~ args[2..$];
        if (opt == "-T") {
            nolevelthemes = true;
        } else if (opt == "-z") {
            archive_fmt = 2;
        } else if (opt == "--") {
            //stop argument parsing, standard on Linux
            break;
        } else {
            Stdout.formatln("unknown option: {}", opt);
            usageerror = true;
        }
    }
    if (args.length < 2 || usageerror) {
        Stdout(
`Syntax: extractdata [options] <wormsMainDir> [<outputDir>]
    <wormsMainDir>: worms main dir, i.e. where your wwp.exe is
    <outputDir>: where to write stuff to (defaults to
                 prefix/share/lumbricus/data2 )
Options:
    -T  don't extract/convert/write level themes
    -z  pack everything into a zip archive`).newline;
        return 1;
    }
    char[] appPath = getAppPath(args[0]);
    char[] outputDir;
    if (args.length >= 3)
        outputDir = args[2];
    else
        outputDir = appPath ~ "../share/lumbricus/data2";
    trymkdir(outputDir);
    //try {
        do_extractdata(appPath ~ "../share/lumbricus/wimport", args[1],
            outputDir, nolevelthemes);
    //} catch (Exception e) {
    //    writefln("Error: %s",e.msg);
    //}
    if (archive_fmt) {
        //create archive, and remove output folder
        auto outd = new FileFolder(outputDir);
        switch (archive_fmt) {
            case 1:
                zipDirectory(outd, outputDir ~ "/../data2.zip");
                break;
            case 2:
                tarDirectory(outd, outputDir ~ "/../data2.tar");
                break;
            default:
                assert(false);
        }
        remove_dir(outputDir);
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

//why does tango not have this??? recurse through fld and return
//  relative filenames
void browse(VfsFolder fld, void delegate(VfsFile file, char[] fn) del,
    char[] prefix = null)
{
    foreach (subf; fld) {
        browse(subf, del, prefix ~ subf.name ~ "/");
    }
    foreach (cfile; fld.self.catalog) {
        del(cfile, prefix ~ cfile.name);
    }
}

//pack inFolder into a zip archive, using relative filenames
void zipDirectory(FileFolder inFolder, char[] zipFile) {
    Stdout.formatln("Creating ZIP archive '{}'...", zipFile);
    auto zb = new ZipBlockWriter(zipFile);
    browse(inFolder, (VfsFile file, char[] fname) {
        //no compression for png files
        if (fname.length > 4 && fname[$-4..$] == ".png")
            zb.method = Method.Store;
        else
            zb.method = Method.Deflate;
        scope fin = file.input;
        ZipEntryInfo info;
        info.name = fname;
        Stdout.format("                                              \r").flush;
        Stdout.format("Deflating {}\r", fname).flush;
        zb.putStream(info, fin);
    });
    zb.finish();
    Stdout.formatln(
        "Done.                                                               ");
}

//pack inFolder into a tar archive, using relative filenames
void tarDirectory(FileFolder inFolder, char[] tarFile) {
    Stdout.formatln("Creating TAR archive '{}'...", tarFile);
    auto ta = new TarArchive(Stream.OpenFile(tarFile, File.WriteCreate), false);
    browse(inFolder, (VfsFile file, char[] fname) {
        auto fin = new ConduitStream(file.input);
        auto fout = ta.openUncompressed(fname);
        Stdout.format("                                              \r").flush;
        Stdout.format("Storing {}\r", fname).flush;
        fout.pipeOut.copyFrom(fin.pipeIn);
        fin.close();
        fout.close();
    });
    ta.close();
    Stdout.formatln(
        "Done.                                                               ");
}
