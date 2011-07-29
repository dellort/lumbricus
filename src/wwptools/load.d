//this module allows the game to directly load WWP data files (i.e. the user
//  doesn't have to manually convert the data with extractdata)
module wwptools.load;

import common.resources;
import common.restypes.sound;
import framework.config;
import framework.filesystem;
import framework.globalsettings;
import framework.imgread;
import framework.imgwrite;
import framework.sound;
import framework.surface;
//import framework.texturepack;
import utils.color;
import utils.configfile;
import utils.log;
import utils.misc;
import utils.path;
import utils.stream;
import utils.strparser;
import wwptools.animconv;
import wwptools.image;
import wwptools.untile;
import wwpdata.animation;
import wwpdata.reader_bnk;
import wwpdata.reader_img;
import wwpdata.reader_dir;
import wwpdata.reader_spr;

import str = utils.string;

//bad dependency? it really just registers a delegate
import game.gfxset : LoadedWater, gWaterLoadHack;

Setting gWwpDataPath;

static this() {
    gResLoadHacks["wwp"] = toDelegate(&loadWwp);
    gWaterLoadHack["wwp"] = toDelegate(&loadWwpWater);
    gWwpDataPath = addSetting!(string)("game.wwp_data_path");
}

MountId gLastWWpMount;

enum string cWwpVfsPath = "/WWP-import/";

private LogStruct!("wwp_loader") gLog;

private void mountWwp() {
    string path = gWwpDataPath.value;
    if (!path.length)
        throwError("%s not set, can't load data", gWwpDataPath.name);

    //mount the WWP data dir; when I wrote this only the sounds needed that (the
    //  sound drivers get a VFS path to the sound file => VFS must remain
    //  mounted as long as they are possibly used)
    //xxx always remount => possibly take over changes to WWP data path (better
    //  solution? maybe a per-game FileSystem instance?)
    if (gLastWWpMount != MountId.init) {
        gFS.unmount(gLastWWpMount);
        gLastWWpMount = MountId.init;
    }

    gLog.minor("using WWP data path: %s", path);
    gLastWWpMount = gFS.mount(MountPath.absolute, path, cWwpVfsPath, false);
}

private Dir openDir(string dpath) {
    return new Dir(gFS.open(dpath));
}

void loadWwp(ConfigNode node, ResourceFile resfile) {
    mountWwp();

    ConfigNode importconf = loadConfig("import_wwp/animations.conf");
    ConfigNode importsound = loadConfig("import_wwp/sounds.conf");

    Dir gfxdir = openDir(cWwpVfsPath ~ "data/Gfx/Gfx.dir");
    scope(exit) gfxdir.close();

    gLog.minor("importing bnk: main sprites");
    doImportAnis(resfile, readBnkFile(gfxdir.open("mainspr.bnk")),
        importconf.getSubNode("mainspr"));

    gLog.minor("importing rest");

    //sounds
    auto sndinfo = importsound.getSubNode("sounds").getSubNode("normal");
    string sndpath = cWwpVfsPath ~ sndinfo["source_path"] ~ "/";
    foreach (string name, string value; sndinfo.getSubNode("files")) {
        auto fn = sndpath ~ value;
        auto res = new SampleResource(resfile, name, SoundType.sfx, fn);
        resfile.addResource(res);
    }

    //weapon icons
    Surface iconlo = readImgFile(gfxdir.open("iconlo.img"));
    Surface icMask = loadImage("import_wwp/iconmask.png");
    applyAlphaMask(iconlo, icMask);
    Stream names = gFS.open("import_wwp/iconnames.txt");
    scope(exit) names.close();
    string[] inames = readNamefile(names);
    Surface[] imgs = untileImages(iconlo);
    foreach (int idx, img; imgs) {
        require(indexValid(inames, idx), "error in namefile");
        resfile.addPseudoResource("icon_" ~ inames[idx], img);
    }

    gLog.minor("done importing WWP stuff");
}

//code for reading colors from wwp colours.txt
private Color readWaterFile(string vpath) {
    auto file = gFS.open(vpath);
    scope(exit) file.close();
    //xxx missing invalid-utf-8 sanity check
    auto contents = cast(string)file.readAll();

    //colour.txt contains the water background color as RGB
    //  ex.: 47 55 123 for a blue color
    auto lines = str.splitlines(contents);
    require(lines.length > 0, "empty colour.txt?");
    auto cols = str.split(lines[0]);
    require(cols.length == 3, "colour.txt doesn't contain 3 colors?");
    //xxx ignoring "fatal" conversion exception
    return Color.fromBytes(fromStr!(ubyte)(cols[0]), fromStr!(ubyte)(cols[1]),
        fromStr!(ubyte)(cols[2]));
}

private void importWater(ResourceFile resfile, string vpath) {
    ConfigNode importconf = loadConfig("import_wwp/animations.conf");

    Dir waterdir = openDir(vpath ~ "Water.dir");
    scope(exit) waterdir.close();

    gLog.minor("importing bnk: water");
    doImportAnis(resfile, readBnkFile(waterdir.open("water.bnk")),
        importconf.getSubNode("water_anims"));

    auto spr = readSprFile(waterdir.open("layer.spr"));
    doImportAnis(resfile, [spr], importconf.getSubNode("water_waves"));
}

LoadedWater loadWwpWater(ConfigNode info) {
    mountWwp();

    string color = info.value;

    //attempt to find the waterset directory with the correct case
    //e.g. if color=="blue2", find the directory "Blue2"
    //maybe gFS should have an case-insensitive mode for WWP mounted data (as
    //  WWP is a Windows game, where paths are always case-insensitive, damn you
    //  Microsoft); but sorry, I'd rather not hack filesystem.d
    string pathprefix = cWwpVfsPath ~ "data/Water/";
    gFS.listdir(pathprefix, "*", true, (string fn) {
        str.eatEnd(fn, "/");  //for some reason, directories have trailing '/'
        if (str.icmp(fn, color) == 0) {
            color = fn;
            return false;
        }
        return true;
    });
    string vpath = pathprefix ~ color ~ "/";

    //awful hack; just wanted it to get done (we really should rewrite
    //  resource.d instead of attempting to make this code here "cleaner")

    auto resnode = new ConfigNode();
    //make resources code think this was loaded from a color-specific res-file
    resnode[Resources.cResourcePathName] = "wwp_water/" ~ color;
    ResourceFile resfile = gResources.loadResources(resnode, true);

    //was the file already loaded? (the whole point of ResourceFile is caching)
    try {
        resfile.find("water_waves"); //typically part of waterset
    } catch (CustomException e) {
        //most likely not, so actually load stuff
        gLog.minor("loading waterset '%s'", color);
        importWater(resfile, vpath);
        gLog.minor("done loading");
    }

    //colour.txt is opened and parsed on every game round... but who cares
    Color realcolor = readWaterFile(vpath ~ "colour.txt");

    return LoadedWater(realcolor, resfile);
}

//NOTE: destroys rawanis
void doImportAnis(ResourceFile dest, RawAnimation[] rawanis,
    ConfigNode importconf)
{
    auto anims = new AniFile();
    importAnimations(anims, rawanis, importconf);
    //add the converted animations as resources
    foreach (AniEntry e; anims.entries) {
        auto a = new ImportedWWPAnimation(e);
        dest.addPseudoResource(e.name, a);
    }
    foreach (string name, Surface bmp; anims.bitmaps) {
        dest.addPseudoResource(name, bmp);
    }
    int[] unused;
    foreach (idx, a; rawanis) {
        if (!a.seen)
            unused ~= cast(int)idx;
    }
    if (unused.length)
        gLog.trace("unused animation indices: %s", unused);
    freeAnimations(rawanis);
    anims.packer.enableCaching();
    //for debugging: write atlas pages to disk
    version (none) {
        foreach (idx, s; anims.packer.surfaces) {
            saveImage(s, myformat("dump_%s_%s.png", importconf.name, idx));
        }
    }
}
