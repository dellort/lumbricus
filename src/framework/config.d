module framework.config;

///Various utility functions for configfile loading
///(user-friendly shortcuts, error reporting, compression etc.)

import framework.filesystem;
import utils.configfile;
import utils.gzip;
import utils.log;
import utils.path;
import utils.stream;
import utils.misc;

private LogStruct!("configfile") logConf;

///load a config file from disk; file will be automatically unpacked
///if applicable
///Params:
///  allowFail = if the passed file could not be loaded, a value of
///       false -> will throw an exception (default)
///       true  -> will return null
ConfigNode loadConfig(string filename, bool allowFail = false)
{
    VFSPath file = VFSPath(filename);
    VFSPath fileGz = VFSPath(filename~".gz");
    bool gzipped;
    if (!gFS.exists(file) && gFS.exists(fileGz)) {
        //found gzipped file instead of original
        file = fileGz;
        gzipped = true;
    }
    logConf("load config: %s", file);
    string data;
    try {
        Stream stream = gFS.open(file);
        scope (exit) { if (stream) stream.close(); }
        assert (!!stream);
        data = cast(string)stream.readAll();
    } catch (FilesystemException e) {
        if (!allowFail)
            throw e;
        goto error;
    }
    if (gzipped) {
        try {
            data = cast(string)gunzipData(cast(ubyte[])data);
        } catch (ZlibException e) {
            if (!allowFail)
                throw new CustomException("Decompression failed: "~e.msg);
            goto error;
        }
    }
    //xxx: if parsing fails? etc.
    auto f = new ConfigFile(data, file.get());
    if (!f.rootnode)
        throw new CustomException("?");
    return f.rootnode;

error:
    logConf.minor("config file %s failed to load (allowFail = true)", file);
    return null;
}

///Same as above, but will return an empty ConfigNode on error
///Never returns null or throws
ConfigNode loadConfigDef(string filename) {
    ConfigNode res = loadConfig(filename, true);
    if (!res)
        res = new ConfigNode();
    return res;
}

private bool doSaveConfig(ConfigNode node, string filename, bool compress,
    bool logerror = true)
{
    try {
        auto stream = gFS.open(filename, "w");
        scope(exit) stream.close();
        auto outw = stream.pipeOut();
        if (compress)
            outw = GZWriter.Pipe(outw);
        scope(exit) outw.close();
        node.writeFile(outw);
        return true;
    } catch (FilesystemException e) {
        //this is perfectly fine: just show the user the error (unless the
        //  caller would like to detect this failure programmatically => return
        //  value and logerror param)
        if (logerror)
            logConf.error("saving config file %s failed: %s", filename, e);
        return false;
    }
}

//arrgh
//compress = true: do gzip compression, adds .gz to filename
bool saveConfig(ConfigNode node, string filename, bool compress = false) {
    return compress
        ? doSaveConfig(node, filename~".gz", true)
        : doSaveConfig(node, filename, false);
}

//same as above, always gzipped
//will not modify file extension
bool saveConfigGz(ConfigNode node, string filename) {
    return doSaveConfig(node, filename, true);
}

ubyte[] saveConfigGzBuf(ConfigNode node) {
    ArrayWriter a;
    auto w = GZWriter.Pipe(a.pipe());
    node.writeFile(w);
    w.close();
    return a.data();
}

ConfigNode loadConfigGzBuf(ubyte[] buf) {
    auto data = cast(string)gunzipData(buf);
    auto f = new ConfigFile(data, "MemoryBuffer");
    if (!f.rootnode)
        throw new CustomException("?");
    return f.rootnode;
}
