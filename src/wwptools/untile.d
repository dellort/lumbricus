module wwptools.untile;

import wwptools.image;
import utils.stream;
import utils.configfile;
import utils.output : TangoStreamOutput; //silly wrapper
import utils.filetools;
import utils.misc;

import tango.io.FilePath;
import tango.io.vfs.model.Vfs;

import tango.io.model.IFile : FileConst;
const pathsep = FileConst.PathSeparatorChar;

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
///in-memory-version:
///  img = instead of filename
///  filename = to get the name of the thing (filename is never opened or so)
void do_untile(char[] filename, VfsFolder destFolder, char[] imgPath,
    char[] nameHead, char[] nameTail, char[] confName, Stream namefile)
{
    scope auto img = new Image(filename);
    do_untile(img, filename, destFolder, imgPath, nameHead, nameTail, confName,
        namefile);
}
void do_untile(Image img, char[] filename, VfsFolder destFolder, char[] imgPath,
    char[] nameHead, char[] nameTail, char[] confName, Stream namefile)
{
    scope buffer = new void[2*1024*1024];
    char[] fnbase = FilePath(filename).name;
    //path.getBaseName(path.getName(filename));

    char[][] names = str.splitlines(cast(char[])namefile.readAll());

    ConfigNode conffile, bmps;
    if (confName.length) {
        conffile = new ConfigNode();
        auto s = conffile.getSubNode("resources");
        s.comment = "//Automatically generated by untile";
        bmps = s.getSubNode("bitmaps");
    }

    auto imgFolder = destFolder;
    if (imgPath.length > 0)
        imgFolder = destFolder.folder(imgPath).create;

    int sNameIdx = 0;
    char[] getNextName() {
        if (names.length) {
            return nameHead ~ names[sNameIdx++] ~ nameTail;
        } else {
            return nameHead ~ fnbase ~ nameTail ~ myformat("{}", sNameIdx++);
        }
    }

    void saveImg(Image imgToSave) {
        char[] baseName = getNextName();
        auto f = imgFolder.file(baseName ~ ".png").create.output;
        scope(exit) f.close();
        //eh, so we don't like checking return values?
        imgToSave.saveTo(new ConduitStream(f));
        if (conffile) {
            bmps.setStringValue(baseName, imgPath ~ "/" ~ baseName ~ ".png");
        }
    }

    if (img.h > img.w) {
        int tilesize = img.w;
        for (int i = 0; i < img.h/tilesize; i ++) {
            auto imgout = new Image(tilesize, tilesize);
            imgout.blit(img, 0, tilesize*i, tilesize, tilesize, 0, 0);
            saveImg(imgout);
        }
    } else {
        int tilesize = img.h;
        for (int i = 0; i < img.w/tilesize; i ++) {
            auto imgout = new Image(tilesize, tilesize);
            imgout.blit(img, tilesize*i, 0, tilesize, tilesize, 0, 0);
            saveImg(imgout);
        }
    }

    if (conffile) {
        scope outp = destFolder.file(confName).create.output;
        conffile.writeFile(new TangoStreamOutput(outp));
    }
}
