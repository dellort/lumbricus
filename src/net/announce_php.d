//this uses a server which runs the web/announce.php script
//everything goes over HTTP
//(PHP sucks, but it is widely available)
module net.announce_php;

import net.announce;
import net.netlayer;

import utils.configfile;
import utils.time;
import utils.log;
import utils.misc;

import tango.net.http.HttpClient;
import tango.net.http.HttpHeaders;
//import conv = tango.util.Convert;
import str = stdx.string;

LogStruct!("http_get") http_log;

//get stuff from URL
//use GET method and encode args as arguments for the method
//return true or false on success or failure
//result contains the response data or an error message
private bool http_get(char[] url, out char[] result, char[][char[]] args) {
    http_log("HTTP GET: url={} args={}", url, args);

    auto client = new HttpClient(HttpClient.Get, url);
    scope(exit) client.close();

    foreach (char[] k, char[] v; args) {
        client.getRequestParams().add(k, v);
    }

    char[] res;

    void getstuff(void[] d) {
        //xxx: content encoding?
        //     we always must have utf-8, or at least sanitized to utf-8
        res ~= cast(char[])d;
    }

    client.open();

    if (client.isResponseOK) {
        auto length = client.getResponseHeaders.getInt(HttpHeader.ContentLength);
        client.read(&getstuff, length);
        result = res;
        return true;
    } else {
        //hm, I don't know
        result = "HTTP error: I have no idea";
        return false;
    }
}

class PhpAnnouncer : NetAnnouncer {
    private {
        char[] mUrl;
        Time mLastUpdate;
        AnnounceInfo mInfo;
        LogStruct!("php_server_announce") log;
    }

    const Time cUpdateTime = timeSecs(30);

    this(ConfigNode cfg) {
        mUrl = cfg.getStringValue("script_url");
    }

    override void tick() {
        if (timeCurrentTime() > mLastUpdate + cUpdateTime)
            do_update();
    }

    //actually trigger a PHP request to add/update/keep-alive the announcement
    void do_update() {
        log("announcing");
        char[] res;
        char[][char[]] hdrs;
        hdrs["action"] = "add";
        hdrs["port"] = myformat("{}", mInfo.port);
        hdrs["info"] = "huh";
        http_get(mUrl, res, hdrs);
        mLastUpdate = timeCurrentTime();
    }

    override void update(AnnounceInfo info) {
        mInfo = info;
        do_update();
    }

    override void active(bool act) {
        //???
    }

    override void close() {
        //could do remove request, for now let it timeout
    }

    static this() {
        AnnouncerFactory.register!(typeof(this))("php");
    }
}

class PhpAnnounceClient : NetAnnounceClient {
    private {
        char[] mUrl;
        Time mLastUpdateTime;
        ServerInfo[] mServers;
    }

    const Time cUpdateTime = timeSecs(10);

    this(ConfigNode cfg) {
        mUrl = cfg.getStringValue("script_url");
    }

    override void tick() {
        if (timeCurrentTime() > mLastUpdateTime + cUpdateTime)
            do_update();
    }

    void do_update() {
        mServers.length = 0;
        char[][char[]] hdrs;
        hdrs["action"] = "list";
        char[] res;
        if (http_get(mUrl, res, hdrs)) {
            auto lines = str.splitlines(res);
            forline: foreach (line; lines) {
                //expected format: address|time|info
                //we don't actually need time?
                auto comps = str.split(line, "|");
                if (comps.length == 3) {
                    ServerInfo sinf;
                    //xxx: why do I need to parse the address? netlayer.d can
                    //     do this already , arg!
                    auto addr = NetAddress(comps[0]);
                    sinf.address = addr.hostName;
                    sinf.info.port = addr.port;
                    //not sure about rest
                    mServers ~= sinf;
                }
            }
        }
        mLastUpdateTime = timeCurrentTime();
    }

    ///loop over internal server list
    ///behavior is implementation-specific, but it should be implemented to
    ///block as short as possible (best not at all)
    override int opApply(int delegate(ref ServerInfo) del) {
        int result = 0;
        foreach (s; mServers) {
            result = del(s);
            if (result)
                break;
        }
        return result;
    }

    ///Client starts inactive
    override void active(bool act) {
    }

    override bool active() {
        return false;
    }

    override void close() {
        //nothing to do, yay for HTTP being stateless
    }

    static this() {
        AnnounceClientFactory.register!(typeof(this))("php");
    }
}