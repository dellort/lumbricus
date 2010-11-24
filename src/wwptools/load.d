//this module allows the game to directly load WWP data files (i.e. the user
//  doesn't have to manually convert the data with extractdata)
module wwptools.load;

import common.resources;
import common.restypes.sound;
import framework.config;
import framework.filesystem;
import framework.globalsettings;
import framework.imgread;
import framework.sound;
import framework.surface;
//import framework.texturepack;
import utils.configfile;
import utils.misc;
import utils.path;
import utils.stream;
import wwptools.animconv;
import wwptools.image;
import wwptools.untile;
import wwpdata.animation;
import wwpdata.reader_bnk;
import wwpdata.reader_img;
import wwpdata.reader_dir;
import wwpdata.reader_spr;

Setting gWwpDataPath;

static this() {
    gResLoadHacks["wwp"] = toDelegate(&loadWwp);
    gWwpDataPath = addSetting!(char[])("game.wwp_data_path");
}

MountId gLastWWpMount;

void loadWwp(ConfigNode node, ResourceFile resfile) {
    auto log = &Resources.log.minor;

    char[] path = gWwpDataPath.value;
    if (!path.length)
        throwError("{} not set, can't load data", gWwpDataPath.name);

    //mount the WWP data dir; when I wrote this only the sounds needed that (the
    //  sound drivers get a VFS path to the sound file => VFS must remain
    //  mounted as long as they are possibly used)
    //xxx always remount => possibly take over changes to WWP data path (better
    //  solution? maybe a per-game FileSystem instance?)
    if (gLastWWpMount != MountId.init) {
        gFS.unmount(gLastWWpMount);
        gLastWWpMount = MountId.init;
    }

    char[] vfspath = "/WWP-import/";

    log("using WWP data path: {}", path);
    gLastWWpMount = gFS.mount(MountPath.absolute, path, vfspath, false);

    Dir openDir(char[] dpath) {
        return new Dir(gFS.open(vfspath ~ dpath));
    }

    ConfigNode importconf = loadConfig(node["import_ani"]);
    ConfigNode importsound = loadConfig(node["import_sound"]);

    foreach (ConfigNode sub; node.getSubNode("bnks")) {
        char[] dirpath = sub["dir"];
        char[] bnk = sub["bnk"];

        log("importing bnk: {}/{}", dirpath, bnk);

        //load/convert the data
        //no progress bar for you, it's all done here
        Dir dir = openDir(dirpath);
        scope(exit) dir.close();
        auto bnkfile = dir.open(bnk);
        auto rawanis = readBnkFile(bnkfile);
        doImportAnis(resfile, rawanis, importconf.getSubNode(sub["name"]));
    }

    auto water = node.getSubNode("water_spr");
    Dir wdir = openDir(water["dir"]);
    scope(exit) wdir.close();
    auto spr = readSprFile(wdir.open(water["spr"]));
    doImportAnis(resfile, [spr], importconf.getSubNode(water["name"]));

    //code for reading colors
    /+
    //colour.txt contains the water background color as RGB
    //  ex.: 47 55 123 for a blue color
    scope colourtxt = new TextInput(
        new File(wpath~"/colour.txt", File.ReadExisting));
    char[] colLine;
    bool ok = colourtxt.readln(colLine);
    assert(ok);
    ubyte[] colRGB = to!(ubyte[])(str.split(colLine));
    assert(colRGB.length == 3);
    auto col = Color.fromBytes(colRGB[0], colRGB[1], colRGB[2]);
    +/

    //sounds
    auto sndinfo = importsound.getSubNode("sounds").getSubNode("normal");
    char[] sndpath = vfspath ~ "data/" ~ sndinfo["source_path"] ~ "/";
    foreach (char[] name, char[] value; sndinfo.getSubNode("files")) {
        auto fn = sndpath ~ value;
        auto res = new SampleResource(resfile, name, SoundType.sfx, fn);
        resfile.addResource(res);
    }

    auto icons = node.getSubNode("icons");
    Dir idir = openDir(icons["dir"]);
    scope(exit) idir.close();
    Surface iconlo = readImgFile(idir.open(icons["img"]));
    Surface icMask = loadImage(icons["mask"]);
    applyAlphaMask(iconlo, icMask);
    Stream names = gFS.open(icons["names"]);
    scope(exit) names.close();
    char[][] inames = readNamefile(names);
    Surface[] imgs = untileImages(iconlo);
    foreach (int idx, img; imgs) {
        softAssert(indexValid(inames, idx), "error in namefile");
        resfile.addPseudoResource("icon_" ~ inames[idx], img);
    }

    log("done importing WWP stuff");
}

//NOTE: destroys rawanis
void doImportAnis(ResourceFile dest, RawAnimation[] rawanis,
    ConfigNode importconf)
{
    auto anims = new AniFile();
    importAnimations(anims, rawanis, importconf);
    //add the converted animations as resources
    foreach (AniEntry e; anims.entries) {
        auto a = new WWPAnimation(e);
        dest.addPseudoResource(e.name, a);
    }
    foreach (char[] name, Surface bmp; anims.bitmaps) {
        dest.addPseudoResource(name, bmp);
    }
    int[] unused;
    foreach (idx, a; rawanis) {
        if (!a.seen)
            unused ~= idx;
    }
    if (unused.length)
        Resources.log.trace("unused animation indices: {}", unused);
    freeAnimations(rawanis);
}
