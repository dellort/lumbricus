//this module allows the game to directly load WWP data files (i.e. the user
//  doesn't have to manually convert the data with extractdata)
module wwptools.load;

import common.resources;
import common.restypes.animation;
import common.restypes.atlas;
import common.restypes.frames;
import common.restypes.sound;
import framework.config;
import framework.filesystem;
import framework.globalsettings;
import framework.imgread;
import framework.sound;
import framework.surface;
import utils.configfile;
import utils.misc;
import utils.path;
import utils.stream;
import wwptools.animconv;
import wwptools.atlaspacker;
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

void loadWwp(ConfigNode node, ResourceFile resfile) {
    auto log = &Resources.log.minor;

    char[] path = gWwpDataPath.value;
    if (!path.length)
        throwError("{} not set, can't load data", gWwpDataPath.name);

    //mount the WWP data dir; when I wrote this only the sounds needed that
    //xxx this is somewhat inconvenient if the user e.g. changes the path and
    //  then retries; and in general, global state like this isn't good (better
    //  solution? maybe per-game FileSystem instance?)
    char[] vfspath = "/WWP-import/";
    if (!gFS.pathExists(vfspath)) {
        log("using WWP data path: {}", path);
        gFS.mount(MountPath.absolute, path, vfspath, false);
    }

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
void doImportAnis(ResourceFile dest, wwpdata.animation.Animation[] rawanis,
    ConfigNode importconf)
{
    auto anims = new AniFile();
    auto ctx = new AniLoadContext(rawanis);
    importAnimations(anims, ctx, importconf);
    //add the converted animations as resources
    auto atlas = atlas2atlas(anims.atlas);
    foreach (AniEntry e; anims.entries) {
        Frames f = new AtlasFrames(atlas, e.createAnimationData());
        auto a = new ComplicatedAnimation(f);
        dest.addPseudoResource(e.name, a);
    }
    foreach (char[] name, Surface bmp; anims.bitmaps) {
        dest.addPseudoResource(name, bmp);
    }
    freeAnimations(rawanis);
    anims.atlas.freeMetaData();
}

//fucking stupid...
Atlas atlas2atlas(AtlasPacker src) {
    return new Atlas(src.blocks, src.images);
}
