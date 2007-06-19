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

//Uncomment this to see detailed filesystem log messages
//version = FSDebug;

///add OS-dependant path delimiter to pathStr, if not there
public char[] addTrailingPathDelimiter(char[] pathStr) {
version(Windows) {
    if (pathStr[$-1] != '/' && pathStr[$-1] != '\\') {
        pathStr ~= '/';
    }
} else {
    if (pathStr[$-1] != '/') {
        pathStr ~= '/';
    }
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
    ///listing should be non-recursive, and return files without path
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
        version(FSDebug) log("New dir handler for '%s'",mDirPath);
    }

    bool isWritable() {
        return true;
    }

    bool exists(char[] handlerPath) {
        char[] p = mDirPath ~ handlerPath;
        version(FSDebug) log("Checking for existance: '%s'",p);
        return stdf.exists(p) && stdf.isfile(p);
    }

    bool pathExists(char[] handlerPath) {
        char[] p = mDirPath ~ handlerPath;
        return stdf.exists(p) && stdf.isdir(p);
    }

    Stream open(char[] handlerPath, FileMode mode) {
        version(FSDebug) log("Handler for '%s': Opening '%s'",mDirPath, handlerPath);
        return new File(mDirPath ~ handlerPath, mode);
    }

    bool listdir(char[] handlerPath, char[] pattern, bool delegate(char[] filename) callback) {
        bool cont = true;
        bool listdircb(stdf.DirEntry* de) {
            if (!stdf.isdir(de.name)) {
                //listdir does a path.join with searchpath and found file, remove this
                char[] fn = de.name[mDirPath.length..$];
version(Windows) {
                if (fn.length>0 && (fn[0] == '/' || fn[0] == '\\')) {
                    fn = fn[1..$];
                }
} else {
                if (fn.length>0 && fn[0] == '/') {
                    fn = fn[1..$];
                }
}
                if (std.path.fnmatch(fn, pattern))
                    return (cont = callback(fn));
            } else {
                return true;
            }
        }

        char[] p = mDirPath ~ handlerPath;
        stdf.listdir(p, &listdircb);
        return cont;
    }
}

private class HandlerLink : HandlerInstance {
    private char[] mLinkedPath;
    private FileSystem mParent;

    this(FileSystem parent, char[] relPath) {
        version(FSDebug) log("New link: %s",relPath);
        mLinkedPath = relPath;
        mParent = parent;
    }

    bool isWritable() {
        version(FSDebug) log("Link: isWritable");
        return mParent.pathIsWritable(mLinkedPath, this);
    }

    bool exists(char[] handlerPath) {
        version(FSDebug) log("Link: exists(%s)",handlerPath);
        return mParent.exists(mLinkedPath ~ handlerPath, this);
    }

    bool pathExists(char[] handlerPath) {
        version(FSDebug) log("Link: pathexists(%s)",handlerPath);
        return mParent.pathExists(mLinkedPath ~ handlerPath, this);
    }

    Stream open(char[] handlerPath, FileMode mode) {
        version(FSDebug) log("Link: open(%s)",handlerPath);
        return mParent.open(mLinkedPath ~ handlerPath, mode, this);
    }

    bool listdir(char[] handlerPath, char[] pattern, bool delegate(char[] filename) callback) {
        return mParent.listdir(mLinkedPath ~ handlerPath, pattern, callback, this);
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
            private bool mWritable;

            public static MountedPath opCall(char[] mountPoint, HandlerInstance handler, bool writable) {
                MountedPath ret;
                //make sure mountPoint starts and ends with a '/'
                ret.mountPoint = fixRelativePath(mountPoint) ~ '/';
                ret.handler = handler;
                ret.mWritable = writable;
                return ret;
            }

            public bool isWritable() {
                return mWritable && handler.isWritable();
            }

            ///is relPath a subdirectory of mountPoint?
            ///compares case-sensitive
            public bool matchesPath(char[] relPath) {
                version(FSDebug) log("Checking for match: '%s' and '%s'",relPath,mountPoint);
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
            version(FSDebug) log("Entering STFU mode.");
            log.setBackend(DevNullOutput.output, "null");
        }
        mAppId = appId;
        initPaths(arg0);
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
        version(FSDebug) log("PUser = '%s'",mUserPath);

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
            version(FSDebug) log("PData = '%s'",p);
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

        if (prepend)
            mMountedPaths = MountedPath(mountPoint,currentHandler.mount(absPath),writable) ~ mMountedPaths;
        else
            mMountedPaths ~= MountedPath(mountPoint,currentHandler.mount(absPath),writable);
    }

    ///Try mounting a file/folder and return if the mount succeeded
    public bool tryMount(MountPath mp, char[] path, char[] mountPoint, bool writable, bool prepend = false) {
        try {
            mount(mp, path, mountPoint, writable, prepend);
            return true;
        } catch {
            return false;
        }
    }
    ///Create a symbolic link from mountPoint to relPath
    ///relPath cannot be a parent directory of mountPoint
    ///Example:
    ///  link("/locale/de","/")
    ///Path is not checked for existance
    public void link(char[] relPath, char[] mountPoint, bool prepend = false) {
        relPath = fixRelativePath(relPath) ~ '/';
        mountPoint = fixRelativePath(mountPoint) ~ '/';
        if (relPath.length <= mountPoint.length && mountPoint[0..relPath.length] == relPath) {
            throw new Exception("Can't link to a direct or indirect parent directory");
        }
        if (prepend)
            mMountedPaths = MountedPath(mountPoint,new HandlerLink(this, relPath),true) ~ mMountedPaths;
        else
            mMountedPaths ~= MountedPath(mountPoint,new HandlerLink(this, relPath),true);
    }

    ///open a stream to a file in the VFS
    ///if you try to open an existing file (mode != FileMode.OutNew), all mounted
    ///paths are searched top-down (first mounted first) until a file has been found
    ///When creating a file, it will be created in the first matching path that
    ///is writable
    ///Params:
    ///  relFilename = path to the file, relative to VFS root
    ///  mode = how the file should be opened
    //need to make caller parameter public
    public Stream open(char[] relFilename, FileMode mode = FileMode.In,
        HandlerInstance caller = null)
    {
        relFilename = fixRelativePath(relFilename);
        version(FSDebug) log("Trying to open '%s'",relFilename);
        foreach (inout MountedPath p; mMountedPaths) {
            if (p.handler == caller)
                continue;
            if (p.matchesPath(relFilename) && p.matchesMode(mode)) {
                version(FSDebug) log("Found matching handler");
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
    ///Returns:
    /// false if listing was aborted, true otherwise
    public bool listdir(char[] relPath, char[] pattern,
        bool delegate(char[] filename) callback)
    {
        return listdir(relPath, pattern, callback, null);
    }

    protected bool listdir(char[] relPath, char[] pattern,
        bool delegate(char[] filename) callback, HandlerInstance caller)
    {
        relPath = fixRelativePath(relPath) ~ '/';
        bool cont = true;
        foreach (inout MountedPath p; mMountedPaths) {
            if (p.handler == caller)
                continue;
            if (p.matchesPathForList(relPath)) {
                version(FSDebug) log("Found matching handler");
                char[] handlerPath = p.getHandlerPath(relPath);
                if (p.handler.pathExists(handlerPath)) {
                    //the path exists, list contents
                    cont = p.handler.listdir(handlerPath, pattern, callback);
                }
            }
            if (!cont)
                break;
        }
        return cont;
    }

    ///Check if a file exists in the VFS
    ///This will only look for files, not directories
    ///Params:
    ///  relFilename = path to file to check for existance, relative to VFS root
    public bool exists(char[] relFilename) {
        return exists(relFilename, null);
    }

    protected bool exists(char[] relFilename, HandlerInstance caller) {
        relFilename = fixRelativePath(relFilename);
        foreach (inout MountedPath p; mMountedPaths) {
            if (p.handler == caller)
                continue;
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


    ///Check if a directory exists in the VFS
    public bool pathExists(char[] relPath) {
        return pathExists(relPath, null);
    }

    protected bool pathExists(char[] relPath, HandlerInstance caller) {
        relPath = fixRelativePath(relPath) ~ '/';
        foreach (inout MountedPath p; mMountedPaths) {
            if (p.handler == caller)
                continue;
            if (p.matchesPathForList(relPath)) {
                char[] handlerPath = p.getHandlerPath(relPath);
                if (p.handler.pathExists(handlerPath)) {
                    //path exists
                    return true;
                }
            }
        }
        return false;
    }

    public bool pathIsWritable(char[] relPath) {
        return pathIsWritable(relPath, null);
    }

    protected bool pathIsWritable(char[] relPath, HandlerInstance caller) {
        relPath = fixRelativePath(relPath) ~ '/';
        foreach (inout MountedPath p; mMountedPaths) {
            if (p.handler == caller)
                continue;
            if (p.matchesPathForList(relPath)) {
                if (p.isWritable()) {
                    //writable path found
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
