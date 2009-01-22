// Written in the D programming language.

/**
 * Macros:
 *	WIKI = Phobos/StdFile
 */

/*
 *  Copyright (C) 2001-2004 by Digital Mars, www.digitalmars.com
 * Written by Walter Bright, Christopher E. Miller, Andre Fornacon
 *
 *  This software is provided 'as-is', without any express or implied
 *  warranty. In no event will the authors be held liable for any damages
 *  arising from the use of this software.
 *
 *  Permission is granted to anyone to use this software for any purpose,
 *  including commercial applications, and to alter it and redistribute it
 *  freely, subject to the following restrictions:
 *
 *  o  The origin of this software must not be misrepresented; you must not
 *     claim that you wrote the original software. If you use this software
 *     in a product, an acknowledgment in the product documentation would be
 *     appreciated but is not required.
 *  o  Altered source versions must be plainly marked as such, and must not
 *     be misrepresented as being the original software.
 *  o  This notice may not be removed or altered from any source
 *     distribution.
 */

module stdx.file;

version (Tango) {
    import tango.io.device.File;
    import tango.io.FilePath;
    import tango.io.FileSystem;
    import tango.io.Path;
    import tango.core.Exception;
} else {
    import file = std.file;
}

private import stdx.path;
//private import std.string;
//private import std.regexp;

/***********************************
 * Exception thrown for file I/O errors.
 */

version (Tango) {
    class FileException : Exception
    {

        this(char[] name)
        {
            this(name, "file I/O");
        }

        this(char[] name, char[] message)
        {
            super(name ~ ": " ~ message);
        }
    }
} else {
    public import std.file : FileException;
}

/* **********************************
 * Basic File operations.
 */

/********************************************
 * Read file name[], return array of bytes read.
 * Throws:
 *	FileException on error.
 */

//in Tango case: turn IOException into FileException hurrrrr
T converror(T)(char[] name, T delegate() d) {
    version (Tango) {
        try {
            return d();
        } catch (IOException e) {
            throw new FileException(name, e.toString());
        }
    } else {
        return d();
    }
}

void[] read(char[] name)
{
    version (Tango) {
        return converror(name, { return File.get(name); });
    } else {
        return file.read(name);
    }
}

void write(char[] name, void[] buffer)
{
    version (Tango) {
        converror(name, { File.set(name, buffer); });
    } else {
        return file.write(name, buffer);
    }
}

void append(char[] name, void[] buffer)
{
    version (Tango) {
        converror(name, { File.append(name, buffer); });
    } else {
        return file.append(name, buffer);
    }
}

/***************************************************
 * Rename file from[] to to[].
 * Throws: FileException on error.
 */

void rename(char[] from, char[] to)
{
    version (Tango) {
        converror(to, { FilePath(from).rename(FilePath(to)); });
    } else {
        return file.rename(from, to);
    }
}


void remove(char[] name)
{
    version (Tango) {
        converror(name, { FilePath(name).remove(); });
    } else {
        file.remove(name);
    }
}

//yyy removed ulong getSize(char[] name)

//yyy removed void getTimes(char[] name, out d_time ftc, out d_time fta, out d_time ftm)

/***************************************************
 * Does file name[] (or directory) exist?
 * Return 1 if it does, 0 if not.
 */

int exists(char[] name)
{
    version (Tango) {
        return converror(name, { return FilePath(name).exists() ? 1 : 0; });
    } else {
        return file.exists(name);
    }
}

//yyy removed uint getAttributes(char[] name)

int isfile(char[] name)
{
    version (Tango) {
        return converror(name, { return FilePath(name).isFolder() ? 0 : 1; });
    } else {
        return file.isfile(name);
    }
}

int isdir(char[] name)
{
    version (Tango) {
        return converror(name, { return FilePath(name).isFolder() ? 1 : 0; });
    } else {
        return file.isdir(name);
    }
}

//yyy removed void chdir(char[] pathname)

void mkdir(char[] pathname)
{
    version (Tango) {
        converror(pathname, { FilePath(pathname).createFolder();} );
    } else {
        file.mkdir(pathname);
    }
}

//yyy removed void rmdir(char[] pathname)

char[] getcwd() {
    version (Tango) {
        return converror(".", { return FileSystem.getDirectory(); } );
    } else {
        return file.getcwd();
    }
}

/***************************************************
 * Directory Entry
 */

struct DirEntry
{
    char[] name;			/// file or directory name
    ulong size = ~0UL;			/// size of file in bytes
    //yyy removed
    //d_time creationTime = d_time_nan;	/// time of file creation
    //d_time lastAccessTime = d_time_nan;	/// time file was last accessed
    //d_time lastWriteTime = d_time_nan;	/// time file was last written to

    bool m_isdir;

    /****
     * Return !=0 if DirEntry is a directory.
     */
    uint isdir()
    {
	return m_isdir ? 1 : 0;
    }

    /****
     * Return !=0 if DirEntry is a file.
     */
    uint isfile()
    {
	return m_isdir ? 0 : 1;
    }
}


/***************************************************
 * Return contents of directory pathname[].
 * The names in the contents do not include the pathname.
 * Throws: FileException on error
 * Example:
 *	This program lists all the files and subdirectories in its
 *	path argument.
 * ----
 * import std.stdio;
 * import std.file;
 *
 * void main(char[][] args)
 * {
 *    auto dirs = std.file.listdir(args[1]);
 *
 *    foreach (d; dirs)
 *	writefln(d);
 * }
 * ----
 */

char[][] listdir(char[] pathname)
{
    char[][] result;

    bool listing(char[] filename)
    {
	result ~= filename;
	return true; // continue
    }

    listdir(pathname, &listing);
    return result;
}


/*****************************************************
 * Return all the files in the directory and its subdirectories
 * that match pattern or regular expression r.
 * Params:
 *	pathname = Directory name
 *	pattern = String with wildcards, such as $(RED "*.d"). The supported
 *		wildcard strings are described under fnmatch() in
 *		$(LINK2 std_path.html, std.path).
 *	r = Regular expression, for more powerful _pattern matching.
 * Example:
 *	This program lists all the files with a "d" extension in
 *	the path passed as the first argument.
 * ----
 * import std.stdio;
 * import std.file;
 *
 * void main(char[][] args)
 * {
 *    auto d_source_files = std.file.listdir(args[1], "*.d");
 *
 *    foreach (d; d_source_files)
 *	writefln(d);
 * }
 * ----
 * A regular expression version that searches for all files with "d" or
 * "obj" extensions:
 * ----
 * import std.stdio;
 * import std.file;
 * import std.regexp;
 *
 * void main(char[][] args)
 * {
 *    auto d_source_files = std.file.listdir(args[1], RegExp(r"\.(d|obj)$"));
 *
 *    foreach (d; d_source_files)
 *	writefln(d);
 * }
 * ----
 */

char[][] listdir(char[] pathname, char[] pattern)
{   char[][] result;

    bool callback(DirEntry* de)
    {
	if (de.isdir)
	    listdir(de.name, &callback);
	else
	{   if (stdx.path.fnmatch(de.name, pattern))
		result ~= de.name;
	}
	return true; // continue
    }

    listdir(pathname, &callback);
    return result;
}

/** Ditto */
/+
char[][] listdir(char[] pathname, RegExp r)
{   char[][] result;

    bool callback(DirEntry* de)
    {
	if (de.isdir)
	    listdir(de.name, &callback);
	else
	{   if (r.test(de.name))
		result ~= de.name;
	}
	return true; // continue
    }

    listdir(pathname, &callback);
    return result;
}
+/

/******************************************************
 * For each file and directory name in pathname[],
 * pass it to the callback delegate.
 * Params:
 *	callback =	Delegate that processes each
 *			filename in turn. Returns true to
 *			continue, false to stop.
 * Example:
 *	This program lists all the files in its
 *	path argument, including the path.
 * ----
 * import std.stdio;
 * import std.path;
 * import std.file;
 *
 * void main(char[][] args)
 * {
 *    auto pathname = args[1];
 *    char[][] result;
 *
 *    bool listing(char[] filename)
 *    {
 *      result ~= std.path.join(pathname, filename);
 *      return true; // continue
 *    }
 *
 *    listdir(pathname, &listing);
 *
 *    foreach (name; result)
 *      writefln("%s", name);
 * }
 * ----
 */

void listdir(char[] pathname, bool delegate(char[] filename) callback)
{
    bool listing(DirEntry* de)
    {
	return callback(stdx.path.getBaseName(de.name));
    }

    listdir(pathname, &listing);
}

/******************************************************
 * For each file and directory DirEntry in pathname[],
 * pass it to the callback delegate.
 * Params:
 *	callback =	Delegate that processes each
 *			DirEntry in turn. Returns true to
 *			continue, false to stop.
 * Example:
 *	This program lists all the files in its
 *	path argument and all subdirectories thereof.
 * ----
 * import std.stdio;
 * import std.file;
 *
 * void main(char[][] args)
 * {
 *    bool callback(DirEntry* de)
 *    {
 *      if (de.isdir)
 *        listdir(de.name, &callback);
 *      else
 *        writefln(de.name);
 *      return true;
 *    }
 *
 *    listdir(args[1], &callback);
 * }
 * ----
 */

void listdir(char[] pathname, bool delegate(DirEntry* de) callback)
{
    version (Tango) {
        converror(pathname, {
            foreach (FS.FileInfo fi; FilePath(pathname)) {
                DirEntry de;
                //yyy: correct?
                assert (fi.path.length && fi.path[$-1] == '/');
                de.name = fi.path ~ fi.name;
                de.m_isdir = fi.folder;
                de.size = fi.bytes;
                if (!callback(&de))
                    break;
            }
        });
    } else {
        file.listdir(pathname, delegate bool(file.DirEntry* de) {
            //blergh
            DirEntry de2;
            de2.name = de.name;
            de2.m_isdir = !!de.isdir();
            de2.size = de.size;
            return callback(&de2);
        });
    }
}

/***************************************************
 * Copy a file from[] to[].
 */

void copy(char[] from, char[] to)
{
    version (Tango) {
        converror(to, { FilePath(to).copy(from); });
    } else {
        file.copy(from, to);
    }
}


unittest
{
    //printf("std.file.unittest\n");
    void[] buf;

    buf = new void[10];
    (cast(byte[])buf)[] = 3;
    write("unittest_write.tmp", buf);
    void buf2[] = read("unittest_write.tmp");
    assert(buf == buf2);

    copy("unittest_write.tmp", "unittest_write2.tmp");
    buf2 = read("unittest_write2.tmp");
    assert(buf == buf2);

    remove("unittest_write.tmp");
    if (exists("unittest_write.tmp"))
	assert(0);
    remove("unittest_write2.tmp");
    if (exists("unittest_write2.tmp"))
	assert(0);
}

unittest
{
    /+listdir (".", delegate bool (DirEntry * de)
    {
	auto s = std.string.format("%s : c %s, w %s, a %s", de.name,
		toUTCString (de.creationTime),
		toUTCString (de.lastWriteTime),
		toUTCString (de.lastAccessTime));
	return true;
    }
    );+/
}


