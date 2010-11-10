//this module allows the game to directly load WWP data files (i.e. the user
//  doesn't have to manually convert the data with extractdata)
module wwptools.load;

import common.resources;
import common.restypes.animation;
import common.restypes.atlas;
import common.restypes.frames;
import framework.config;
import framework.globalsettings;
import framework.surface;
import utils.configfile;
import utils.misc;
import wwptools.animconv;
import wwptools.atlaspacker;
import wwpdata.animation;
import wwpdata.reader_bnk;
import wwpdata.reader_dir;
import wwpdata.reader_spr;

Setting gWwpDataPath;

static this() {
    gResLoadHacks["wwp"] = toDelegate(&loadWwp);
    gWwpDataPath = addSetting!(char[])("wwp_data_path");
}

void loadWwp(ConfigNode node, ResourceFile resfile) {
    auto log = &Resources.log.minor;

    char[] path = gWwpDataPath.value;
    if (!path.length)
        throwError("{} not set, can't load data", gWwpDataPath.name);
    //xxx maybe multiple / are a problem on windows?
    path = path ~ "/";

    ConfigNode importconf = loadConfig(node["import_ani"]);
    ConfigNode importsound = loadConfig(node["import_sound"]);

    foreach (ConfigNode sub; node.getSubNode("bnks")) {
        char[] dirpath = path ~ sub["dir"];
        char[] bnk = sub["bnk"];

        log("importing bnk: {}/{}", dirpath, bnk);

        //load/convert the data
        //no progress bar for you, it's all done here
        Dir dir = new Dir(dirpath);
        scope(exit) dir.close();
        auto bnkfile = dir.open(bnk);
        auto rawanis = readBnkFile(bnkfile);
        doImportAnis(resfile, rawanis, importconf.getSubNode(sub["name"]));
    }

    auto water = node.getSubNode("water_spr");
    Dir wdir = new Dir(path ~ water["dir"]);
    scope(exit) wdir.close();
    auto spr = readSprFile(wdir.open(water["spr"]));
    doImportAnis(resfile, spr, importconf.getSubNode(water["name"]));

    //sounds
    /+
    auto sndinfo = importsound.getSubNode("sounds").getSubNode("normal");
    char[] sndpath = sndinfo["source_path"] ~ "/";
    foreach (char[] name, char[] value; sndinfo.getSubNode("files")) {
        xxx can't add resources, because SoundManager wants a filename and
            always goes through gFS (but we want to use real filesystem paths)
    }
    +/

    log("done importing WWP stuff");
}

void doImportAnis(ResourceFile dest, AnimList rawanis, ConfigNode importconf) {
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
}

//fucking stupid...
Atlas atlas2atlas(AtlasPacker src) {
    return new Atlas(src.blocks, src.images);
}
