module animconv;

import aconv.metadata;
import std.stdio;
import std.stream;
import stdf = std.file;
import std.string;
import std.conv;
import path = std.path;
import utils.configfile;
import utils.vector2;
import utils.output;
import wwpdata.reader_bnk;

void main(char[][] args) {
    if (args.length < 2) {
        writefln("Syntax: animconv <conffile> [<workPath>]");
        return 1;
    }
    char[] conffn = args[1];
    char[] workPath = "."~path.sep;
    if (args.length >= 3) {
        workPath = args[2]~path.sep;
    }

    void confError(char[] msg) {
        writefln(msg);
    }

    ConfigNode animConf = (new ConfigFile(new File(conffn), conffn,
         &confError)).rootnode;

    //get all animation indices that are used from one bnk file
    int[] getUsedAnimations(ConfigNode fileNode) {
        int[] res;
        foreach (ConfigNode handlerNode; fileNode) {
            foreach (char[] aniName, char[] aniNums; handlerNode) {
                char[][] values = split(aniNums);
                foreach (char[] v; values) {
                    res ~= toInt(v);
                }
            }
        }
        return res;
    }

    foreach (char[] bnkname, ConfigNode bnkNode; animConf) {
        writefln("Working on %s",bnkname);
        scope bnkf = new File(workPath ~ bnkname ~ ".bnk");
        bnkf.seek(4, SeekPos.Set);
        scope animList = readBnkFile(bnkf);
        int[] usedAnims = getUsedAnimations(bnkNode);
        bool[int] filter;
        foreach (int iani; usedAnims) {
            filter[iani] = true;
        }
        writefln();
        int maxPageIdx = animList.savePacked(workPath, bnkname, true,
            Vector2i(512, 512), filter);
        writefln();

        ConfigNode confOut = (new ConfigFile("","",&confError)).rootnode;

        auto resNode = confOut.getSubNode("resources").getSubNode("atlas")
            .getSubNode(bnkname);
        auto pageNode = resNode.getSubNode("pages");
        for (int i = 0; i <= maxPageIdx; i++) {
            pageNode.setStringValue("",bnkname ~ "/page_" ~ toString(i)
                ~ ".png");
        }
        resNode.setStringValue("meta", bnkname ~ ".meta");

        scope confst = new File(workPath ~ bnkname ~ ".conf", FileMode.OutNew);
        auto textstream = new StreamOutput(confst);
        confOut.writeFile(textstream);
    }

}












/+
    char[] curfilepat; //something which contains %s
    char[] confname;
    char[][] confout;
    Animation[] curanims;
    char[] section;

    void closeCurrent() {
        if (confname.length > 0) {
            confout ~= "}}";
            char[] flap;
            foreach (foo; confout) {
                flap ~= foo ~ "\n";
            }
            write(confname, flap);
            curfilepat = null;
            confname = null;
            confout = null;
            curanims = null;
            section = null;
        }
    }

    for (;;) {
        if (cur == "=end") {
            closeCurrent();
            break;
        } else if (cur[0] == '=') {
            closeCurrent();
            //new anim file or directory/name (produced by unworms)
            curfilepat = cur[1..$] ~ "/anim_#.png";
            curanims = loadMeta(cur[1..$] ~ ".meta");
	    confout ~= "//automatically created by animconv/convani.d";
	    confout ~= "//edit animations.txt instead";
            confout ~= "resources { animations {";
            confname = cur[1..$] ~ ".conf";
        } else if (cur[0] == '+') {
            section = cur[1..$];
        } else if (cur[0] == '.') {
            //name offset1 offset2 ...
            char[][] params = split(cur[1..$]);
            assert(params.length >= 2);
            int[] images;
            foreach(char[] p; params[1..$]) {
                images ~= toInt(p);
            }
            int ani1 = images[0];
            confout ~= "    " ~ params[0] ~ " {";
            confout ~= "        handler = \"" ~ section ~ "\"";
            confout ~= "        width = \"" ~ toString(curanims[ani1].desc.w) ~ "\"";
            confout ~= "        height = \"" ~ toString(curanims[ani1].desc.h) ~ "\"";
            confout ~= "        flags = \"" ~ toString(curanims[ani1].desc.flags) ~ "\"";
            confout ~= "        path = \"" ~ curfilepat ~ "\"";
            confout ~= "        imagecount = \"" ~ toString(images.length) ~ "\"";
            foreach(int index, int i; images) {
                confout ~= "        image_" ~ toString(index) ~ " = \""
                    ~ toString(i) ~ "\"";
                confout ~= "        frames_" ~ toString(index) ~ " = \""
                    ~ toString(curanims[i].desc.framecount) ~ "\"";
            }
            confout ~= "    }";
	} else if (cur[0] == '#') {
	    //skip comment
        } else {
            assert(false);
        }

        nextLine();
    }
}
+/
