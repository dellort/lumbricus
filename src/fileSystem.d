module fileSystem;

import derelict.physfs.physfs;
import path = std.path;
import stdf = std.file;
import cstdlib = std.c.stdlib;
import str = std.string;
import std.stream;

private static FileSystem gFileSystem;

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

class FileSystemException : Exception {
    this(char[] msg) {
        super(msg);
    }
}

public class FileSystem {
    char[] mAppPath;
    char[] mUserPath;
    char[] mDataPath;

    private const char[] USERPATH = ".lumbricus";
    private const char[] DATAPATH = "data";

    ///needs args[0] for initialization
    this(char[] arg0) {
        if (gFileSystem !is null) {
            throw new Exception("FileSystem is a singleton, sorry.");
        }

        gFileSystem = this;

        //setup necessary paths
        initPaths(arg0);

        //initialize PhysFs
        DerelictPhysFs.load();
        PHYSFS_init(arg0);

        //mount paths for PhysFs
        //NO trailing /
        PHYSFS_setWriteDir(str.toStringz(mUserPath));
        mount(mDataPath,"data",1);
        mount(mUserPath,"user",1);
    }

    ~this() {
        PHYSFS_deinit();
    }

    ///Fill mAppPath, mUserPath and mDataPath with OS-dependant values
    private void initPaths(char[] arg0) {
        version(Windows) {
            //win: args[0] contains full path to executable
            mAppPath = path.getDirName(arg0);
        } else {
            //lin: args[0] is relative to current directory
            char[] curDir = addTrailingPathDelimiter(stdf.getcwd());
            char[] dirname = path.getDirName(arg0);
            if (dirname.length > 0 && dirname[0] == path.sep[0]) {
                //sometimes, the path is absolute
                mAppPath = dirname;
            } else if (dirname != ".") {
                mAppPath = curDir ~ dirname;
            } else {
                mAppPath = curDir;
            }
        }
        
        mAppPath = addTrailingPathDelimiter(mAppPath);

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
            mUserPath = addTrailingPathDelimiter(str.toString(home)) ~ USERPATH;
        else
            //failed to get env var? then use AppPath/.lumbricus instead
            mUserPath = mAppPath ~ USERPATH;

        //try to create user directory
        try {
            stdf.mkdir(mUserPath);
        } catch (stdf.FileException e) {
            //directory already exists, do nothing
        }

        //search data path
        //try 1: AppPath/../data if run from svn
        mDataPath = mAppPath ~ ".." ~ path.sep ~ DATAPATH;
        if (!dirExists(mDataPath)) {
            //try 2: /usr/share/data for linux
            mDataPath = mAppPath ~ ".." ~ path.sep ~ "share" ~ path.sep ~
                DATAPATH;
            if (!dirExists(mDataPath)) {
                //try 3: AppPath/data for windows
                mDataPath = mAppPath ~ DATAPATH;
                if (!dirExists(mDataPath)) {
                    //out of options...
                    throw new FileSystemException(
                        "Data path could not be determined");
                }
            }
        }
    }

    /** Wrapper for PHYSFS_mount that converts char[] to char*
     * and throws helpful exceptions on failure
     */
    private void mount(char[] pathStr, char[] mountPoint, bool append) {
        int iappend = append?1:0;
        if (PHYSFS_mount(str.toStringz(pathStr),str.toStringz(mountPoint),
            append) == 0)
        {
            throw new FileSystemException(str.format(
                "Could not mount \"%s\" to \"%s\": %s",pathStr,mountPoint,
                str.toString(PHYSFS_getLastError())));
        }
    }

    /** Open a file from data directory/archives for reading
     * throws FileSystemException if file could not be opened
     * Stream must be closed manually
     */
    public Stream openData(char[] filename) {
        try {
            return new PhysFsStream("data/"~filename,FileMode.In);
        } catch (StreamException e) {
            throw new FileSystemException("Could not open file \""~
                filename~"\": "~e.toString());
        }
    }

    /** Open a file from user directory
     * throws FileSystemException if file could not be opened
     * Stream must be closed manually
     */
    public Stream openUser(char[] filename, FileMode mode) {
        try {
            if ((mode & FileMode.Out) || (mode & FileMode.Append)) {
                return new PhysFsStream(filename,mode);
            } else {
                return new PhysFsStream("user/"~filename,mode);
            }
        } catch (StreamException e) {
            throw new FileSystemException("Could not open file \""~
                filename~"\" for writing: "~e.toString());
        }
    }

    ///return path to executable with trailing /
    public char[] appPath() {
        return mAppPath;
    }
}
