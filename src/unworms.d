module unworms;

import std.stdio;
import wwptools.unworms;

int main(string[] args)
{
    if (args.length < 2) {
        writefln("Syntax: unworms <wormsFile> [<outputDir>]");
        return 1;
    }
    string outputDir;
    if (args.length >= 3)
        outputDir = args[2];
    else
        outputDir = ".";

    do_unworms(args[1], outputDir);

    return 0;
}
