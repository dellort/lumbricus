module wwptools.levelconverter;

import aconv.atlaspacker;
import stdf = std.file;
import str = std.string;
import std.stream;
import std.conv;
import std.stdio;
import utils.filetools;
import utils.vector2;
import wwpdata.animation;
import wwpdata.reader_spr;
import wwptools.animconv;
import wwptools.convert;
import wwptools.unworms;

struct BmpDef {
    char[] id, fn;

    static BmpDef opCall(char[] id, char[] fn) {
        BmpDef ret;
        ret.id = id;
        ret.fn = fn;
        return ret;
    }
}

struct ObjDef {
    char[] objid;
    int side;

    static ObjDef opCall(char[] objid, int side) {
        ObjDef ret;
        ret.objid = objid;
        ret.side = side;
        return ret;
    }

    char[] sideStr() {
        switch (side) {
            case 0: return "left";
            case 1: return "right";
            case 2: return "ceiling";
            case 3: return "floor";
        }
    }
}

//convert WWP level directory to lumbricus level directory
//xxx missing debris animation
void convert_level(char[] sourcePath, char[] destPath, char[] tmpdir) {
    BmpDef[] definedBitmaps;
    ObjDef[] definedObjects;

    //extract Level.dir to temp path
    do_unworms(sourcePath~"Level.dir", tmpdir);
    char[] lvlextr = tmpdir~path.sep~"Level";
    scope(exit) remove_dir(lvlextr);
    lvlextr ~= path.sep;
    //Soil back texture
    do_unworms(lvlextr~"soil.img",destPath);
    definedBitmaps ~= BmpDef("soiltex","soil.png");
    //Level front texture
    do_unworms(lvlextr~"text.img",destPath);
    definedBitmaps ~= BmpDef("land","text.png");

    //solid ground texture (WWP does not have this, use default)
    stdf.copy("hard.png",destPath~"hard.png");
    definedBitmaps ~= BmpDef("solid_land","hard.png");

    //Sky gradient
    do_unworms(lvlextr~"gradient.img",destPath);
    RGBTriple colsky = convertSky(destPath~"gradient.png");
    definedBitmaps ~= BmpDef("sky_gradient","gradient.png");

    //big background image
    scope backSpr = new File(lvlextr~"back.spr");
    scope AnimList backAl = readSprFile(backSpr);
    //WWP backgrounds are animation files, although there's only one frame (?)
    //spr file -> one animation with (at least) one frame, so this is ok
    backAl.animations[0].frames[0].save(destPath~"backdrop.png");
    definedBitmaps ~= BmpDef("sky_backdrop","backdrop.png");

    //debris with metadata
    scope debrisPacker = new AtlasPacker("debris_atlas",Vector2i(256));
    scope debrisAnif = new AniFile("debris", debrisPacker);
    scope debrisSpr = new File(lvlextr~"debris.spr");
    scope AnimList debrisAl = readSprFile(debrisSpr);
    debrisAnif.add("debris", debrisAl.animations, [Param.Time, Param.Null],
        Mirror.None, [], AniFlags.Repeat);
    debrisPacker.write(destPath, true);
    debrisAnif.write(destPath, false);

    //bridges
    trymkdir(destPath~"bridge");
    do_unworms(lvlextr~"bridge.img",destPath~"bridge");
    do_unworms(lvlextr~"bridge-l.img",destPath~"bridge");
    do_unworms(lvlextr~"bridge-r.img",destPath~"bridge");
    definedBitmaps ~= BmpDef("bridge_seg","bridge/bridge.png");
    definedBitmaps ~= BmpDef("bridge_l","bridge/bridge-l.png");
    definedBitmaps ~= BmpDef("bridge_r","bridge/bridge-r.png");

    //floor/ceiling makeover texture
    do_unworms(lvlextr~"grass.img",tmpdir);
    scope(exit) stdf.remove(tmpdir~path.sep~"grass.png");
    RGBTriple colground = convertGround(tmpdir~path.sep~"grass.png",
        destPath);
    definedBitmaps ~= BmpDef("ground_up","groundup.png");
    definedBitmaps ~= BmpDef("ground_down","grounddown.png");

    //objects
    trymkdir(destPath~"objects");
    char[][] inffiles = stdf.listdir(lvlextr,"*.inf");
    foreach (inff; inffiles) {
        char[] objname = path.getBaseName(path.getName(inff));
        char[] imgfile = lvlextr~objname~".img";
        do_unworms(imgfile,destPath~"objects");
        scope infFile = new File(inff);
        char[][] infLines = str.split(infFile.toString());
        assert(infLines.length >= 6);
        int side = toInt(infLines[5]);
        definedBitmaps ~= BmpDef("obj_"~objname,"objects/"~objname~".png");
        definedObjects ~= ObjDef("obj_"~objname, side);
    }

    //config file
    scope levelconf = new File(destPath~"level.conf",FileMode.OutNew);
    levelconf.writefln(LEVEL_HEADER);
    foreach (bmpd; definedBitmaps) {
        levelconf.writefln("    %s = \"%s\"",bmpd.id,bmpd.fn);
    }
    levelconf.writefln("  }");
    levelconf.writefln("}\n");

    levelconf.writefln("bordercolor = \"%.6f %.6f %.6f\"",colground.r,
        colground.g,colground.b);
    levelconf.writefln(LEVEL_FIXED_1);
    levelconf.writefln("  skycolor = \"%.6f %.6f %.6f\"",colsky.r,
        colsky.g,colsky.b);
    levelconf.writefln(LEVEL_FIXED_2);

    levelconf.writefln("objects {");
    foreach (obj; definedObjects) {
        levelconf.writefln("  { image = \"%s\" side = \"%s\" }",obj.objid,
            obj.sideStr);
    }
    levelconf.writefln("}");
    levelconf.close();
}


//unchanging part of level.conf, part 1 (yeah, backticked string literals!)
const LEVEL_HEADER = `require_resources = "debris_atlas"
resources {
    aniframes {
        debris_aniframes {
            atlas = "debris_atlas"
            datafile = "debris.meta"
        }
    }
    animations {
        debris {
            index = "0"
            aniframes = "debris_aniframes"
            type = "complicated"
        }
    }
    bitmaps {`;


//unchanging part of level.conf, part 2
const LEVEL_FIXED_1 = `soil_tex = "soiltex"

marker_textures {
  LAND = "land"
  SOLID_LAND = "solid_land"
}

sky {
  gradient = "sky_gradient"
  backdrop = "sky_backdrop"`;


//unchanging part of level.conf, part 3
const LEVEL_FIXED_2 = `  debris = "debris"
}

bridge {
  //a bridge
  //bitmap filenames for the various bridge parts
  segment = "bridge_seg"
  left = "bridge_l"
  right = "bridge_r"
}

borders {
  {
    //paint a border texture, where the
    //pixel-types a and b come together
    marker_a = "LAND"
    marker_b = "FREE"
    //"up", "down" or "both"
    direction = "both"
    texture_up {
      texture = "ground_up"
    }
    texture_down {
      texture = "ground_down"
    }
  }
  {
    marker_a = "SOLID_LAND"
    marker_b = "LAND"
    direction = "both"
    //specify a color instead of a texture
    texture_both {
      color = "0 0 0"
      height = "6"
    }
  }
}
`;
