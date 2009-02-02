module framework.filesystem;

import str = stdx.string;
import stdx.stream;
import tango.util.PathUtil;
import tfs = tango.io.FileSystem;
import tango.io.FilePath;
import tpath = tango.io.Path;
import tango.core.Exception : IOException;
import utils.misc;
import utils.log;
import utils.output;
import utils.path;

version (Tango) {
    import cstdlib = tango.stdc.stdlib;
} else {
    import cstdlib = std.c.stdlib;
}

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

class FilesystemException : Exception {
    this(char[] m) {
        super(m);
    }
}

///return true if dir exists and is a directory, false otherwise
public bool dirExists(char[] dir) {
    if (tpath.exists(dir) && tpath.isFolder(dir))
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
    abstract bool exists(VFSPath handlerPath);

    ///check if this path is valid (it does not have to contain files)
    abstract bool pathExists(VFSPath handlerPath);

    abstract Stream open(VFSPath handlerPath, FileMode mode);

    ///list the files (no dirs) in the path handlerPath (relative to handler
    ///object)
    ///listing should be non-recursive, and return files without path
    ///you can assume that pathExists has been called before
    ///if findDir is true, also find directories
    ///if callback returns false, you should abort and return false too
    abstract bool listdir(VFSPath handlerPath, char[] pattern, bool findDir,
        bool delegate(char[] filename) callback);
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
            throw new FilesystemException("Directory doesn't exist");
        mDirPath = addTrailingPathDelimiter(absPath);
        version(FSDebug) log("New dir handler for '%s'",mDirPath);
    }

    bool isWritable() {
        return true;
    }

    bool exists(VFSPath handlerPath) {
        char[] p = handlerPath.makeAbsolute(mDirPath);
        version(FSDebug) log("Checking for existance: '%s'",p);
        return tpath.exists(p) && !tpath.isFolder(p);
    }

    bool pathExists(VFSPath handlerPath) {
        char[] p = handlerPath.makeAbsolute(mDirPath);
        return tpath.exists(p) && tpath.isFolder(p);
    }

    private void createPath(VFSPath handlerPath) {
        if (!pathExists(handlerPath)) {
            if (handlerPath.isEmpty())
                throw new Exception("createPath error: handler"
                    ~ " path does not exist");
            //recursively create parent dir
            createPath(handlerPath.parent);
            //create last path
            tpath.createFolder(handlerPath.makeAbsolute(mDirPath));
        }
    }

    Stream open(VFSPath handlerPath, FileMode mode) {
        version(FSDebug) log("Handler for '%s': Opening '%s'",mDirPath,
            handlerPath);
        if (mode == FileMode.OutNew) {
            //make sure path exists
            createPath(handlerPath.parent);
        }
        return new File(handlerPath.makeAbsolute(mDirPath), mode);
    }

    bool listdir(VFSPath handlerPath, char[] pattern, bool findDirs,
        bool delegate(char[] filename) callback)
    {
        char[] searchPath = handlerPath.makeAbsolute(mDirPath);

        foreach (de; tpath.children(searchPath)) {
            if (findDirs || !de.folder) {
                //listdir does a path.join with searchpath and found file,
                //remove this
                VFSPath vfn = VFSPath(de.name);
                //add trailing '/' for directories
                char[] fn = vfn.get(false, de.folder);
                //match search pattern
                if (patternMatch(fn, pattern)) {
                    if (!callback(fn))
                        return false;
                }
            }
        }

        return true;
    }
}

private class HandlerLink : HandlerInstance {
    private VFSPath mLinkedPath;
    private FileSystem mParent;

    this(FileSystem parent, VFSPath relPath) {
        version(FSDebug) log("New link: %s",relPath);
        mLinkedPath = relPath;
        mParent = parent;
    }

    bool isWritable() {
        version(FSDebug) log("Link: isWritable");
        return mParent.pathIsWritable(mLinkedPath, this);
    }

    bool exists(VFSPath handlerPath) {
        version(FSDebug) log("Link: exists(%s)",handlerPath);
        return mParent.exists(mLinkedPath.join(handlerPath), this);
    }

    bool pathExists(VFSPath handlerPath) {
        version(FSDebug) log("Link: pathexists(%s)",handlerPath);
        return mParent.pathExists(mLinkedPath.join(handlerPath), this);
    }

    Stream open(VFSPath handlerPath, FileMode mode) {
        version(FSDebug) log("Link: open(%s)",handlerPath);
        return mParent.open(mLinkedPath.join(handlerPath), mode, this);
    }

    bool listdir(VFSPath handlerPath, char[] pattern, bool findDirs,
        bool delegate(char[] filename) callback)
    {
        return mParent.listdir(mLinkedPath.join(handlerPath), pattern, findDirs,
            callback, this);
    }
}

class FileSystem {
    protected {
        ///represents a virtual path in the VFS
        struct MountedPath {
            ///the path this HandlerInstance is mounted into,
            ///relative to VFS root with leading/trailing '/'
            VFSPath mountPoint;
            ///precedence of virtual directory
            ///if multiple paths match, lower precedence is considered first
            uint precedence;
            ///handler for mounted path/file
            HandlerInstance handler;
            ///is opening files for writing/creating files supported by handler
            ///and enabled for this path
            private bool mWritable;

            public static MountedPath opCall(VFSPath mountPoint, uint precedence,
                HandlerInstance handler, bool writable)
            {
                MountedPath ret;
                //make sure mountPoint starts and ends with a '/'
                ret.mountPoint = mountPoint;
                ret.precedence = precedence;
                ret.handler = handler;
                ret.mWritable = writable;
                return ret;
            }

            public bool isWritable() {
                return mWritable && handler.isWritable();
            }

            ///is relPath a subdirectory of mountPoint?
            ///compares case-sensitive
            public bool matchesPath(VFSPath other) {
                version(FSDebug) log("Checking for match: '%s' and '%s'",
                    other,mountPoint);
                return mountPoint.isChild(other);
            }

            public bool matchesPathForList(VFSPath other) {
                return mountPoint.isChildOrEqual(other);
            }

            ///Convert other (relative to VFS root) to a path relative to
            ///mountPoint
            public VFSPath getHandlerPath(VFSPath other) {
                return other.relativePath(mountPoint);
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
    protected char[] getAppPath(char[] arg0) {
        char[] appPath;
        //on win and lin, args[0] is the (sometimes relative to cwd, sometimes
        //  absolute) path to the executable
        char[] curDir = addTrailingPathDelimiter(tfs.FileSystem.getDirectory());
        auto exePath = new FilePath(arg0);
        if (exePath.isAbsolute()) {
            //sometimes, the path is absolute
            appPath = exePath.path;
        } else {
            appPath = normalize(FilePath.join(exePath.path, curDir));
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
            tpath.createFolder(userPath);
        } catch (IOException e) {
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

    //find array index after which to insert new MountedPath with precedence
    //does a binary search, returns -1 for an empty array
    private int findInsertIndex(uint prec) {
        int l = 0, r = mMountedPaths.length-1;
        while (l <= r) {
            int m = (l + r) / 2;
            if (mMountedPaths[m].precedence < prec) {
                l = m + 1;
            } else if (mMountedPaths[m].precedence > prec) {
                r = m - 1;
            } else {
                return m;
            }
        }
        return r;
    }

    private void addMountedPath(MountedPath m) {
        int i = findInsertIndex(m.precedence);
        //the following line should work for all cases, even an empty array
        mMountedPaths = mMountedPaths[0..i+1] ~ m ~ mMountedPaths[i+1..$];
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
    ///             if path is not physically writable, this parameter is
    ///             ignored
    public void mount(MountPath mp, char[] sysPath, VFSPath mountPoint,
        bool writable, uint precedence = 0)
    {
        //get absolute path to object, considering mp
        char[] absPath;
        switch (mp) {
            case MountPath.data:
                foreach (char[] p; mDataPaths) {
                    absPath = p ~ sysPath;
                    if (tpath.exists(absPath))
                        break;
                }
                break;
            case MountPath.user:
                absPath = mUserPath ~ sysPath;
                break;
            case MountPath.absolute:
                absPath = sysPath;
                break;
        }
        if (!tpath.exists(absPath))
            throw new FilesystemException("Failed to mount "~sysPath
                ~": Path/file not found");

        //find a handler for this path
        MountPointHandler currentHandler = null;
        foreach (MountPointHandler h; mHandlers) {
            if (h.canHandle(absPath)) {
                currentHandler = h;
                break;
            }
        }

        if (!currentHandler)
            throw new FilesystemException("No handler was able to mount object "
                ~sysPath);

        addMountedPath(MountedPath(mountPoint, precedence,
            currentHandler.mount(absPath), writable));
    }

    public void mount(MountPath mp, char[] sysPath, char[] mountPoint,
        bool writable, uint precedence = 0)
    {
        mount(mp, sysPath, VFSPath(mountPoint), writable, precedence);
    }

    ///Try mounting a file/folder and return if the mount succeeded
    public bool tryMount(MountPath mp, char[] path, VFSPath mountPoint,
        bool writable, uint precedence = 0)
    {
        try {
            mount(mp, path, mountPoint, writable, precedence);
            return true;
        } catch {
            return false;
        }
    }

    public bool tryMount(MountPath mp, char[] path, char[] mountPoint,
        bool writable, uint precedence = 0)
    {
        return tryMount(mp, path, VFSPath(mountPoint), writable, precedence);
    }

    ///Create a symbolic link from mountPoint to relPath
    ///relPath cannot be a parent directory of mountPoint
    ///Example:
    ///  link("/locale/de","/",false)
    ///Path is not checked for existance
    ///IMPORTANT: Be careful with setting writable = true,
    ///  as you may get errors or files created in wrong paths when
    ///  relPath is a subpath of mountPoint and any directory in-between is
    ///  writable
    public void link(VFSPath relPath, VFSPath mountPoint, bool writable,
        uint precedence = 0)
    {
        if (relPath.isChildOrEqual(mountPoint))
        {
            throw new FilesystemException("Can't link to a direct or indirect"
                " parent directory");
        }

        addMountedPath(MountedPath(mountPoint, precedence,
            new HandlerLink(this, relPath), writable));
    }

    public void link(char[] relPath, char[] mountPoint, bool writable,
        uint precedence = 0)
    {
        link(VFSPath(relPath), VFSPath(mountPoint), writable, precedence);
    }

    ///open a stream to a file in the VFS
    ///if you try to open an existing file (mode != FileMode.OutNew), all
    ///mounted paths are searched top-down (first mounted first) until a file
    ///has been found
    ///When creating a file, it will be created in the first matching path that
    ///is writable
    ///Params:
    ///  relFilename = path to the file, relative to VFS root
    ///  mode = how the file should be opened
    //need to make caller parameter public
    public Stream open(VFSPath filename, FileMode mode = FileMode.In,
        HandlerInstance caller = null)
    {
        version(FSDebug) log("Trying to open '%s'",filename);
        foreach (inout MountedPath p; mMountedPaths) {
            if (p.handler == caller)
                continue;
            if (p.matchesPath(filename) && p.matchesMode(mode)) {
                version(FSDebug) log("Found matching handler");
                VFSPath handlerPath = p.getHandlerPath(filename);
                if (p.handler.exists(handlerPath) || mode == FileMode.OutNew) {
                    //the file exists, or a new file should be created
                    return p.handler.open(handlerPath, mode);
                }
            }
        }
        throw new FilesystemException("File not found: " ~ filename.toString);
    }

    public Stream open(char[] filename, FileMode mode = FileMode.In)
    {
        return open(VFSPath(filename), mode, null);
    }

    ///List files (not directories) in directory relPath
    ///Works like std.file.listdir
    ///Will not error if the path is not found
    ///findDirs: also find directories (these have '/' at the end of filename!)
    ///Returns:
    /// false if listing was aborted, true otherwise
    public bool listdir(VFSPath relPath, char[] pattern, bool findDirs,
        bool delegate(char[] filename) callback)
    {
        return listdir(relPath, pattern, findDirs, callback, null);
    }

    public bool listdir(char[] relPath, char[] pattern, bool findDirs,
        bool delegate(char[] filename) callback)
    {
        return listdir(VFSPath(relPath), pattern, findDirs, callback);
    }

    protected bool listdir(VFSPath relPath, char[] pattern, bool findDirs,
        bool delegate(char[] filename) callback, HandlerInstance caller)
    {
        bool cont = true;
        foreach (inout MountedPath p; mMountedPaths) {
            if (p.handler == caller)
                continue;
            if (p.matchesPathForList(relPath)) {
                version(FSDebug) log("Found matching handler");
                VFSPath handlerPath = p.getHandlerPath(relPath);
                if (p.handler.pathExists(handlerPath)) {
                    //the path exists, list contents
                    cont = p.handler.listdir(handlerPath, pattern, findDirs,
                        callback);
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
    public bool exists(VFSPath filename) {
        return exists(filename, null);
    }

    public bool exists(char[] filename) {
        return exists(VFSPath(filename));
    }

    protected bool exists(VFSPath filename, HandlerInstance caller) {
        foreach (inout MountedPath p; mMountedPaths) {
            if (p.handler == caller)
                continue;
            if (p.matchesPath(filename)) {
                VFSPath handlerPath = p.getHandlerPath(filename);
                if (p.handler.exists(handlerPath)) {
                    //file found
                    return true;
                }
            }
        }
        return false;
    }


    ///Check if a directory exists in the VFS
    public bool pathExists(VFSPath relPath) {
        return pathExists(relPath, null);
    }

    public bool pathExists(char[] relPath) {
        return pathExists(VFSPath(relPath));
    }

    protected bool pathExists(VFSPath relPath, HandlerInstance caller) {
        foreach (inout MountedPath p; mMountedPaths) {
            if (p.handler == caller)
                continue;
            if (p.matchesPathForList(relPath)) {
                VFSPath handlerPath = p.getHandlerPath(relPath);
                if (p.handler.pathExists(handlerPath)) {
                    //path exists
                    return true;
                }
            }
        }
        return false;
    }

    public bool pathIsWritable(VFSPath relPath) {
        return pathIsWritable(relPath, null);
    }

    public bool pathIsWritable(char[] relPath) {
        return pathIsWritable(VFSPath(relPath));
    }

    protected bool pathIsWritable(VFSPath relPath, HandlerInstance caller) {
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

    ///get a unique (non-existing) filename in path with extension ext
    ///if the file already exists, either replace %s with or append 2,3 etc.
    char[] getUniqueFilename(char[] path, char[] nameTemplate, char[] ext,
        out int tries)
    {
        const cValidChars = "-+!.,;a-zA-Z0-9()[]";

        char[] fn = str.format(nameTemplate, "");
        char[] ret;
        int i = 2;
        //detect invalid characters in name by str.tr
        while (exists(ret = path
            ~ str.tr(fn, cValidChars, "_", "c") ~ ext))
        {
            fn = str.format(nameTemplate, i);
            i++;
        }
        tries = i-1;
        return ret;
    }

    package static void registerHandler(MountPointHandler h) {
        mHandlers ~= h;
    }
}
