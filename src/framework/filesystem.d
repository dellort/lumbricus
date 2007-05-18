module framework.filesystem;

import path = std.path;
import stdf = std.file;
import cstdlib = std.c.stdlib;
import str = std.string;
import std.stream;
import utils.misc;
import utils.log;
import utils.output;

private Log log;

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

///Describes where the object you are mounting resides in the physical FS
enum MountPath {
    ///Path is relative to app's data path
    data,
    ///Path is relative to users home directory
    user,
    ///Path is absolute, nothing is appended by mount()
    absolute,
}

///A handler class that registers itself with the framework
///One instance will exist, responsible for creating a HandlerInstance object
///when a path/file is mounted
protected abstract class MountPointHandler {
    ///Can this handler class mount the path/file
    ///Params:
    ///  absPath = Absolute system path to object that should be mounted
    abstract bool canHandle(char[] absPath);

    ///Mount absPath and create HandlerInstance
    ///You can assume that canHandle has been called before
    ///Params:
    ///  absPath = Absolute system path to object that should be mounted
    abstract HandlerInstance mount(char[] absPath);
}

///A mounted path/file
protected abstract class HandlerInstance {
    ///can the currently mounted path/whatever open files for writing?
    abstract bool isWritable();

    ///does the file (relative to handler object) exist and could be opened?
    abstract bool exists(char[] handlerPath);

    ///check if this path is valid (it does not have to contain files)
    abstract bool pathExists(char[] handlerPath);

    abstract Stream open(char[] handlerPath, FileMode mode);

    ///list the files (no dirs) in the path handlerPath (relative to handler object)
    ///you can assume that pathExists has been called before
    ///if callback returns false, you should abort and return false too
    abstract bool listdir(char[] handlerPath, char[] pattern, bool delegate(char[] filename) callback);
}

///Specific MountPointHandler for mounting directories
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

///Specific HandlerInstance for opening files from mounted directories
private class HandlerDirectory : HandlerInstance {
    private {
        char[] mDirPath;
    }

    this(char[] absPath) {
        if (!dirExists(absPath))
            throw new Exception("Directory doesn't exist");
        mDirPath = addTrailingPathDelimiter(absPath);
        log("New dir handler for '%s'",mDirPath);
    }

    bool isWritable() {
        return true;
    }

    bool exists(char[] handlerPath) {
        char[] p = mDirPath ~ handlerPath;
        log("Checking for existance: '%s'",p);
        return stdf.exists(p) && stdf.isfile(p);
    }

    bool pathExists(char[] handlerPath) {
        char[] p = mDirPath ~ handlerPath;
        return stdf.exists(p) && stdf.isdir(p);
    }

    Stream open(char[] handlerPath, FileMode mode) {
        log("Handler for '%s': Opening '%s'",mDirPath, handlerPath);
        return new File(mDirPath ~ handlerPath, mode);
    }

    bool listdir(char[] handlerPath, char[] pattern, bool delegate(char[] filename) callback) {
        char[] p = mDirPath ~ handlerPath;
        char[][] files = stdf.listdir(p, pattern);
        bool cont = true;
        foreach (f; files) {
            if (stdf.isfile(path.join(p,f))) {
                cont = callback(f);
                if (!cont)
                    break;
            }
        }
        return cont;
    }
}

class FileSystem {
    protected {
        ///represents a virtual path in the VFS
        struct MountedPath {
            ///the path this HandlerInstance is mounted into,
            ///relative to VFS root with leading/trailing '/'
            char[] mountPoint;
            ///handler for mounted path/file
            HandlerInstance handler;
            ///is opening files for writing/creating files supported by handler
            ///and enabled for this path
            bool isWritable;

            public static MountedPath opCall(char[] mountPoint, HandlerInstance handler, bool isWritable) {
                MountedPath ret;
                //make sure mountPoint starts and ends with a '/'
                ret.mountPoint = fixRelativePath(mountPoint);
                if (ret.mountPoint[$-1] != '/')
                    ret.mountPoint ~= '/';
                ret.handler = handler;
                ret.isWritable = isWritable && handler.isWritable();
                return ret;
            }

            ///is relPath a subdirectory of mountPoint?
            ///compares case-sensitive
            public bool matchesPath(char[] relPath) {
                log("Checking for match: '%s' and '%s'",relPath,mountPoint);
                return relPath.length>mountPoint.length && (str.cmp(relPath[0..mountPoint.length],mountPoint) == 0);
            }

            public bool matchesPathForList(char[] relPath) {
                return relPath.length>=mountPoint.length && (str.cmp(relPath[0..mountPoint.length],mountPoint) == 0);
            }

            ///Convert relPath (relative to VFS root) to a path relative to
            ///mountPoint
            public char[] getHandlerPath(char[] relPath) {
                if (matchesPath(relPath)) {
                    return relPath[mountPoint.length..$];
                } else {
                    return "";
                }
            }

            ///Check if this mountPoint supports opening files with mode
            public bool matchesMode(FileMode mode) {
                return (mode == FileMode.In || isWritable);
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
        log = registerLog("FS");
        bool stfu = true; //xxx TODO: make configureable (environment var?)
        if (stfu) {
            log("Entering STFU mode.");
            log.setBackend(DevNullOutput.output, "null");
        }
        mAppId = appId;
        initPaths(arg0);
    }

    ///Add leading and trailing slashes if necessary and replace '\' by '/'
    ///An empty path will be converted to '/'
    protected static char[] fixRelativePath(char[] p) {
        if (p.length == 0)
            p = "/";
        p = str.replace(p,"\\","/");
        if (p[0] != '/')
            p = "/" ~ p;
        return p;
    }

    ///Return path to application's executable file, with trailing '/'
    ///XXX test this on Linux
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

    ///Returns path to '.<appId>' in user's home directory
    ///Created if not existant
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

    ///initialize paths where files/folders to mount will be searched
    protected void initPaths(char[] arg0) {
        mAppPath = getAppPath(arg0);

        //user path: home directory + .appId
        mUserPath = getUserPath();
        log("PUser = '%s'",mUserPath);

        //data paths: app directory + special dirs on linux
        mDataPaths = null;
        version(linux) {
            mDataPaths ~= "/usr/local/share/" ~ mAppId ~ "/";
            mDataPaths ~= "/usr/share/" ~ mAppId ~ "/";
        }
        mDataPaths ~= mAppPath;
        //XXX really? this could cause problems if app is in C:\Program Files
        mDataPaths ~= mAppPath ~ "../data/";
        debug foreach(p; mDataPaths) {
            log("PData = '%s'",p);
        }
    }

    ///Mount file/folder path into the VFS at mountPoint
    ///Params:
    ///  mp = where in the real filesystem should be looked for path
    ///       MountPoint.data: Search data dirs
    ///       MountPoint.user: Search user dir
    ///       MountPoint.absolute: Path is absolute, leave as it is
    ///  path = path to object in the real FS, relative if specified by mp
    ///  writable = should it be possible to open files for writing
    ///             or create files in this path
    ///             if path is not physically writable, this parameter is ignored
    public void mount(MountPath mp, char[] path, char[] mountPoint, bool writable, bool prepend = false) {
        //get absolute path to object, considering mp
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

        //find a handler for this path
        MountPointHandler currentHandler = null;
        foreach (MountPointHandler h; mHandlers) {
            if (h.canHandle(absPath)) {
                currentHandler = h;
                break;
            }
        }

        if (!currentHandler)
            throw new Exception("No handler was able to mount object "~path);

        mMountedPaths ~= MountedPath(mountPoint,currentHandler.mount(absPath),writable);
    }

    ///open a stream to a file in the VFS
    ///if you try to open an existing file (mode != FileMode.OutNew), all mounted
    ///paths are searched top-down (first mounted first) until a file has been found
    ///When creating a file, it will be created in the first matching path that
    ///is writable
    ///Params:
    ///  relFilename = path to the file, relative to VFS root
    ///  mode = how the file should be opened
    public Stream open(char[] relFilename, FileMode mode = FileMode.In) {
        relFilename = fixRelativePath(relFilename);
        log("Trying to open '%s'",relFilename);
        foreach (inout MountedPath p; mMountedPaths) {
            if (p.matchesPath(relFilename) && p.matchesMode(mode)) {
                log("Found matching handler");
                char[] handlerPath = p.getHandlerPath(relFilename);
                if (p.handler.exists(handlerPath) || mode == FileMode.OutNew) {
                    //the file exists, or a new file should be created
                    return p.handler.open(handlerPath, mode);
                }
            }
        }
        throw new Exception("File not found: " ~ relFilename);
    }

    ///List files (not directories) in directory relPath
    ///Works like std.file.listdir
    ///Will not error if the path is not found
    public void listdir(char[] relPath, char[] pattern, bool delegate(char[] filename) callback) {
        relPath = fixRelativePath(relPath);
        foreach (inout MountedPath p; mMountedPaths) {
            bool cont = true;
            if (p.matchesPathForList(relPath)) {
                log("Found matching handler");
                char[] handlerPath = p.getHandlerPath(relPath);
                if (p.handler.pathExists(handlerPath)) {
                    //the path exists, list contents
                    cont = p.handler.listdir(handlerPath, pattern, callback);
                }
            }
            if (!cont)
                break;
        }
    }

    ///Check if a file exists in the VFS
    ///This will only look for files, not directories
    ///Params:
    ///  relFilename = path to file to check for existance, relative to VFS root
    public bool exists(char[] relFilename) {
        relFilename = fixRelativePath(relFilename);
        foreach (inout MountedPath p; mMountedPaths) {
            if (p.matchesPath(relFilename)) {
                char[] handlerPath = p.getHandlerPath(relFilename);
                if (p.handler.exists(handlerPath)) {
                    //file found
                    return true;
                }
            }
        }
        return false;
    }

    package static void registerHandler(MountPointHandler h) {
        mHandlers ~= h;
    }
}
