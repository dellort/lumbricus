module net.announce_irc;

import irclib.all;
import net.announce;
import utils.random;
import utils.time;
import utils.configfile;

import str = stdx.string;
import tango.util.Convert;
import tango.core.Exception;

const cDefIrcServer = "chat.freenode.net";
const cDefIrcChannel = "#lumbricus.announce";

//IRC client implementation, used both by server announcer and client searcher
private class AnnIrc : IrcClient {
    char[] channelName;
    bool inChannel;
    char[] myAddress;

    void delegate() onDisconnect;
    void delegate(char[] fromNick, char[] msg) onChatMessage;
    void delegate(char[] channel) onJoinChannel;

	this(char[] serverHostAndPort)
	{
		super(serverHostAndPort);
        //fullName  = "Lumbricus Terrestris";
        userName  = "foobar";
        newNick();
	}

	void newNick() {
	    //choose a random nick
	    //note: if we happen to choose an existing nick, the error message
	    //  is handled and this is called again
        nick = myformat("lt{}", rngShared.next());
	}

	void say(char[] msg) {
        sendMessage(channelName, msg);
	}

    protected override void onChannelMessageReceived(IrcChannelMessage imsg) {
        if (onChatMessage)
            onChatMessage(imsg.fromNick, irclib.tools.strip(imsg.message));
    }

	protected override void onLoggedIn()
	{
		sendLine("JOIN " ~ channelName);
		sendLine("USERHOST " ~ nick);
	}

    protected override void onChannelJoin(ChannelJoin cjoin) {
        if(cjoin.fromNick == nick) {
            //join succeeded
            if (onJoinChannel)
                onJoinChannel(cjoin.channelName);
            inChannel = true;
        }
    }

    protected override void waitForEvent() {
        //nothing
        //finishConnect calls this
    }

    void checkEvents() {
        //if (!mEnableEvents)
            //return;
        //if someone DOSes you on IRC, you have lost the game
        while (doCheck()) { }
    }

    //as far as I understand waitForEvent(), it loops and returns only on
    //disconnection... so, this code duplication is still needed :(
    private bool doCheck() {
        if (!socket())
            return false;

        bool progress;

        SocketSet ssread, sswrite;
        ssread = new SocketSet;
        sswrite = new SocketSet;

        const uint NUM_BYTES = 1024;
        ubyte[NUM_BYTES] _data = void;
        void* data = _data.ptr;

        ssread.reset();
        sswrite.reset();
        ssread.add(socket);
        if(clientQueue.writeBytes)
            sswrite.add(socket);

        //non-blocking
        timeval tv = timeval(0, 0);
        auto sl = Socket.select(ssread, sswrite, null, &tv);
        if(sl > 0) {
            if(ssread.isSet(socket))
            {
                int sv;
                sv = socket.receive(data[0 .. NUM_BYTES]);
                switch(sv)
                {
                    case Socket.ERROR: // Connection error.
                        try
                        {
                            onConnectionError();
                        }
                        finally
                        {
                            serverDisconnected();
                        }
                        return false; // No more event loop.

                    case 0: // Connection closed.
                        serverDisconnected();
                        return false; // No more event loop.

                    default:
                        // Assumes onDataReceived() duplicates the data.
                        clientQueue.onDataReceived(data[0 .. sv]);
                        serverReadData(); // Tell the IrcProtocol about the new data.
                }
            }

            if(sswrite.isSet(socket))
            {
                clientQueue.onSendComplete();
            }

            progress = true;
        } else if (sl == -1) {
            //interrupted, try again
            progress = true;
        }
        return progress;
    }

    override protected void onCommand(char[] prefix, char[] cmd,
        char[] cmdParams)
    {
        switch (cmd) {
            case "302":  //RPL_USERHOST
                //servers will post their hostname with the announce,
                //it would take the client too long to get all IPs via whois
                char[][] m = str.split(cmdParams, "@");
                myAddress = str.strip(m[$-1]);
                break;
            case "433":  //ERR_NICKNAMEINUSE
                //randomize nickname again
                newNick();
                break;
            default:
        }
        super.onCommand(prefix, cmd, cmdParams);
    }

    void disconnect() {
        serverDisconnected();
    }

    override protected void onDisconnected() {
        if (onDisconnect)
            onDisconnect();
    }
}


//Server part of IRC announcer, will post announce message in an IRC channel
//periodically
private class IrcAnnouncer : NetAnnouncer {
    private {
        char[] mServer;
        AnnIrc mIrc;
        Time mLastTime;
        AnnounceInfo mInfo;
        bool mActive;

        //will post announce message at this interval
        const cAnnounceInterval = timeSecs(6);
    }

    this(ConfigNode cfg) {
        mServer = cfg.getStringValue("server", cDefIrcServer);
        mIrc = new AnnIrc(mServer);
        mIrc.onDisconnect = &ircDisconnect;
        mIrc.channelName = cfg.getStringValue("channel", cDefIrcChannel);
    }

    void active(bool act) {
        if (act == mActive)
            return;
        mActive = act;
        if (act) {
            try {
                //xxx: Blocking call
                mIrc.connect();
                mLastTime = timeCurrentTime();
            } catch (IrcClientException e) {
                //connection failed
                mActive = false;
            } catch (SocketException e) {
                mActive = false;
            }
        } else {
            mIrc.disconnect();
        }
    }

    void tick() {
        if (!mActive)
            return;
        mIrc.checkEvents();
        //if connected and joined, post message
        if (mIrc.inChannel && mIrc.myAddress.length > 0) {
            Time t = timeCurrentTime();
            if (t - mLastTime > cAnnounceInterval) {
                //address:port:players:maxPlayers:name
                mIrc.say(myformat("{}:{}:{}:{}:{}", mIrc.myAddress, mInfo.port,
                    mInfo.curPlayers, mInfo.maxPlayers, mInfo.serverName));
                mLastTime = t;
            }
        }
    }

    void update(AnnounceInfo info) {
        mInfo = info;
        //clear colon from servername, is used as separator above
        mInfo.serverName = str.replace(mInfo.serverName, ":", "_");
    }

    void close() {
        mIrc.disconnect();
    }

    private void ircDisconnect() {
        mActive = false;
    }

    static this() {
        AnnouncerFactory.register!(typeof(this))("irc");
    }
}


//Client part of IRC announcer, monitors a channel for announce messages
//and assembles a server list from that
class IrcAnnounceClient : NACPeriodically {
    private {
        char[] mServer;
        AnnIrc mIrc;
        bool mActive;
    }

    this(ConfigNode cfg) {
        mServer = cfg.getStringValue("server", cDefIrcServer);
        mIrc = new AnnIrc(mServer);
        mIrc.channelName = cfg.getStringValue("channel", cDefIrcChannel);
        mIrc.onDisconnect = &ircDisconnect;
        mIrc.onChatMessage = &onChatMessage;
    }

    void active(bool act) {
        if (act == mActive)
            return;
        mActive = act;
        if (act) {
            try {
                //xxx: Blocking call
                mIrc.connect();
            } catch (IrcClientException e) {
                //connection failed
                mActive = false;
            } catch (SocketException e) {
                mActive = false;
            }
        } else {
            mIrc.disconnect();
            mServers = null;
        }
    }
    bool active() {
        return mActive;
    }

    void close() {
        active = false;
    }

    void tick() {
        if (!mActive)
            return;
        mIrc.checkEvents();
    }

    private void ircDisconnect() {
        active = false;
    }

    private void onChatMessage(char[] fromNick, char[] msg) {
        //parse the announce message from one server
        char[][] parts = str.split(msg, ":");
        if (parts.length == 5) {
            AnnounceInfo ai;
            ai.port = to!(ushort)(parts[1]);
            ai.curPlayers = to!(int)(parts[2]);
            ai.maxPlayers = to!(int)(parts[3]);
            ai.serverName = parts[4];

            refreshServer(parts[0], ai);
        }
    }

    static this() {
        AnnounceClientFactory.register!(typeof(this))("irc");
    }
}
