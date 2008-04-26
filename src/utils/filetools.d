module utils.filetools;

import stdf = std.file;
import path = std.path;

void remove_dir(char[] dirpath) {
    try {
        char[][] files = stdf.listdir(dirpath);
        foreach (f; files) {
            char[] fullpath = dirpath~path.sep~f;
            if (stdf.isdir(fullpath))
                remove_dir(fullpath);
            else
                stdf.remove(fullpath);
        }
        stdf.rmdir(dirpath);
    } catch {}
}

void trymkdir(char[] dir) {
    try { stdf.mkdir(dir); } catch {}
}

