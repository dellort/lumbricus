module utils.path;

import str = stdx.string;
import tango.io.model.IFile : FileConst;

char[] getFilePath(char[] fullname)
    out (result)
    {
        assert(result.length <= fullname.length);
    }
    body
    {
        uint i;

        for (i = fullname.length; i > 0; i--)
        {
            if (fullname[i - 1] == '\\')
                break;
            if (fullname[i - 1] == '/')
                break;
        }
        return fullname[0 .. i];
    }

///encapsulates a platform-independant VFS path
///inspired by tango.io.FilePath, but will remove all platform-dependency
///instead of preserving it and contains no file manipulation functions
struct VFSPath {
    const cPathSep = '/';

    private {
        char[] mPath;
        int mNameIdx, mExtIdx;
    }

    ///create VFSPath struct and set path (see set())
    static VFSPath opCall(char[] p, bool fixIllegal) {
        VFSPath ret;
        ret.set(p, fixIllegal);
        return ret;
    }

    ///create VFSPath struct and set path (see set())
    static VFSPath opCall(char[] p) {
        return opCall(p, false);
    }

    ///encapsulate a path into a VFSPath struct
    ///any platform-dependency will be killed, . and .. will be resolved
    ///Params:
    ///  fixIllegal = if true, illegal characters will be replaced with _
    ///               if false, illegal chars will throw an exception
    void set(char[] p, bool fixIllegal = false) {
        mPath = p;
        parse(fixIllegal);
    }

    ///retrieve current path, in platform-independent notation (/ separated)
    ///return value will have a leading /
    ///Params:
    ///  trailingSep = true to append a '/'
    char[] get(bool leadingSep = true, bool trailingSep = false) {
        char[] ret = mPath;
        if (trailingSep)
            ret ~= cPathSep;
        if (!leadingSep && ret.length > 0 && ret[0] == cPathSep)
            ret = ret[1..$];
        return ret;
    }

    ///join this path with an absolute path and get an os-dependant absolute
    ///path
    char[] makeAbsolute(char[] absParent) {
        //cut off all trailing separators
        while (absParent[$-1] == '/' || absParent[$-1] == '\\')
            absParent = absParent[0..$-1];
        char[] p = str.replace(mPath,"/",FileConst.PathSeparatorString);
        return absParent ~ p;
    }

    ///get the parent directory of the current path
    ///ex: /foo/bar -> /foo
    ///ex: /foo -> (empty)
    ///empty dir (i.e. root) will return itself
    VFSPath parent() {
        int i = str.rfind(mPath, '/');
        if (i >= 0)
            return VFSPath(mPath[0..i]);
        else
            return *this;
    }

    ///is the path empty (i.e. the root)
    bool isEmpty() {
        return mPath.length == 0;
    }

    ///return file extension (with .) of the last path component
    ///returns an empty string for files without extension
    char[] extension() {
        if (mExtIdx >= 0)
            return mPath[mExtIdx..$];
        return "";
    }

    ///return filename with extension of the last path component
    char[] filename() {
        if (mNameIdx >= 0)
            return mPath[mNameIdx..$];
        return "";
    }

    ///return base name (without extension) of the last path component
    char[] filebase() {
        int ext = mExtIdx;
        if (ext < 0)
            ext = mPath.length;

        if (mNameIdx >= 0)
            return mPath[mNameIdx..ext];
        return "";
    }

    ///check if other is a real child of this path, i.e. it is in the current
    ///path or in a subdirectory
    bool isChild(VFSPath other) {
        return other.mPath.length > mPath.length+1
            && str.cmp(other.mPath[0..mPath.length], mPath) == 0
            && other.mPath[mPath.length] == cPathSep;
    }

    ///like isChild, but will return true even if the paths are the same
    bool isChildOrEqual(VFSPath other) {
        return isChild(other) || str.cmp(other.mPath, mPath) == 0;
    }


    VFSPath relativePath(VFSPath parent) {
        if (parent.isChildOrEqual(*this))
            return VFSPath(mPath[parent.mPath.length..$]);
        else
            error("relativePath: not a subpath of parent");
    }

    VFSPath join(VFSPath other) {
        return VFSPath(mPath ~ other.mPath);
    }

    char[] toString() {
        return mPath;
    }

    //parses/fixes the path in mPath:
    // - removes platform-dependency
    // - resolves . and ..
    // - handles illegal characters
    // - sets name and extension split points
    private void parse(bool fixIllegal = false) {
        mNameIdx = mExtIdx = -1;
        char[] curpart;
        char[][] parts;

        int discard = 0;
        //add a filename part (everything between / ) to the final part list
        //takes care of . and ..
        void addPart() {
            if (curpart.length == 0)
                return;

            switch (curpart) {
                case "..":
                    discard++;
                    break;
                case ".":
                    //nop
                    break;
                default:
                    if (discard > 0)
                        discard--;
                    else
                        parts = curpart ~ parts;
                    break;
            }
            curpart = null;
        }

        //first pass: go through the path in reverse, check illegal chars and
        //split into parts
        foreach_reverse (int i, inout char c; mPath) {
            switch (c) {
                case ':','*','?','"','<','>','|':
                    //illegal character detected
                    if (fixIllegal)
                        curpart = '_' ~ curpart;
                    else
                        error("The following characters are invalid in a path: "
                            ~ ":*?\"<>|");
                    break;
                case '\\','/':
                    //path separator (windows/linux)
                    addPart();
                    break;
                default:
                    curpart = c ~ curpart;
                    break;
            }
        }
        //add the remaining part (if the path does not start with a / )
        addPart();

        //now join everything back together
        mPath = null;
        foreach (inout char[] p; parts) {
            mPath ~= cPathSep ~ p;
        }

        //second pass: scan for filename and extension index
        foreach_reverse (int i, inout char c; mPath) {
            switch (c) {
                case '.':
                    //filename/extension separator
                    if (mNameIdx < 0) {
                        if (mExtIdx < 0 && i && mPath[i-1] != '.')
                            mExtIdx = i;
                    }
                    break;
                case cPathSep:
                    //path separator
                    if (mNameIdx < 0)
                        mNameIdx = i + 1;
                    break;
                default:
                    break;
            }
        }
    }

    private void error(char[] msg) {
        throw new Exception("VFSPath: "~msg);
    }
}

debug import tango.io.Stdout;

unittest {
    VFSPath v, v2;

    //******************** Parser tests ***************************

    v.set("/foo/bar");              assert(v.mPath == "/foo/bar");
    v.set("foo/bar");               assert(v.mPath == "/foo/bar");
    v.set("/foo/bar/");             assert(v.mPath == "/foo/bar");
    v.set("foo/bar/");              assert(v.mPath == "/foo/bar");
    v.set(r"/\\//\foo//\//bar//");  assert(v.mPath == "/foo/bar");
    v.set("/foo/bar/../bar");       assert(v.mPath == "/foo/bar");
    v.set("/f:o/bar",true);         assert(v.mPath == "/f_o/bar");
    try {
        v.set(r"C:\Windows\System32");
        assert(false);
    } catch {};
    v.set("/foo/../..");            assert(v.mPath == ""); assert(v.isEmpty);
    v.set("/foo/././../bar");       assert(v.mPath == "/bar");

    v.set("/foo/bar.txt");
    assert(v.filename == "bar.txt");
    assert(v.filebase == "bar");
    assert(v.extension == ".txt");

    v.set("/foo/bar");
    assert(v.filename == "bar");
    assert(v.filebase == "bar");
    assert(v.extension == "");

    v.set("/foo/.bar");
    assert(v.filename == ".bar");
    assert(v.filebase == "");
    assert(v.extension == ".bar");

    v.set("bar.txt");
    assert(v.filename == "bar.txt");
    assert(v.filebase == "bar");
    assert(v.extension == ".txt");

    //****************** get/makeAbsolute ******************************

    v.set("/foo/bar");
    assert(v.get(true, false) == "/foo/bar");
    assert(v.get(true, true) == "/foo/bar/");
    assert(v.get(false, false) == "foo/bar");
    assert(v.get(false, true) == "foo/bar/");

    v.set("/foo/bar");
    version(Windows) {
        assert(v.makeAbsolute(r"C:\Test\") == r"C:\Test/foo/bar");
        assert(v.makeAbsolute(r"C:\Test") == r"C:\Test/foo/bar");
        v.set("");
        assert(v.makeAbsolute(r"C:\Test") == r"C:\Test");
    }
    version(Linux) {
        assert(v.makeAbsolute("/usr/share/") == "/usr/share/foo/bar");
        assert(v.makeAbsolute("/usr/share") == "/usr/share/foo/bar");
        v.set("");
        assert(v.makeAbsolute("/usr/share") == "/usr/share");
    }

    //*************** isChild/relativePath/join/parent *******************

    v.set("/foo/bar");  v2.set("/foo");
    assert(v2.isChild(v));
    assert(!v.isChild(v2));
    v2.set("/foo/bar");
    assert(!v2.isChild(v));
    assert(v2.isChildOrEqual(v));
    v2.set("/foobar");
    assert(!v2.isChild(v));
    assert(!v.isChild(v2));

    v.set("/foo/bar"); v2.set("/foo");
    assert(v.relativePath(v2).mPath == "/bar");
    v2.set("/foo/bar");
    assert(v.relativePath(v2).mPath == "");
    v2.set("/foobar");
    try {
        auto tmp = v.relativePath(v2);
        assert(false);
    } catch {};

    v.set("/foo/bar"); v2.set("ar/gl");
    assert(v.join(v2).mPath == "/foo/bar/ar/gl");
    assert(v2.join(v).mPath == "/ar/gl/foo/bar");
    v2.set("");
    assert(v.join(v2).mPath == "/foo/bar");
    assert(v2.join(v).mPath == "/foo/bar");

    v.set("/foo/bar/bla");
    assert(v.parent.mPath == "/foo/bar");
    assert(v.parent.parent.mPath == "/foo");
    assert(v.parent.parent.parent.mPath == "");
    assert(v.parent.parent.parent.parent.mPath == "");

    debug Stdout.formatln("path.d unittest: passed");
}
