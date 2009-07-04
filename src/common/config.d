module common.config;

import framework.filesystem;
import utils.configfile;
import utils.gzip;
import utils.log;
import utils.output;
import utils.path;

import utils.stream;

private ConfigManager gConfigMgr;
ConfigManager gConf() {
    if (!gConfigMgr)
        new ConfigManager();
    return gConfigMgr;
}

//global singleton for configfile loading/saving (lol, didn't know where else
//  to put it), access via gConf
private class ConfigManager {
    private LogStruct!("configfile") logConf;
    private LogStruct!("configerror") logError;

    this() {
        assert(!gConfigMgr, "singleton");
        gConfigMgr = this;
    }

    ///load a config file from disk; file will be automatically unpacked
    ///if applicable
    ///Params:
    ///  asfilename = true: append ".conf" to section name
    ///  allowFail = if the passed file could not be loaded, a value of
    ///       false -> will throw an exception (default)
    ///       true  -> will return null
    ConfigNode loadConfig(char[] section, bool asfilename = false,
        bool allowFail = false)
    {
        char[] fnConf = section ~ (asfilename ? "" : ".conf");
        VFSPath file = VFSPath(fnConf);
        VFSPath fileGz = VFSPath(fnConf~".gz");
        bool gzipped;
        if (!gFS.exists(file) && gFS.exists(fileGz)) {
            //found gzipped file instead of original
            file = fileGz;
            gzipped = true;
        }
        logConf("load config: {}", file);
        char[] data;
        try {
            Stream stream = gFS.open(file);
            scope (exit) { if (stream) stream.close(); }
            assert (!!stream);
            data = cast(char[])stream.readAll();
        } catch (FilesystemException e) {
            if (!allowFail)
                throw e;
            goto error;
        }
        if (gzipped) {
            try {
                data = cast(char[])gunzipData(cast(ubyte[])data);
            } catch (ZlibException e) {
                if (!allowFail)
                    throw new Exception("Decompression failed: "~e.msg);
                goto error;
            }
        }
        //xxx: if parsing fails? etc.
        auto f = new ConfigFile(data, file.get(), &doLogError);
        if (!f.rootnode)
            throw new Exception("?");
        return f.rootnode;

    error:
        logError("config file {} failed to load (allowFail = true)", file);
        return null;
    }

    ///Same as above, but will return an empty ConfigNode on error
    ///Never returns null or throws
    ConfigNode loadConfigDef(char[] section, bool asfilename = false) {
        ConfigNode res = loadConfig(section, asfilename, true);
        if (!res)
            res = new ConfigNode();
        return res;
    }

    private void doLogError(char[] log) {
        logError("{}", log);
    }

    //arrgh
    //compress = true: do gzip compression, adds .gz to filename
    void saveConfig(ConfigNode node, char[] filename, bool compress = false) {
        if (compress) {
            saveConfigGz(node, filename~".gz");
            return;
        }
        auto stream = gFS.open(filename, File.WriteCreate);
        try {
            auto textstream = new StreamOutput(stream);
            node.writeFile(textstream);
        } finally {
            stream.close();
        }
    }

    //same as above, always gzipped
    //will not modify file extension
    void saveConfigGz(ConfigNode node, char[] filename) {
        auto stream = gFS.open(filename, File.WriteCreate);
        try {
            /*ubyte[] txt = cast(ubyte[])node.writeAsString();
            ubyte[] gz = gzipData(txt);
            stream.write(gz);*/
            auto w = new GZStreamOutput(stream);
            node.writeFile(w);
            w.finish();
        } finally {
            stream.close();
        }
    }

    ubyte[] saveConfigGzBuf(ConfigNode node) {
        /+scope buf = new MemoryStream();
        scope gz = new GZStreamOutput(buf);
        node.writeFile(gz);
        gz.finish();
        return buf.data();+/
        assert(false, "yyy fix me");
    }

    ConfigNode loadConfigGzBuf(ubyte[] buf) {
        auto data = cast(char[])gunzipData(buf);
        auto f = new ConfigFile(data, "MemoryBuffer", &doLogError);
        if (!f.rootnode)
            throw new Exception("?");
        return f.rootnode;
    }
}
