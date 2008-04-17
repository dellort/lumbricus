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
    BmpDef[] envBitmaps;
    BmpDef[] landBitmaps;
    BmpDef[] definedBitmaps;
    ObjDef[] definedObjects;

    //extract Level.dir to temp path
    do_unworms(sourcePath~"Level.dir", tmpdir);
    char[] lvlextr = tmpdir~path.sep~"Level";
    scope(exit) remove_dir(lvlextr);
    lvlextr ~= path.sep;
    //Soil back texture
    do_unworms(lvlextr~"soil.img",destPath);
    landBitmaps ~= BmpDef("soiltex","soil.png");
    //Level front texture
    do_unworms(lvlextr~"text.img",destPath);
    definedBitmaps ~= BmpDef("land","text.png");

    //solid ground texture (WWP does not have this, use default)
    stdf.copy("./hard.png",destPath~"hard.png");
    definedBitmaps ~= BmpDef("solid_land","hard.png");

    //Sky gradient
    do_unworms(lvlextr~"gradient.img",destPath);
    GradientDef skyGradient = convertSky(destPath~"gradient.png");
    envBitmaps ~= BmpDef("sky_gradient","gradient.png");

    //big background image
    scope backSpr = new File(lvlextr~"back.spr");
    scope AnimList backAl = readSprFile(backSpr);
    //WWP backgrounds are animation files, although there's only one frame (?)
    //spr file -> one animation with (at least) one frame, so this is ok
    backAl.animations[0].frames[0].save(destPath~"backdrop.png");
    envBitmaps ~= BmpDef("sky_backdrop","backdrop.png");

    //debris with metadata
    scope debrisPacker = new AtlasPacker("debris_atlas",Vector2i(256));
    scope debrisAnif = new AniFile("debris", debrisPacker);
    scope debrisSpr = new File(lvlextr~"debris.spr");
    scope AnimList debrisAl = readSprFile(debrisSpr);
    auto debrisAni = new AniEntry(debrisAnif, "debris");
    debrisAni.addFrames(debrisAl.animations);
    debrisAni.flags = FileAnimationFlags.Repeat;
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

    char[][char[]] stuff;

    char[] makeBmps(BmpDef[] bitmaps) {
        char[] res;
        foreach (bmpd; bitmaps) {
            res ~= str.format("%s = \"%s\"\n",bmpd.id,bmpd.fn);
        }
        return res;
    }

    stuff["landgen_bitmaps"] = makeBmps(definedBitmaps);
    stuff["land_bitmaps"] = makeBmps(landBitmaps);
    stuff["env_bitmaps"] = makeBmps(envBitmaps);

    char[] fmtColor(RGBTriple c) {
        return str.format("%.6f %.6f %.6f", c.r, c.g, c.b);
    }

    char[] objs;
    foreach (obj; definedObjects) {
        objs ~= str.format("{ image = \"%s\" side = \"%s\" }\n",obj.objid,
            obj.sideStr);
    }
    stuff["landgen_objects"] = objs;

    stuff["bordercolor"] = fmtColor(colground);
    stuff["skycolor"] = fmtColor(skyGradient.top);

    char[] levelconf = fillTemplate(LEVEL_CONF, stuff);

    version(Windows) {
        //xxx nasty hack to fix EOL characters on Windows, as backticked strings
        //contain only "\x0A" as end-of-line char
        levelconf = str.replace(levelconf, "\x0A","\x0D\x0A");
    }

    stdf.write(destPath~"level.conf", levelconf);
}

//replace each %key% in template_str by the value stuff[key]
//it fixes up indentation because the output must be pretty (HAHAHAHA)
//if the value contains a trailing \n, don't include that in the output
char[] fillTemplate(char[] template_str, char[][char[]] stuff) {
    //slow and simple
    char[] res = template_str;
    foreach (char[] key, char[] value; stuff) {
        char[] find = '%' ~ key ~ '%';
        //before inserting the value into the result string, add indentation
        //(which is why I don't use str.replace())
        int nextpos = 0;
        for (;;) {
            auto pos = str.find(res[nextpos..$], find);
            if (pos < 0)
                break;
            pos += nextpos;
            nextpos = pos + find.length;

            //find out identation
            int n = pos - 1;
            while (n >= 0) {
                if (res[n] != ' ')
                    break;
                n--;
            }
            char[] indent;
            indent.length = pos - n - 1;
            indent[] = ' ';

            //indent
            if (value.length && value[$-1] == '\n')
                value = value[0..$-1];
            value = str.join(str.split(value, "\n"), "\n" ~ indent);

            //replace
            res = res[0 .. pos] ~ value ~ res[nextpos .. $];
            nextpos = pos + value.length;
        }
    }
    return res;
}

//level.conf template (yeah, backticked string literals!)
char[] LEVEL_CONF = `//automatically created by extractdata
environment {
  require_resources {
    "debris_atlas.conf"
  }

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
    bitmaps {
      %env_bitmaps%
    }
  }

  gradient = "sky_gradient"
  backdrop = "sky_backdrop"
  skycolor = "%skycolor%"
  debris = "debris"
}

landscape {
  resources {
    bitmaps {
      %land_bitmaps%
    }
  }

  border_color = "%bordercolor%" //border_color or border_tex
  soil_tex = "soiltex" //soil_color or soil_tex
}

landscapegen {
  resources {
    bitmaps {
      %landgen_bitmaps%
    }
  }

  objects {
    %landgen_objects%
  }

  marker_textures {
    LAND = "land"
    SOLID_LAND = "solid_land"
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
}
`;

