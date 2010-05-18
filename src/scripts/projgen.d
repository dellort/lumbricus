module projgen;

/**
 * Updates a project file by parsing the dmd -deps output.
 * The filelist in the passed project will be replaced.
 *
 * Supports: CodeBlocks, VisualD
 *
 * Call: projgen <ProjectFile>  < depfile
 * Make sure you call dmd from the right path when generating the depfile
 *   (i.e. where the project file is)
 */

import tango.io.Console;
import tango.io.Stdout;
import tango.text.Util;
import tango.text.Regex;
import tango.core.Array : sort, distinct;
import tango.text.Ascii : icompare;
import tango.io.device.File;
import tango.io.stream.TextFile;
import tango.io.stream.Format;
import tango.io.FilePath;

//xxx can it really take 2 seconds to parse that Regex??? program start is slow
Regex gReDepLine;
static this() {
    gReDepLine= Regex(r"^(\S+) \(([^\)]+)\) : [^:]+ : (\S+) \(([^\)]+)\).*$");
}

//Parses a line from the depfile by dmd
struct DepLine {
    char[] modulename;
    char[] filename;
    char[] impModule;
    char[] impFilename;

    static DepLine opCall(char[] line) {
        DepLine ret;
        if (gReDepLine.test(line)) {
            ret.modulename = gReDepLine.match(1).dup;
            ret.filename = unescape(gReDepLine.match(2));
            ret.impModule = gReDepLine.match(3).dup;
            ret.impFilename = unescape(gReDepLine.match(4));
        }
        return ret;
    }

    void dbg() {
        Stdout.formatln("{} {}", modulename, filename);
        Stdout.formatln("{} {}", impModule, impFilename);
    }
}

//A referenced module
struct Module {
    char[] id;
    char[] filename;

    int opCmp(Module other) {
        return icompare(filename, other.filename);
    }

    int opEquals(Module other) {
        return icompare(filename, other.filename) == 0;
    }
}

//CodeBlocks projects just contain a filelist; CB does the work of making
//  a file tree
void processCodeblocks(char[] input, FormatOutput!(char) output, Module[] modules) {
    bool skip = false;
    foreach (line; lines(input)) {
        if (line.length == 0)
            continue;
        if (line == "\t\t<Extensions>") {
            skip = false;
        }
        if (!skip)
            output(line).newline;
        if (line == "\t\t</Build>") {
            skip = true;
            foreach (ref mod; modules) {
                output.formatln("\t\t<Unit filename=\"{}\" />", mod.filename);
            }
        }
    }
}

//XML tree structure in the project file that needs to be generated
void processVisuald(char[] input, FormatOutput!(char) output, Module[] modules) {
    struct Folder {
        char[] name;
        Folder[] sub;
        char[][] files;

        void add(char[] id, char[] fn) {
            uint p = locate(id, '.');
            if (p < id.length) {
                char[] folder = id[0..p];
                foreach (ref f; sub) {
                    if (f.name == folder) {
                        f.add(id[p+1..$], fn);
                        return;
                    }
                }
                sub ~= Folder(folder.dup, null, null);
                sub[$-1].add(id[p+1..$], fn);
            } else {
                files ~= fn;
            }
        }

        void write(char[] indent, FormatOutput!(char) output) {
            output.formatln("{}<Folder name=\"{}\">", indent, name);
            foreach (ref fld; sub) {
                fld.write(indent ~ ' ', output);
            }
            foreach (fn; files) {
                output.formatln("{} <File path=\"{}\" />", indent, fn);
            }
            output.formatln("{}</Folder>", indent);
        }
    }
    Folder root;
    root.name = "Root";
    foreach (ref mod; modules) {
        root.add(mod.id, mod.filename);
    }

    bool skip = false;
    foreach (line; lines(input)) {
        if (line.length == 0)
            continue;
        if (line == "</DProject>") {
            skip = false;
        }
        if (!skip)
            output(line).newline;
        if (line == " </Config>") {
            skip = true;
            root.write(" ", output);
        }
    }
}

enum ProjType {
    codeblocks,
    visuald,
}

int main(char[][] args)
{
    if (args.length < 2) {
        Stdout("Syntax: projgen <ProjectFileToUpdate>").newline;
        Stdout("Pipe in dmd depfile.").newline;
        return 1;
    }
    char[] projFile = args[1];
    ProjType projType;

    if (FilePath(projFile).ext() == "cbp")
        projType = ProjType.codeblocks;
    else if (FilePath(projFile).ext() == "visualdproj")
        projType = ProjType.visuald;
    else {
        Stdout("Unknown project file type.");
        return 1;
    }
    //Cache project file (will be overwritten)
    char[] projectIn = cast(char[])File.get(projFile);

    //Parse depfile
    char[] line;
    DepLine[] deps;
    while (Cin.readln(line)) {
        auto dep = DepLine(line);
        if (dep.modulename.length == 0)
            break;
        deps ~= dep;
    }
    if (deps.length == 0) {
        Stdout("Invalid depfile.");
        return 1;
    }

    //Flatten depfile (we only want the file list)
    Module[] modules;
    foreach (ref dep; deps) {
        if (!FilePath(dep.filename).isAbsolute())
            modules ~= Module(dep.modulename, dep.filename);
        if (!FilePath(dep.impFilename).isAbsolute())
            modules ~= Module(dep.impModule, dep.impFilename);
    }
    //Sort by filename and eliminate duplicates
    modules.sort();
    modules.length = modules.distinct();
    Stdout.formatln("{} modules", modules.length);

    //Write output; replace filelist, preserve everything else
    auto projectOut = new TextFileOutput(projFile, File.WriteCreate);
    scope(exit)projectOut.flush();
    if (projType == ProjType.codeblocks)
        processCodeblocks(projectIn, projectOut, modules);
    else
        processVisuald(projectIn, projectOut, modules);

    return 0;
}
