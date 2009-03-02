module common.config;

import framework.filesystem;
import utils.configfile;
import utils.gzip;
import utils.log;
import utils.output;
import utils.path;

import stdx.stream;

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
            data = stream.readString(stream.size());
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
        auto stream = gFS.open(filename, FileMode.OutNew);
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
        auto stream = gFS.open(filename, FileMode.OutNew);
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
}
