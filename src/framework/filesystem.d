module framework.filesystem;

import path = std.path;
import stdf = std.file;
import cstdlib = std.c.stdlib;
import str = std.string;
import std.stream;

///add OS-dependant path delimiter to pathStr, if not there
public char[] addTrailingPathDelimiter(char[] pathStr) {
    if (pathStr[$-1] != path.sep[0]) {
        pathStr ~= path.sep;
    }
    return pathStr;
}

///return true if dir exists and is a directory, false otherwise
public bool dirExists(char[] dir) {
    if (stdf.exists(dir) && stdf.isdir(dir))
        return true;
    else
        return false;
}

enum MountPath {
    data,
    user,
    absolute,
}

private abstract class MountPointHandler {
    abstract bool canHandle(char[] absPath);

    abstract HandlerInstance mount(char[] absPath);
}

private abstract class  HandlerInstance {
    abstract bool isWritable();
}

private class MountPointHandlerDirectory : MountPointHandler {
    bool canHandle(char[] absPath) {
        return dirExists(absPath);
    }

    HandlerInstance mount(char[] absPath) {
        if (canHandle(absPath)) {
            return new HandlerDirectory(absPath);
        }
    }

    static this() {
        FileSystem.registerHandler(new MountPointHandlerDirectory());
    }
}

private class HandlerDirectory : HandlerInstance {
    this(char[] absPath) {
    }

    bool isWritable() {
        return true;
    }
}

abstract class FileSystem {
    protected {
        struct MountedPath {
            char[] mountPoint;
            HandlerInstance handler;
            bool isWritable;

            public static MountedPath opCall(char[] mountPoint, HandlerInstance handler, bool isWritable) {
                MountedPath ret;
                ret.mountPoint = mountPoint;
                ret.handler = handler;
                ret.isWritable = isWritable && handler.isWritable();
                return ret;
            }
        }

        char[] mAppId;
        char[] mAppPath;
        char[] mUserPath;
        char[][] mDataPaths;
        MountedPath[] mMountedPaths;

        static MountPointHandler[] mHandlers;
    }

    this(char[] arg0, char[] appId) {
        mAppId = appId;
        initPaths(arg0);
    }

    protected char[] getAppPath(char[] arg0) {
        char[] appPath;
        version(Windows) {
            //win: args[0] contains full path to executable
            appPath = path.getDirName(arg0);
        } else {
            //lin: args[0] is relative to current directory
            char[] curDir = addTrailingPathDelimiter(stdf.getcwd());
            char[] dirname = path.getDirName(arg0);
            if (dirname.length > 0 && dirname[0] == path.sep[0]) {
                //sometimes, the path is absolute
                appPath = dirname;
            } else if (dirname != ".") {
                appPath = curDir ~ dirname;
            } else {
                appPath = curDir;
            }
        }

        appPath = addTrailingPathDelimiter(appPath);
        return appPath;
    }

    ///Assuming mAppPath is already initalized
    protected char[] getUserPath() {
        char[] userPath;

        //set user directory from os home path
        char* home = null;
        version(Windows) {
            //windows: Docs & Settings\AppData\.lumbricus
            home = cstdlib.getenv("APPDATA");
        } else {
            //linux: ~/.lumbricus
            home = cstdlib.getenv("HOME");
        }
        if (home != null)
            //append ".lumbricus"
            userPath = addTrailingPathDelimiter(str.toString(home)) ~ mAppId;
        else
            //failed to get env var? then use AppPath/.lumbricus instead
            userPath = mAppPath ~ mAppId;

        //try to create user directory
        try {
            stdf.mkdir(userPath);
        } catch (stdf.FileException e) {
            //directory already exists, do nothing
        }
        return userPath;
    }

    protected void initPaths(char[] arg0) {
        mAppPath = getAppPath(arg0);

        mUserPath = getUserPath();

        mDataPaths = null;
        version(linux) {
            mDataPaths ~= "/usr/local/share/" ~ mAppId ~ "/";
            mDataPaths ~= "/usr/share/" ~ mAppId ~ "/";
        }
        mDataPaths ~= mAppPath ~ "../bin/";
    }

    public void mountDirectory(MountPath mp, char[] path, char[] mountPoint, bool writable, bool prepend = false) {
        char[] absPath;
        switch (mp) {
            case MountPath.data:
                foreach (char[] p; mDataPaths) {
                    absPath = p ~ path;
                    if (stdf.exists(absPath))
                        break;
                }
                break;
            case MountPath.user:
                absPath = mUserPath ~ mountPoint;
                break;
            case MountPath.absolute:
                absPath = path;
                break;
        }
        if (!stdf.exists(absPath))
            throw new Exception("Failed to mount "~path~": Path/file not found");

        MountPointHandler currentHandler = null;
        foreach (MountPointHandler h; mHandlers) {
            if (h.canHandle(absPath)) {
                currentHandler = h;
                break;
            }
        }

        if (!currentHandler)
            throw new Exception("No handler was able to mount object "~path);

        mMountedPaths ~= MountedPath(path,currentHandler.mount(absPath),writable);
    }

    public abstract Stream open(char[] relFilename, FileMode mode = FileMode.In);

    public abstract bool exists(char[] filename);

    package static void registerHandler(MountPointHandler h) {
        mHandlers ~= h;
    }
}
