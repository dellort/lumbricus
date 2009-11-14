//this uses a server which runs the web/announce.php script
//everything goes over HTTP
//(PHP sucks, but it is widely available)
module net.announce_php;

import net.announce;
import net.netlayer;
import net.marshal;

import utils.configfile;
import utils.time;
import utils.log;
import utils.misc;

import tango.net.http.HttpClient;
import tango.net.http.HttpHeaders;
//import conv = tango.util.Convert;
import tango.core.Thread;
import tango.core.Exception;
import str = utils.string;

//LogStruct!("http_get") http_log;

//get stuff from URL
//use GET method and encode args as arguments for the method
//return true or false on success or failure
//result contains the response data or an error message
private bool http_get(char[] url, out char[] result, char[][char[]] args) {
    //http_log("HTTP GET: url={} args={}", url, args);

    try {
        //hostname is resolved here (which may fail)
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
    } catch (SocketException e) {
        result = "Socket error: "~e.msg;
        return false;
    }
}

private class HttpGetter : Thread {
    private {
        alias void delegate(bool success, char[] result) ResultDg;

        bool mTerminated;
        char[] mUrl;
        char[][char[]] mArgs;
        char[] mResult;
        bool mSuccess;
        ResultDg onFinish;
    }

    this(char[] url, char[][char[]] args, ResultDg finish) {
        super(&run);
        mUrl = url.dup;
        mArgs = args;
        onFinish = finish;
        isDaemon = true;
    }

    //call this periodically to check if the request completed
    //will call onFinish once and return true if the request is done
    bool check() {
        if (!isRunning() && mTerminated) {
            mTerminated = false;
            if (onFinish)
                onFinish(mSuccess, mResult);
            return true;
        }
        return false;
    }

    private void run() {
        mResult = null;
        mSuccess = http_get(mUrl, mResult, mArgs);
        mTerminated = true;
    }
}

class PhpAnnouncer : NetAnnouncer {
    private {
        char[] mUrl;
        Time mLastUpdate;
        AnnounceInfo mInfo;
        char[] mInfoData;
        LogStruct!("php_server_announce") log;
        bool mActive;
        HttpGetter mLastGetter;
    }

    const Time cUpdateTime = timeSecs(30);

    this(ConfigNode cfg) {
        mUrl = cfg.getStringValue("script_url");
    }

    bool isInternet() {
        return true;
    }

    override void tick() {
        if (mActive && timeCurrentTime() > mLastUpdate + cUpdateTime)
            do_update();
    }

    //actually trigger a PHP request to add/update/keep-alive the announcement
    void do_update() {
        log("announcing");
        char[][char[]] hdrs;
        hdrs["action"] = "add";
        hdrs["port"] = myformat("{}", mInfo.port);
        hdrs["info"] = mInfoData;
        //run and forget, we don't need the result
        mLastGetter = new HttpGetter(mUrl, hdrs, null);
        mLastGetter.start();
        mLastUpdate = timeCurrentTime();
    }

    void do_remove() {
        log("removing");
        char[][char[]] hdrs;
        hdrs["action"] = "remove";
        hdrs["port"] = myformat("{}", mInfo.port);
        mLastGetter = new HttpGetter(mUrl, hdrs, null);
        mLastGetter.start();
    }

    override void update(AnnounceInfo info) {
        if (mInfo == info)
            return;
        mInfo = info;
        mInfoData = marshalBase64(info);
        do_update();
    }

    override void active(bool act) {
        if (act == mActive)
            return;
        mActive = act;
        if (act)
            do_update();
        else
            do_remove();
    }

    override void close() {
        active = false;
        //on shutdown, wait for remove request to finish
        mLastGetter.join();
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
        bool mActive;
        HttpGetter mGetter;
    }

    const Time cUpdateTime = timeSecs(10);

    this(ConfigNode cfg) {
        mUrl = cfg.getStringValue("script_url");
        char[][char[]] hdrs;
        hdrs["action"] = "list";
        mGetter = new HttpGetter(mUrl, hdrs, &requestFinish);
    }

    override void tick() {
        mGetter.check();
        if (mActive && timeCurrentTime() > mLastUpdateTime + cUpdateTime)
            do_update();
    }

    void do_update() {
        //only one update a time
        if (mGetter.isRunning())
            return;
        mGetter.start();
        mLastUpdateTime = timeCurrentTime();
    }

    void requestFinish(bool success, char[] result) {
        mServers.length = 0;
        if (success) {
            auto lines = str.splitlines(result);
            forline: foreach (line; lines) {
                //expected format: address|time|info
                //we don't actually need time?
                auto comps = str.split(line, "|");
                if (comps.length == 3) {
                    ServerInfo sinf;
                    //NetAddress ctor parses the text; throws no exceptions
                    auto addr = NetAddress(comps[0]);
                    try {
                        sinf.info = unmarshalBase64!(AnnounceInfo)(comps[2]);
                    } catch (UnmarshalException e) {
                        //ignore bad entries
                        continue forline;
                    }
                    sinf.address = addr.hostName;
                    sinf.info.port = addr.port;
                    //not sure about rest
                    mServers ~= sinf;
                }
            }
        }
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
        if (act == mActive)
            return;
        mActive = act;
        if (mActive)
            do_update();
    }

    override bool active() {
        return mActive;
    }

    override void close() {
        //nothing to do, yay for HTTP being stateless
    }

    static this() {
        AnnounceClientFactory.register!(typeof(this))("php");
    }
}
