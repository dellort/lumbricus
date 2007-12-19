module tools.untile;

import devil.image;
import path = std.path;
import stdf = std.file;
import str = std.string;
import std.stdio;
import std.stream;

///Params:
///  filename = full path to input image
///  destPath = output directory with trailing separator (has to exist)
///  imgPath = relative directory for images (no separators)
///  nameHead = Prefix for image names
///  nameTail = Suffix for image names
///  confName = filename for config file (without path), if empty no config
///             file is written
///  namefile = stream where image names are read from (one name per line,
///             can be null)
void do_untile(char[] filename, char[] destPath, char[] imgPath,
    char[] nameHead, char[] nameTail, char[] confName, Stream namefile)
{
    auto img = new Image(filename);
    char[] fnbase = path.getBaseName(path.getName(filename));

    Stream conffile;
    if (confName.length) {
        conffile = new File(destPath ~ confName, FileMode.OutNew);
        conffile.writefln("resources {");
        conffile.writefln("    bitmaps {");
    }

    if (imgPath.length > 0 && !stdf.exists(destPath ~ imgPath))
        stdf.mkdir(destPath ~ imgPath);

    int sNameIdx = 0;
    char[] getNextName() {
        if (namefile) {
            return nameHead ~ namefile.readLine() ~ nameTail;
        } else {
            return nameHead ~ fnbase ~ nameTail ~ str.toString(sNameIdx++);
        }
    }

    void saveImg(Image imgToSave) {
        char[] baseName = getNextName();
        imgToSave.save(destPath ~ imgPath ~ path.sep ~ baseName ~ ".png");
        if (conffile) {
            conffile.writefln("        %s = \"%s\"", baseName,
                imgPath ~ "/" ~ baseName ~ ".png");
        }
    }

    if (img.h > img.w) {
        int tilesize = img.w;
        for (int i = 0; i < img.h/tilesize; i ++) {
            auto imgout = new Image(tilesize, tilesize, img.alpha);
            imgout.blit(img, 0, tilesize*i, tilesize, tilesize, 0, 0);
            saveImg(imgout);
        }
    } else {
        int tilesize = img.h;
        for (int i = 0; i < img.w/tilesize; i ++) {
            auto imgout = new Image(tilesize, tilesize, img.alpha);
            imgout.blit(img, tilesize*i, 0, tilesize, tilesize, 0, 0);
            saveImg(imgout);
        }
    }

    if (conffile) {
        conffile.writefln("    }");
        conffile.writefln("}");
    }
    return 0;
}