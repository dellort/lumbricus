module utils.filetools;

public import std.file;

/+
void remove_dir(string dirpath) {
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
+/

void trymkdir(string dir) {
    try { mkdirRecurse(dir); } catch {}
}
