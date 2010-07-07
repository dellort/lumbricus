module framework.filesystem;

import str = utils.string;
import utils.stream;
import tpath = tango.io.Path;
import tango.core.Exception : IOException;
import tango.text.Regex;  //for filename cleanup
import utils.misc;
import utils.log;
import utils.path;
import utils.archive;

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

class FilesystemException : CustomException {
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

    abstract Stream open(VFSPath handlerPath, File.Style mode);

    ///list the files (no dirs) in the path handlerPath (relative to handler
    ///object)
    ///listing should be non-recursive, and return files without path
    ///you can assume that pathExists has been called before
    ///if findDir is true, also find directories
    ///if callback returns false, you should abort and return false too
    abstract bool listdir(VFSPath handlerPath, char[] pattern, bool findDir,
        bool delegate(char[] filename) callback);

    abstract void close();
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
        FileSystem.registerHandler(new typeof(this)());
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
        log("New dir handler for '{}'",mDirPath);
    }

    bool isWritable() {
        return true;
    }

    bool exists(VFSPath handlerPath) {
        char[] p = handlerPath.makeAbsolute(mDirPath);
        log("Checking for existance: '{}'",p);
        return tpath.exists(p) && !tpath.isFolder(p);
    }

    bool pathExists(VFSPath handlerPath) {
        char[] p = handlerPath.makeAbsolute(mDirPath);
        return tpath.exists(p) && tpath.isFolder(p);
    }

    private void createPath(VFSPath handlerPath) {
        if (!pathExists(handlerPath)) {
            if (handlerPath.isEmpty())
                throw new CustomException("createPath error: handler"
                    ~ " path does not exist");
            //recursively create parent dir
            createPath(handlerPath.parent);
            //create last path
            tpath.createFolder(handlerPath.makeAbsolute(mDirPath));
        }
    }

    Stream open(VFSPath handlerPath, File.Style mode) {
        log("Handler for '{}': Opening '{}'",mDirPath, handlerPath);
        if (mode.open != File.Open.Exists) {
            //make sure path exists
            createPath(handlerPath.parent);
        }
        return new ConduitStream(castStrict!(Conduit)(
            new File(handlerPath.makeAbsolute(mDirPath), mode)));
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
                if (tpath.patternMatch(fn, pattern)) {
                    if (!callback(fn))
                        return false;
                }
            }
        }

        return true;
    }

    void close() {
        mDirPath = null;
    }
}

//--------------------------------------------------------------------
//  Code for ZIP support, using tango Vfs functions, follows
//  Side-note: 5 Tango tickets were created while writing this code

import tango.io.vfs.ZipFolder : ZipFolder;

//hack for tango 0.99.9 <-> svn trunk change
import tango.core.Version;
static if (Tango.Major == 0 && Tango.Minor == 999) {
    import tango.io.compress.ZlibStream : ZlibInput;
} else {
    import tango.io.stream.Zlib : ZlibInput;
}

import tango.io.vfs.model.Vfs : VfsFolder;
import ic = tango.io.model.IConduit;

///Specific MountPointHandler for mounting ZIP archives
private class MountPointHandlerZip : MountPointHandler {
    bool canHandle(char[] absPath) {
        //exisiting files, name ending with ".zip"
        return tpath.exists(absPath) && !tpath.isFolder(absPath)
            && absPath.length > 4 && str.tolower(absPath[$-4..$]) == ".zip";
    }

    HandlerInstance mount(char[] absPath) {
        assert(canHandle(absPath));
        return new HandlerTangoVfs(new ZipFolder(absPath, true));
    }

    static this() {
        FileSystem.registerHandler(new typeof(this)());
    }
}

//wrapper from tango Vfs to our filesystem
//currently, only supports reading because of ZipFolder limitations (i.e. bugs),
//  and Stream interface issues (see hack above)
private class HandlerTangoVfs : HandlerInstance {
    private {
        VfsFolder mVfsFolder;

        //the purpose of this is to correct the wrong (too small) size
        //reported by tango.io.compress.ZlibStream.ZlibInput (tango bug)
        //see http://dsource.org/projects/tango/ticket/1673
        class SizeFixStream : ConduitStream {
            private ulong mForcedSize;

            this(Conduit c, ulong forcedSize) {
                super(c);
                //this class only fixes a tango bug, for slicing you have
                //  to use SliceStream
                assert(forcedSize >= super.size());
                mForcedSize = forcedSize;
            }

            this(ic.InputStream i, ulong forcedSize) {
                super(i);
                assert(forcedSize >= super.size());
                mForcedSize = forcedSize;
            }

            override ulong size() {
                return mForcedSize;
            }
        }
    }

    this(VfsFolder fld) {
        assert(!!fld);
        mVfsFolder = fld;
    }

    bool isWritable() {
        return mVfsFolder.writable();
    }

    bool exists(VFSPath handlerPath) {
        //seems ZipFolder can't handle that case (assertion ZipFolder, 1370)
        //so we check every path level recursively
        if (!pathExists(handlerPath.parent))
            return false;
        return mVfsFolder.file(handlerPath.get(false)).exists;
    }

    bool pathExists(VFSPath handlerPath) {
        //assertion failed ZipFolder, 705
        if (handlerPath.isEmpty)
            return true;
        //assertion failed ZipFolder, 1370
        if (!pathExists(handlerPath.parent))
            return false;
        return mVfsFolder.folder(handlerPath.get(false)).exists;
    }

    Stream open(VFSPath handlerPath, File.Style mode) {
        //only input
        assert(mode.access == File.Access.Read);
        auto vfile = mVfsFolder.file(handlerPath.get(false));
        //wrap the tango stream
        if (cast(ZlibInput)vfile.input) {
            //see SizeFixStream comment for explanation
            return new SizeFixStream(vfile.input, vfile.size);
        } else {
            return new ConduitStream(vfile.input);
        }
    }

    bool listdir(VFSPath handlerPath, char[] pattern, bool findDir,
        bool delegate(char[] filename) callback)
    {
        //xxx I don't know how many useless classes this function creates...
        auto fld = mVfsFolder;
        if (!handlerPath.isEmpty)
            fld = mVfsFolder.folder(handlerPath.get(false)).open;
        if (findDir) {
            //direct subfolders
            foreach (subf; fld) {
                if (tpath.patternMatch(subf.name, pattern)) {
                    if (!callback(subf.name ~ "/"))
                        return false;
                }
            }
        }
        //matching files
        foreach (fn; fld.self.catalog(pattern)) {
            if (!callback(fn.name))
                return false;
        }
        return true;
    }

    void close() {
        mVfsFolder.close();
        mVfsFolder = null;
    }
}

//  ZIP support end
//----------------------------------------------------------------

///Specific MountPointHandler for mounting ZIP archives
private class MountPointHandlerTar : MountPointHandler {
    bool canHandle(char[] absPath) {
        //exisiting files, name ending with ".tar"
        return tpath.exists(absPath) && !tpath.isFolder(absPath)
            && absPath.length > 4 && str.tolower(absPath[$-4..$]) == ".tar";
    }

    HandlerInstance mount(char[] absPath) {
        assert(canHandle(absPath));
        return new HandlerTar(absPath);
    }

    static this() {
        FileSystem.registerHandler(new typeof(this)());
    }
}

private class HandlerTar : HandlerInstance {
    private {
        TarArchive mTarFile;
    }

    this(char[] archivePath) {
        auto archFile = new ConduitStream(castStrict!(Conduit)(
            new File(archivePath, File.ReadShared)));
        mTarFile = new TarArchive(archFile, true);
    }

    this(Stream archiveStream) {
        mTarFile = new TarArchive(archiveStream, true);
    }

    bool isWritable() {
        return false;
    }

    bool exists(VFSPath handlerPath) {
        return mTarFile.fileExists(handlerPath.get(false));
    }

    bool pathExists(VFSPath handlerPath) {
        return mTarFile.pathExists(handlerPath.get(false));
    }

    Stream open(VFSPath handlerPath, File.Style mode) {
        return mTarFile.openReadStreamUncompressed(handlerPath.get(false));
    }

    bool listdir(VFSPath handlerPath, char[] pattern, bool findDir,
        bool delegate(char[] filename) callback)
    {
        bool[char[]] dirCache;
        foreach (char[] fn; mTarFile) {
            auto cur = VFSPath(fn);
            if (handlerPath.isChild(cur)) {
                auto rel = cur.relativePath(handlerPath);
                if (rel.parent.isEmpty) {
                    //entry is a file in the directory
                    char[] filen = rel.get(false);
                    if (!tpath.patternMatch(filen, pattern))
                        continue;
                    if (!callback(filen))
                        return false;
                } else if (rel.parent.parent.isEmpty) {
                    //entry is a file in a direct subdirectory
                    if (findDir) {
                        char[] dirn = rel.parent.get(false);
                        if (!tpath.patternMatch(dirn, pattern))
                            continue;
                        if (!(dirn in dirCache)) {
                            dirCache[dirn] = true;
                            if (!callback(dirn ~ '/'))
                                return false;
                        }
                    }
                }
            }
        }
        return true;
    }

    void close() {
        mTarFile.close();
        mTarFile = null;
    }
}


private class HandlerLink : HandlerInstance {
    private VFSPath mLinkedPath;
    private FileSystem mParent;

    this(FileSystem parent, VFSPath relPath) {
        log("New link: {}",relPath);
        mLinkedPath = relPath;
        mParent = parent;
    }

    bool isWritable() {
        log("Link: isWritable");
        return mParent.pathIsWritable(mLinkedPath, this);
    }

    bool exists(VFSPath handlerPath) {
        log("Link: exists({})",handlerPath);
        return mParent.exists(mLinkedPath.join(handlerPath), this);
    }

    bool pathExists(VFSPath handlerPath) {
        log("Link: pathexists({})",handlerPath);
        return mParent.pathExists(mLinkedPath.join(handlerPath), this);
    }

    Stream open(VFSPath handlerPath, File.Style mode) {
        log("Link: open({})",handlerPath);
        return mParent.open(mLinkedPath.join(handlerPath), mode, this);
    }

    bool listdir(VFSPath handlerPath, char[] pattern, bool findDirs,
        bool delegate(char[] filename) callback)
    {
        return mParent.listdir(mLinkedPath.join(handlerPath), pattern, findDirs,
            callback, this);
    }

    void close() {
        mLinkedPath.set("");
        mParent = null;
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
                log("Checking for match: '{}' and '{}'",other,mountPoint);
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
            public bool matchesMode(File.Style mode) {
                return (mode.access == File.Access.Read || isWritable);
            }
        }

        char[] mUserPath;
        char[] mDataPath;
        MountedPath[] mMountedPaths;
        static MountId mNextMountId;

        static MountPointHandler[] mHandlers;
        Regex mRegFilename;
    }

    this(char[] appId) {
        assert(!gFS, "FileSystem is singleton");
        gFS = this;
        log = registerLog("fs");
        mRegFilename = new Regex(`[^-+!.,;a-zA-Z0-9()\[\]]`);
        initPaths(appId);
    }

    //standalone, non-singleton instance of a FileSystem
    this() {
        log = registerLog("fs2");
        mRegFilename = new Regex(`[^-+!.,;a-zA-Z0-9()\[\]]`);
        mUserPath = "";
        mDataPath = "";
    }

    ///Returns path to '.<appId>' in user's home directory
    ///Created if not existant
    ///appPath = directory where exe is located
    protected char[] getUserPath(char[] appPath, char[] appId) {
        char[] userPath;

        //set user directory from os home path
        char[] home = null;
        char[] os_appid = appId;
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
            userPath = appPath ~ os_appid;

        //try to create user directory
        try {
            tpath.createFolder(userPath);
        } catch (IOException e) {
            //directory already exists, do nothing
        }
        return userPath;
    }

    ///initialize paths where files/folders to mount will be searched
    protected void initPaths(char[] appId) {
        auto appPath = getAppPath();

        //user path: home directory + .appId
        mUserPath = getUserPath(appPath, appId);
        log("PUser = '{}'",mUserPath);

        //data path: prefix/share/appId
        mDataPath ~= appPath ~ "../share/" ~ appId ~ "/";
        log("PData = '{}'", mDataPath);
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
                if (!mDataPath.length)
                    throw new FilesystemException("no app filesystem");
                absPath = mDataPath ~ sysPath;
                break;
            case MountPath.user:
                if (!mUserPath.length)
                    throw new FilesystemException("no app filesystem");
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

    ///Mount a stream as archive on this mount point.
    ///Read-only access is implied.
    ///Params:
    ///  mp = see mount()
    ///  archive = stream of the archive contents
    ///  fmt = type of the archive, usually the file extension (e.g. "tar")
    ///  mountPoint = see mount()
    ///  precedence = see mount()
    MountId mountArchive(MountPath mp, Stream archive, char[] fmt,
        VFSPath mountPoint, uint precedence = 0)
    {
        //hardcoded to tar because it's the only one that works
        //zip with ZipFolder doesn't because ZipFolder expects a real filesystem
        //  path for the zip, and apparently can't use a tango stream instead
        if (fmt != "tar")
            throw new FilesystemException("unsupported archive format");
        auto handler = new HandlerTar(archive);
        auto mounted = MountedPath(mountPoint, precedence, handler, false);
        addMountedPath(mounted);
        return mounted.mountId;
    }

    MountId mountArchive(MountPath mp, Stream archive, char[] fmt,
        char[] mountPoint, uint precedence = 0)
    {
        return mountArchive(mp, archive, fmt, VFSPath(mountPoint), precedence);
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
        } catch(FilesystemException e) {
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

    ///Mount fsPath from fs on mountPoint()
    ///also see link()
    ///xxx: not bothering with a VFSPath version
    public MountId linkExternal(FileSystem fs, char[] fsPath, char[] mountPoint,
        bool writable, uint precedence = 0)
    {
        auto fsPath_ = VFSPath(fsPath);
        auto mountPoint_ = VFSPath(mountPoint);

        auto mp = MountedPath(mountPoint_, precedence,
            new HandlerLink(fs, fsPath_), writable);
        addMountedPath(mp);
        return mp.mountId;
    }

    ///Try unmounting the specified id (result of mount() or link())
    ///Returns true if the id was found and unmounted (does not throw)
    public bool unmount(MountId mid) {
        foreach (int idx, ref mp; mMountedPaths) {
            if (mp.mountId == mid) {
                mp.handler.close();
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
    public Stream open(VFSPath filename, File.Style mode = File.ReadShared,
        HandlerInstance caller = null)
    {
        log("Trying to open '{}'",filename);
        //always shared reading
        if (mode.share == File.Share.None)
            mode.share = File.Share.Read;
        foreach (inout MountedPath p; mMountedPaths) {
            if (p.handler == caller)
                continue;
            if (p.matchesPath(filename) && p.matchesMode(mode)) {
                log("Found matching handler");
                VFSPath handlerPath = p.getHandlerPath(filename);
                if (p.handler.exists(handlerPath)
                    || (mode.open != File.Open.Exists)) {
                    //the file exists, or a new file should be created
                    return p.handler.open(handlerPath, mode);
                }
            }
        }
        throw new FilesystemException("File not found: " ~ filename.toString);
    }

    public Stream open(char[] filename, File.Style mode = File.ReadShared)
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
                log("Found matching handler");
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

    //throw exception if file is not existent and not readable
    //(doesn't check if it's readable yet)
    void mustExist(char[] filename) {
        auto fn = VFSPath(filename);
        if (!exists(fn))
            throw new FilesystemException("File not found: " ~ fn.toString);
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
        //changed in r657: always append a number to filename (I hope it's ok)

        int i = 0;
        char[] fn, ret;
        do {
            i++;
            fn = myformat(nameTemplate, i);
        } while (exists(ret = path //detect invalid characters in name
            ~ mRegFilename.replaceAll(fn, "_") ~ ext))
        tries = i-1;
        return ret;
    }

    package static void registerHandler(MountPointHandler h) {
        mHandlers ~= h;
    }
}
