module utils.filetools;

import tango.io.model.IFile : FileConst;
import path = tango.io.Path;
import tango.io.FilePath;

void remove_dir(char[] dirpath) {
    try {
        foreach (f; path.children(dirpath)) {
            if (f.folder)
                remove_dir(f.path ~ f.name);
            else
                path.remove(f.path ~ f.name);
        }
        path.remove(dirpath);
    } catch {assert(false);} //xxx: someone remove this
}

void trymkdir(char[] dir) {
    try { path.createFolder(dir); } catch {}
}

char[] basename(char[] f) {
    //return path.getBaseName(path.getName(filename));
    return FilePath(f).name;
}
