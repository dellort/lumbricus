module framework.filesystem;

import str = stdx.string;
import stdx.stream;
import tango.util.PathUtil;
import tpath = tango.io.Path;
import tango.core.Exception : IOException;
import utils.misc;
import utils.log;
import utils.output;
import utils.path;

import tango.sys.Environment;
version(Windows) {
    //for My Documents folder
    import tango.sys.win32.SpecialPath;
}

FileSystem gFS;

private Log log;

//Uncomment this to see detailed filesystem log messages
//xxx: not needed anymore, logs are enabled or disabled by a runtime mechanism
//or so I thought
//version = FSDebug;

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
private abstract class MountPointHandler {
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
private abstract class HandlerInstance {
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
        version(FSDebug) log("New dir handler for '{}'",mDirPath);
    }

    bool isWritable() {
        return true;
    }

    bool exists(VFSPath handlerPath) {
        char[] p = handlerPath.makeAbsolute(mDirPath);
        version(FSDebug) log("Checking for existance: '{}'",p);
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
        version(FSDebug) log("Handler for '{}': Opening '{}'",mDirPath,
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
        version(FSDebug) log("New link: {}",relPath);
        mLinkedPath = relPath;
        mParent = parent;
    }

    bool isWritable() {
        version(FSDebug) log("Link: isWritable");
        return mParent.pathIsWritable(mLinkedPath, this);
    }

    bool exists(VFSPath handlerPath) {
        version(FSDebug) log("Link: exists({})",handlerPath);
        return mParent.exists(mLinkedPath.join(handlerPath), this);
    }

    bool pathExists(VFSPath handlerPath) {
        version(FSDebug) log("Link: pathexists({})",handlerPath);
        return mParent.pathExists(mLinkedPath.join(handlerPath), this);
    }

    Stream open(VFSPath handlerPath, FileMode mode) {
        version(FSDebug) log("Link: open({})",handlerPath);
        return mParent.open(mLinkedPath.join(handlerPath), mode, this);
    }

    bool listdir(VFSPath handlerPath, char[] pattern, bool findDirs,
        bool delegate(char[] filename) callback)
    {
        return mParent.listdir(mLinkedPath.join(handlerPath), pattern, findDirs,
            callback, this);
    }
}

typedef uint MountId;

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
            MountId mountId;

            public static MountedPath opCall(VFSPath mountPoint, uint precedence,
                HandlerInstance handler, bool writable)
            {
                MountedPath ret;
                //make sure mountPoint starts and ends with a '/'
                ret.mountPoint = mountPoint;
                ret.precedence = precedence;
                ret.handler = handler;
                ret.mWritable = writable;
                ret.mountId = mNextMountId++;
                return ret;
            }

            public bool isWritable() {
                return mWritable && handler.isWritable();
            }

            ///is relPath a subdirectory of mountPoint?
            ///compares case-sensitive
            public bool matchesPath(VFSPath other) {
                version(FSDebug) log("Checking for match: '{}' and '{}'",
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
        char[] mDataPath;
        MountedPath[] mMountedPaths;
        static MountId mNextMountId;

        static MountPointHandler[] mHandlers;
    }

    this(char[] arg0, char[] appId) {
        assert(!gFS, "FileSystem is singleton");
        gFS = this;
        log = registerLog("FS");
        mAppId = appId;
        initPaths(arg0);
    }

    ///Returns path to '.<appId>' in user's home directory
    ///Created if not existant
    ///Assuming mAppPath is already initalized
    protected char[] getUserPath() {
        char[] userPath;

        //set user directory from os home path
        char[] home = null;
        char[] os_appid = mAppId;
        version(Windows) {
            //windows: Docs & Settings\AppData\Lumbricus
            //home = Environment.get("APPDATA");
            //no, rather use My Documents\Lumbricus
            home = getSpecialPath(CSIDL_PERSONAL);
            //Uppercase (MS users like it that way)
            if (os_appid.length)
                os_appid = str.toupper(os_appid[0..1]) ~ os_appid[1..$];
        } else {
            //linux: ~/.lumbricus
            home = Environment.get("HOME");
            os_appid = "." ~ os_appid;
        }
        if (home != null)
            //append ".lumbricus"
            userPath = addTrailingPathDelimiter(home) ~ os_appid;
        else
            //failed to get env var? then use AppPath/.lumbricus instead
            userPath = mAppPath ~ os_appid;

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
        version(FSDebug) log("PUser = '{}'",mUserPath);

        //data path: prefix/share/appId
        mDataPath ~= mAppPath ~ "../share/" ~ mAppId ~ "/";
        version(FSDebug) log("PData = '{}'", mDataPath);
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
    public MountId mount(MountPath mp, char[] sysPath, VFSPath mountPoint,
        bool writable, uint precedence = 0)
    {
        //get absolute path to object, considering mp
        char[] absPath;
        switch (mp) {
            case MountPath.data:
                absPath = mDataPath ~ sysPath;
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

        auto mounted = MountedPath(mountPoint, precedence,
            currentHandler.mount(absPath), writable);
        addMountedPath(mounted);
        return mounted.mountId;
    }

    public MountId mount(MountPath mp, char[] sysPath, char[] mountPoint,
        bool writable, uint precedence = 0)
    {
        return mount(mp, sysPath, VFSPath(mountPoint), writable, precedence);
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

    ///Reset all mounts and links and start from scratch
    public void reset() {
        mMountedPaths = null;
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
    public MountId link(VFSPath relPath, VFSPath mountPoint, bool writable,
        uint precedence = 0)
    {
        if (relPath.isChildOrEqual(mountPoint))
        {
            throw new FilesystemException("Can't link to a direct or indirect"
                " parent directory");
        }

        auto mp = MountedPath(mountPoint, precedence,
            new HandlerLink(this, relPath), writable);
        addMountedPath(mp);
        return mp.mountId;
    }

    public MountId link(char[] relPath, char[] mountPoint, bool writable,
        uint precedence = 0)
    {
        return link(VFSPath(relPath), VFSPath(mountPoint), writable, precedence);
    }

    ///Try unmounting the specified id (result of mount() or link())
    ///Returns true if the id was found and unmounted (does not throw)
    public bool unmount(MountId mid) {
        foreach (int idx, ref mp; mMountedPaths) {
            if (mp.mountId == mid) {
                mMountedPaths = mMountedPaths[0..idx] ~ mMountedPaths[idx+1..$];
                return true;
            }
        }
        return false;
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
        version(FSDebug) log("Trying to open '{}'",filename);
        foreach (inout MountedPath p; mMountedPaths) {
            if (p.handler == caller)
                continue;
            if (p.matchesPath(filename) && p.matchesMode(mode)) {
                version(FSDebug) log("Found matching handler");
                VFSPath handlerPath = p.getHandlerPath(filename);
                if (p.handler.exists(handlerPath)
                    || (mode & FileMode.OutNew) == FileMode.OutNew) {
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
    ///if the file already exists, either replace {} with or append 2,3 etc.
    char[] getUniqueFilename(char[] path, char[] nameTemplate, char[] ext,
        out int tries)
    {
        const cValidChars = "-+!.,;a-zA-Z0-9()[]";

        //changed in r657: always append a number to filename (I hope it's ok)

        int i = 0;
        char[] fn, ret;
        do {
            i++;
            fn = myformat(nameTemplate, i);
        } while (exists(ret = path //detect invalid characters in name by str.tr
            ~ str.tr(fn, cValidChars, "_", "c") ~ ext))
        tries = i-1;
        return ret;
    }

    package static void registerHandler(MountPointHandler h) {
        mHandlers ~= h;
    }
}
