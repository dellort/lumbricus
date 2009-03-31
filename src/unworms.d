module unworms;

import tango.io.Stdout;
import wwptools.unworms;

int main(char[][] args)
{
    if (args.length < 2) {
        Stdout("Syntax: unworms <wormsFile> [<outputDir>]").newline;
        return 1;
    }
    char[] outputDir;
    if (args.length >= 3)
        outputDir = args[2];
    else
        outputDir = ".";

    do_unworms(args[1], outputDir);

    return 0;
}
