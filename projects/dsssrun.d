module dsss;

version(Tango) {
    import tango.stdc.stdlib;
    import tango.stdc.stringz;
    import tango.io.FileSystem;
} else {
    import std.file;
    import std.process;
}

const cSrcDir = "../src";

void main(char[][] args) {
    version(Tango) {
        FileSystem.setDirectory(cSrcDir);
    } else {
        chdir(cSrcDir);
    }
    char[] argstr;
    foreach (char[] a; args[1..$])
        argstr ~= a~" ";
    version(Tango) {
        system(toStringz("dsss "~argstr));
    } else {
        system("dsss "~argstr);
    }
}
