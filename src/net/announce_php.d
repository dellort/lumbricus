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
private bool http_get(string url, out string result, string[string] args) {
    //http_log("HTTP GET: url=%s args=%s", url, args);

    try {
        //hostname is resolved here (which may fail)
        auto client = new HttpClient(HttpClient.Get, url);
        //5 seconds timeout
        client.setTimeout(5.0f);
        scope(exit) client.close();

        foreach (string k, string v; args) {
            client.getRequestParams().add(k, v);
        }

        string res;

        void getstuff(void[] d) {
            //xxx: content encoding?
            //     we always must have utf-8, or at least sanitized to utf-8
            res ~= cast(string)d;
        }

        client.open();

        if (client.isResponseOK) {
            auto length = client.getResponseHeaders.getInt(HttpHeader.ContentLength);
            client.read(&getstuff, length);
            result = res;
            return true;
        } else {
            //hm, I don't know
            result = "HTTP error: " ~ client.getResponse().toString();
            return false;
        }
    } catch (SocketException e) {
        result = "Socket error: "~e.msg;
        return false;
    }
}

private class HttpGetter : Thread {
    private {
        alias void delegate(bool success, string result) ResultDg;

        bool mTerminated;
        string mUrl;
        string[string] mArgs;
        string mResult;
        bool mSuccess;
        ResultDg onFinish;
    }

    this(string url, string[string] args, ResultDg finish) {
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

private LogStruct!("php_announce") log;

class PhpAnnouncer : NetAnnouncer {
    private {
        string mUrl;
        Time mLastUpdate;
        AnnounceInfo mInfo;
        bool mActive;
        HttpGetter mLastGetter;
    }

    enum Time cUpdateTime = timeSecs(30);

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
    private void do_update() {
        log("announcing");
        string[string] hdrs;
        hdrs["action"] = "add";
        hdrs["port"] = myformat("%s", mInfo.port);
        //run and forget, we don't need the result
        mLastGetter = new HttpGetter(mUrl, hdrs, null);
        mLastGetter.start();
        mLastUpdate = timeCurrentTime();
    }

    private void do_remove() {
        log("removing");
        string[string] hdrs;
        hdrs["action"] = "remove";
        hdrs["port"] = myformat("%s", mInfo.port);
        mLastGetter = new HttpGetter(mUrl, hdrs, null);
        mLastGetter.start();
    }

    override void update(AnnounceInfo info) {
        if (mInfo == info)
            return;
        mInfo = info;
        if (mActive)
            do_update();
    }

    override void active(bool act) {
        if (act == mActive)
            return;
        log("active = %s", act);
        mActive = act;
        if (act)
            do_update();
        else
            do_remove();
    }

    override void close() {
        active = false;
        //on shutdown, wait for remove request to finish
        if (mLastGetter)
            mLastGetter.join();
    }

    static this() {
        AnnouncerFactory.register!(typeof(this))("php");
    }
}

class PhpAnnounceClient : NetAnnounceClient {
    private {
        string mUrl;
        Time mLastUpdateTime;
        ServerAddress[] mServers;
        bool mActive;
        HttpGetter mGetter;
    }

    //regular update of server list (will also be updated when active gets true)
    enum Time cUpdateTime = timeSecs(60);

    this(ConfigNode cfg) {
        mUrl = cfg.getStringValue("script_url");
        string[string] hdrs;
        hdrs["action"] = "blist";
        mGetter = new HttpGetter(mUrl, hdrs, &requestFinish);
    }

    override void tick() {
        mGetter.check();
        if (mActive && timeCurrentTime() > mLastUpdateTime + cUpdateTime)
            do_update();
    }

    private void do_update() {
        //only one update a time
        if (mGetter.isRunning())
            return;
        log("Updating");
        mGetter.start();
        mLastUpdateTime = timeCurrentTime();
    }

    private void requestFinish(bool success, string result) {
        mServers.length = 0;
        if (success) {
            log("requestFinish OK (length = %s)", result.length);
            //result is a binary list (4 bytes ip, 2 bytes port little endian)
            for (int idx = 0; idx + 6 <= result.length; idx += 6) {
                ServerAddress saddr;
                //xxx convert on big endian platform (I'm lazy)
                saddr.address = *cast(uint*)(result.ptr + idx);
                saddr.port = *cast(ushort*)(result.ptr + idx + 4);
                mServers ~= saddr;
            }
        } else {
            log.warn("Request failed (%s)", result);
        }
    }

    ///loop over internal server list
    ///behavior is implementation-specific, but it should be implemented to
    ///block as short as possible (best not at all)
    override int opApply(scope int delegate(ref ServerAddress) del) {
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
        log("active = %s", act);
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
