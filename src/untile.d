module untile;

import wwptools.untile;
import path = std.path;
import stdf = std.file;
import str = std.string;
import std.stdio;
import std.stream;

int main(char[][] args) {
    if (args.length < 2) {
        writefln("Syntax: untile <imgFile> <argument>*");
        writefln("Arguments:");
        writefln("  [-h<nameHead>]       Prepend to filename");
        writefln("  [-t<nameTail>]       Append to filename");
        writefln("  [-f<namesFile>]      Read filenames from <namesFile>");
        writefln("  [-d<imageDirectory>] Write images to <imageDirectory>");
        writefln("  [-c<confFile>]       Write resources config file");
        return 1;
    }

    Stream namefile;
    char[] nameTail = "_t";
    char[] nameHead = "";
    char[] imgPath = "";
    char[] confName = "";

    //char[] fnpath = path.getDirName(args[1]);
    char[] fnpath = "." ~ path.sep;

    void parseArg(char[] arg) {
        if (arg.length < 2)
            return;
        switch (arg[0..2]) {
            case "-h":
                nameHead = arg[2..$].dup;
                break;
            case "-t":
                nameTail = arg[2..$].dup;
                break;
            case "-f":
                namefile = new File(arg[2..$]);
                break;
            case "-d":
                imgPath = arg[2..$].dup;
                break;
            case "-c":
                confName = arg[2..$];
                break;
            default:
                writefln("Invalid argument: %s",arg);
        }
    }

    for (int i = 2; i < args.length; i++) {
        parseArg(args[i]);
    }

    do_untile(args[1], fnpath, imgPath, nameHead, nameTail, confName, namefile);

    return 0;
}
