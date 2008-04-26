module animconv;

import std.stdio;
import std.stream;
import stdf = std.file;
import path = std.path;
import utils.configfile;
import wwptools.animconv;

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

    do_animconv(animConf, workPath);
}
