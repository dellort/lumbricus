module dsss;

import std.file;
import std.process;

const cSrcDir = "../src";

void main(char[][] args) {
    chdir(cSrcDir);
    char[] argstr;
    foreach (char[] a; args[1..$])
        argstr ~= a~" ";
    system("dsss "~argstr);
}
