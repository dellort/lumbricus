module irc.ircclient;

import common.common;
import common.task;
import framework.framework;
import framework.commandline : CommandBucket, Command;
import gui.container;
import gui.console;
import gui.widget;
import gui.wm;
import irclib.all;
import std.conv : toUshort;
import std.string : find;
import std.thread;
import utils.mybox;
import utils.configfile;
import utils.output;

version(Windows) {
    pragma(lib,"ws2_32");
}

interface IRCOutput {
	//Output a line of text
	void writeChat(char[] nick, char[] s);
	void writeAction(char[] nick, char[] s);
	void writeNotice(char[] nick, char[] s);
	//Write status information
	void writeInfo(char[] s);

	//clear list of nicknames
	void clearNicks();
	//add a nick to the nick list
	void addNick(char[] nick);
	//remove a nick from the list
	void removeNick(char[] nick);
	//change an existing nick
	void changeNick(char[] oldNick, char[] newNick);
}

class WIrcClient : IrcClient {
    private IRCOutput mOutput;
    private bool mEnableEvents, mGettingNames;

    this(IRCOutput write) {
        mOutput = write;
    }

    void connectTo(char[] server) {
        disconnect();
        mOutput.writeInfo("Connecting to '"~server~"'...");

        try {
            int i = find(server, ":");

            if (i == -1) {
                serverHost = server;
                serverPort = DEFAULT_PORT;
            } else {
                serverHost = server[0..i];
                serverPort = toUshort(server[i+1..$]);
            }

            connect();
            mOutput.writeInfo("Connected");
        } catch (IrcClientException ie) {
            mOutput.writeInfo("Connection failed: "~ie.msg);
        }
    }

    void disconnect() {
        if (isConnected) {
            mOutput.writeInfo("Disconnected");
            serverDisconnected();
        }
    }

    void join(char[] chan) {
		sendLine("JOIN " ~ chan);
    }

    void say(char[] chan, char[] msg) {
        sendMessage(chan, msg);
        mOutput.writeChat(nick, irclib.tools.strip(msg));
    }

    void privmsg(char[] targetnick, char[] msg) {
        sendMessage(targetnick, msg);
        //no output
    }

    void me(char[] chan, char[] msg) {
        sendAction(chan, msg);
        mOutput.writeAction(nick, irclib.tools.strip(msg));
    }

	protected override void onChannelMessageReceived(IrcChannelMessage imsg) {
		mOutput.writeChat(imsg.fromNick,irclib.tools.strip(imsg.message));
	}

	protected override void onChannelActionReceived(IrcChannelMessage imsg) {
		mOutput.writeAction(imsg.fromNick,irclib.tools.strip(imsg.message));
	}

	protected override void onUserNoticeReceived(IrcUserMessage imsg) {
		mOutput.writeNotice(imsg.fromNick,irclib.tools.strip(imsg.message));
	}

	protected override void onTopicChanged(ChannelTopic ctopic) {
		mOutput.writeInfo(ctopic.fromNick ~ " has changed the topic to '" ~
			irclib.tools.strip(ctopic.topic) ~ "'");
	}

	protected override void onTopicReply(ChannelTopicReply ctr) {
		mOutput.writeInfo("Topic is '" ~ irclib.tools.strip(ctr.topic) ~ "'");
	}

	protected override void onTopicWhoTimeReply(ChannelTopicWhoTimeReply ctwtr) {
		mOutput.writeInfo("Topic was set by " ~ ctwtr.setter ~ ".");
	}

	protected override void onChannelJoin(ChannelJoin cjoin) {
		mOutput.addNick(cjoin.fromNick.dup);

		if(cjoin.fromNick == nick) {
			mOutput.writeInfo("You have joined the channel.");
		} else {
			mOutput.writeInfo(cjoin.fromNick ~ " has joined the channel.");
		}
	}

	private void userleft(IrcFrom who, char[] reason) {
		mOutput.removeNick(who.fromNick);

		char[] s;
		s = who.fromNick ~ " has left the channel";
		if(reason.length)
			s ~= " (" ~ reason ~ ")";
		else
			s ~= ".";
		mOutput.writeInfo(s);
	}

	protected override void onChannelPart(ChannelPart cpart) {
		userleft(cpart, cpart.reason);
	}

	protected override void onQuit(IrcQuit iquit) {
		if(iquit.fromNick != nick)
			userleft(iquit, iquit.reason);
	}

	protected override void onChannelKick(ChannelKick ckick) {
		mOutput.removeNick(ckick.kickedNick);

		mOutput.writeInfo(ckick.fromNick ~ " has kicked " ~ ckick.kickedNick ~
			" from the channel (" ~ irclib.tools.strip(ckick.reason) ~ ")");
	}

	protected override void onNick(IrcNick inick) {
		mOutput.changeNick(inick.fromNick, inick.newNick);

		mOutput.writeInfo(inick.fromNick ~ " is now known as " ~ inick.newNick ~ ".");
	}

	protected override void onLoggedIn()
	{
		//do something, e.g. join default channel
	}

	protected override void onCommand(char[] prefix, char[] cmd, char[] cmdParams)
	{
		char[] s, chan;

		switch(cmd)
		{
			case "353": // RPL_NAMREPLY
				if(!mGettingNames)
				{
					mGettingNames = true;
					mOutput.clearNicks();
				}

				ircParam(cmdParams); // My nick.
				ircParam(cmdParams); // Channel type.
				chan = ircParam(cmdParams);
				s = ircParam(cmdParams); // The names.

				foreach(char[] nick; std.string.split(s, " "))
				{
					if(nick.length)
					{
						if(std.string.find(prefixSymbols, nick[0]) != -1)
							nick = nick[1 .. nick.length];
						mOutput.addNick(nick.dup);
					}
				}
				return;

			case "366": // RPL_ENDOFNAMES
				mGettingNames = false;

				break;

			default: ;
		}

		super.onCommand(prefix, cmd, cmdParams);
	}

    protected override void waitForEvent() {
	    //don't wait after successful connection,
	    //events are checked by checkEvents()
	    mEnableEvents = true;
	}

	protected override void serverDisconnected() {
	    mEnableEvents = false;
	}

	void checkEvents() {
	    if (!mEnableEvents)
            return;

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

        int sl;
        //non-blocking
        sl = Socket.select(ssread, sswrite, null, 0);
        if(sl != -1) {// Interrupted.
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
                        return; // No more event loop.

                    case 0: // Connection closed.
                        serverDisconnected();
                        return; // No more event loop.

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
        }
	}
}

class WIrcThread : Thread {
    private WIrcClient mIrc;
    private char[] mServerPending, mServer;
    private bool mTerminated;

    this(IRCOutput outp) {
        super();
        mIrc = new WIrcClient(outp);
    }

    override int run() {
        while (!mTerminated) {
            if (mServerPending != mServer) {
                if (mServerPending.length) {
                    mIrc.connectTo(mServerPending);
                } else {
                    mIrc.disconnect();
                }
                mServer = mServerPending;
            }
            mIrc.checkEvents();
            yield();
        }
        mIrc.disconnect();
        return 0;
    }

    void terminate() {
        mTerminated = true;
    }

    void nick(char[] n) {
        mIrc.nick = n;
    }
    char[] nick() {
        return mIrc.nick;
    }

    void userName(char[] n) {
        mIrc.userName = n;
    }
    char[] userName() {
        return mIrc.userName;
    }

    void fullName(char[] n) {
        mIrc.fullName = n;
    }
    char[] fullName() {
        return mIrc.fullName;
    }

    void connect(char[] server) {
        mServerPending = server;
    }

    void disconnect() {
        mServerPending = null;
    }

    void join(char[] chan) {
		mIrc.join(chan);
    }

    void say(char[] chan, char[] msg) {
        mIrc.say(chan, msg);
    }

    void privmsg(char[] targetnick, char[] msg) {
        mIrc.privmsg(targetnick, msg);
    }

    void me(char[] chan, char[] msg) {
        mIrc.me(chan, msg);
    }
}

class IRCFrame : Container, IRCOutput {
    private Task mOwner;
    private GuiConsole mConsole;
    private WIrcThread mIrc;
    private char[] mChannel;
    private ConfigNode mCfg;

    this(Task owner) {
        mOwner = owner;
        mCfg = globals.loadConfig("irc");

        mConsole = new GuiConsole;
        mConsole.console.writefln("Welcome to wIRC!");
        mConsole.console.writefln("List commands with /help");
        mConsole.cmdline.registerCommand("say", &cmdSay, "hullo!",
            ["text...:what you say"]);
        mConsole.cmdline.registerCommand("quit", &cmdQuit, "Quit wIRC",
            ["text...:Quit reason"]);
        mConsole.cmdline.registerCommand("server", &cmdServer,
            "Connect to a server", ["text:Server address"]);
        mConsole.cmdline.registerCommand("join", &cmdJoin, "Join a channel",
            ["text:Channel name"]);
        mConsole.cmdline.registerCommand("part", &cmdPart, "Leave a channel",
            ["text?:Channel name"]);
        mConsole.cmdline.registerCommand("me", &cmdMe, "Say what you do",
            ["text...:Message"]);
        mConsole.cmdline.registerCommand("msg", &cmdMsg, "PrivMsg someone",
            ["text:Nick","text...:Message"]);
        mConsole.cmdline.registerCommand("nick", &cmdNick, "Change your name",
            ["text:New nick"]);
        mConsole.cmdline.setPrefix("/", "say");
        addChild(mConsole);

        mIrc = new WIrcThread(this);
        mIrc.nick = mCfg.getStringValue("nick");
        mIrc.userName = mCfg.getStringValue("emailuser");
        mIrc.fullName = mCfg.getStringValue("fullname");
        mIrc.start();
    }

    void quit(char[] reason) {
        mIrc.disconnect();
        mIrc.terminate();
        mOwner.terminate();
    }

	void writeChat(char[] nick, char[] s) {
	    mConsole.console.writefln("<%s> %s",nick,s);
	}

	void writeAction(char[] nick, char[] s) {
	    mConsole.console.writefln("%s %s",nick,s);
	}

	void writeNotice(char[] nick, char[] s) {
	    mConsole.console.writefln("-%s- %s",nick,s);
	}

	void writeInfo(char[] s) {
	    mConsole.console.writefln("* "~s);
	}

	void clearNicks() {
	    mConsole.console.writefln("~~~ clearNicks");
	}

	void addNick(char[] nick) {
	    mConsole.console.writefln("~~~ addNick: "~nick);
	}

	void removeNick(char[] nick) {
	    mConsole.console.writefln("~~~ removeNick: "~nick);
	}

	void changeNick(char[] oldNick, char[] newNick) {
	    mConsole.console.writefln("~~~ changeNick: "~oldNick~" -> "~newNick);
	}

    void cmdSay(MyBox[] args, Output write) {
        mIrc.say(mChannel, args[0].unbox!(char[]));
    }

    void cmdQuit(MyBox[] args, Output write) {
        char[] reason;
        if (args.length > 0)
            reason = args[0].unbox!(char[]);
        quit(reason);
    }

    void cmdServer(MyBox[] args, Output write) {
        mIrc.connect(args[0].unbox!(char[]));
    }

    void cmdJoin(MyBox[] args, Output write) {
        mChannel = args[0].unbox!(char[]);
        mIrc.join(mChannel);
    }

    void cmdPart(MyBox[] args, Output write) {
        char[] chan;
        if (args.length)
            chan = args[0].unbox!(char[]);
        writeInfo("Not supported");
    }

    void cmdMe(MyBox[] args, Output write) {
        mIrc.me(mChannel, args[0].unbox!(char[]));
    }

    void cmdMsg(MyBox[] args, Output write) {
        char[] tn = args[0].unbox!(char[]);
        char[] msg = args[1].unbox!(char[]);
	    mConsole.console.writefln("-> *%s* %s",tn,msg);
        mIrc.privmsg(tn,msg);
    }

    void cmdNick(MyBox[] args, Output write) {
        mIrc.nick = args[0].unbox!(char[]);
    }
}

class IRCTask: Task {
    this(TaskManager tm) {
        super(tm);

        gWindowManager.createWindow(this, new IRCFrame(this), "wIRC",
            Vector2i(600, 400));
    }

    static this() {
        TaskFactory.register!(typeof(this))("irc");
    }

    protected override void onKill() {
    }
}
