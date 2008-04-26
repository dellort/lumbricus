/*
	Copyright (C) 2005-2007 Christopher E. Miller

	This software is provided 'as-is', without any express or implied
	warranty.  In no event will the authors be held liable for any damages
	arising from the use of this software.

	Permission is granted to anyone to use this software for any purpose,
	including commercial applications, and to alter it and redistribute it
	freely, subject to the following restrictions:

	1. The origin of this software must not be misrepresented; you must not
	   claim that you wrote the original software. If you use this software
	   in a product, an acknowledgment in the product documentation would be
	   appreciated but is not required.
	2. Altered source versions must be plainly marked as such, and must not be
	   misrepresented as being the original software.
	3. This notice may not be removed or altered from any source distribution.
*/
module irclib.protocol;

//private
package
{
	version(Windows)
	{
		version(Tango)
		{
			import tango.sys.win32.UserGdi;
		}
		else
		{
			import std.c.windows.windows;
		}
	}


	version(Tango)
	{
		import tango.text.Util;

		int ilCharFindInString(char[] str, dchar dch)
		{
			auto loc = tango.text.Util.locate!(char)(str, dch);
			if(loc == str.length)
				return -1;
			return cast(int)loc;
		}

		alias tango.text.Util.delimit!(char) ilStringSplit;


		import tango.text.Ascii;

		alias tango.text.Ascii.icompare ilStringICmp;

		alias tango.text.Ascii.toUpper ilStringToUpper;


		import tango.text.convert.Utf;

		wchar* ilToUTF16z(char[] s)
		{
			wchar[] ws;
			ws = tango.text.convert.Utf.toString16(s);
			ws ~= '\0';
			return ws.ptr;
		}

		void ilValidateUtf8(char[] s)
		{
			tango.text.convert.Utf.toString16(s);
		}


		import tango.core.Exception;

		alias tango.core.Exception.UnicodeException ilUtfException;


		import tango.stdc.stdlib;

		alias tango.stdc.stdlib.alloca ilAlloca;


		dchar ilCharToLower(dchar ch)
		{
			if(ch >= 'A' && ch <= 'Z')
				return 'a' + (ch - 'A');
			return ch;
		}

		dchar ilCharToUpper(dchar ch)
		{
			if(ch >= 'a' && ch <= 'z')
				return 'A' + (ch - 'a');
			return ch;
		}


		import tango.text.convert.Integer;

		alias tango.text.convert.Integer.atoi ilStringToUint;

		ushort ilStringToUshort(char[] s)
		{
			return ilStringToUint(s);
		}


		//import tango.net.Socket;
	}
	else
	{
		import std.string;

		alias std.string.find ilCharFindInString;

		alias std.string.icmp ilStringICmp;

		alias std.string.split ilStringSplit;

		alias std.string.toupper ilStringToUpper;


		import std.utf;

		alias std.utf.toUTF16z ilToUTF16z;

		alias std.utf.validate ilValidateUtf8;

		alias std.utf.UtfException ilUtfException;


		import std.c.stdlib;

		alias std.c.stdlib.alloca ilAlloca;


		import std.ctype;

		alias std.ctype.tolower ilCharToLower;

		alias std.ctype.toupper ilCharToUpper;


		import std.conv;

		alias std.conv.toUint ilStringToUint;

		alias std.conv.toUshort ilStringToUshort;


		//import std.socket;
	}


	debug(IRC_TRACE)
	{
		version(Tango)
			import tango.stdc.stdio;
		else
			import std.c.stdio;
	}
}


/// Returns: the next param and updates params to exclude it.
char[] ircParam(inout char[] params)
{
	if(!params.length)
		return null;

	char[] result;
	uint i;

	if(params[0] == ':')
	{
		result = params[1 .. params.length];
		params = null;
		return result;
	}

	for(i = 0; i != params.length; i++)
	{
		if(params[i] == ' ')
		{
			// Found a parameter.
			result = params[0 .. i];
			params = params[i + 1 .. params.length];
			return result;
		}
	}

	// Fell through, last parameter.
	result = params;
	params = null;
	return result;
}


/// Returns: the next word and updates line to exclude it.
char[] nextWord(inout char[] line)
{
	if(!line.length)
		return null;

	char[] result;
	uint i;

	for(i = 0; i != line.length; i++)
	{
		if(line[i] == ' ')
		{
			// Found a word.
			result = line[0 .. i];
			line = line[i + 1 .. line.length];
			return result;
		}
	}

	// Fell through, last word.
	result = line;
	line = null;
	return result;
}


/// Returns: the name from a command prefix in one of the formats: "nick!user@host", "nick", "server.name"
char[] nickFromSource(char[] source)
{
	int i = ilCharFindInString(source, '!');
	if(i != -1)
		return source[0 .. i];
	return source;
}


/// Returns: "user@host" from the format "nick!user@host", or returns null.
char[] addressFromSource(char[] source)
{
	int i;
	i = ilCharFindInString(source, '!');
	if(i == -1)
		return null;
	return source[i + 1 .. source.length];
}


/// Returns: "host" from the format "nick!user@host" or "server.name", or returns null.
char[] siteFromSource(char[] source)
{
	bool dot = false;
	size_t iw;
	for(iw = 0; iw != source.length; iw++)
	{
		if(source[iw] == '@')
			return source[iw + 1 .. source.length];
		if(source[iw] == '.')
			dot = true;
	}
	if(dot)
		return source;
	return null;
}


/// Returns: "user" from the format "nick!user@host", or returns null.
char[] userNameFromSource(char[] source)
{
	int i;
	i = ilCharFindInString(source, '!');
	if(i != -1)
	{
		source = source[i + 1 .. source.length];
		i = ilCharFindInString(source, '@');
		if(i != -1)
			return source[0 .. i];
	}
	return null;
}


/// IRC protocol exception.
class IrcProtocolException: Exception
{
	///
	this(char[] msg)
	{
		super(msg);
	}
}


/// Queue incoming and outgoing data.
/// When implementing: Data to be written must be duplicated if stored. Data to be read must be owned by the reader.
interface IQueue
{
	void write(void[] data); ///
	void[] read(int nbytes); ///
	void[] read(); ///
	void[] peek(); ///

	/// Property: get number of bytes in the write queue.
	int writeBytes(); // getter

	/// Property: get number of bytes in the read queue.
	int readBytes(); // getter
}


/// Source of an IRC command.
class IrcFrom
{
	///
	this(char[] from)
	{
		_from = from;
		_nick = nickFromSource(from); // Save for speed.
	}


	/// Property: get the source/prefix.
	final char[] from() // getter
	{
		return _from;
	}


	/// Property: get
	/// See nickFromSource().
	final char[] fromNick() // getter
	{
		return _nick;
	}


	/// Property: get
	/// See addressFromSource().
	final char[] fromAddress() // getter
	{
		return addressFromSource(_from);
	}


	/// Property: get
	/// See siteFromSource().
	final char[] fromSite() // getter
	{
		return siteFromSource(_from);
	}


	/// Property: get
	/// See userNameFromSource().
	final char[] fromUserName() // getter
	{
		return userNameFromSource(_from);
	}


	private:
	char[] _from, _nick;
}


///
class ChannelTopic: IrcFrom
{
	///
	this(char[] prefix, char[] channelName, char[] topic)
	{
		_chan = channelName;
		_topic = topic;
		super(prefix);
	}


	/// Property: get
	final char[] channelName() // getter
	{
		return _chan;
	}


	/// Property: get
	final char[] topic() // getter
	{
		return _topic;
	}


	private:
	char[] _chan, _topic;
}


///
class IrcMode: IrcFrom
{
	///
	this(char[] prefix, char[] target, char[] modechars, char[] modeparams)
	{
		//IrcChannelMode(prefix, target, modechars, modeparams)
		_target = target;
		_modechars = modechars;
		_modeparams = modeparams;
		super(prefix);
	}


	/// Property: get
	final char[] target() // getter
	{
		return _target;
	}


	/// Property: get
	final char[] modeChars() // getter
	{
		return _modechars;
	}


	/// Property: get
	final char[] modeParams() // getter
	{
		return _modeparams;
	}


	private:
	char[] _target, _modechars, _modeparams;
}


class IrcUserMode: IrcMode
{
	this(char[] prefix, char[] target, char[] modechars, char[] modeparams)
	{
		super(prefix, target, modechars, modeparams);
	}
}


///
class IrcChannelMode: IrcMode
{
	///
	this(char[] prefix, char[] channelName, char[] modechars, char[] modeparams)
	{
		super(prefix, channelName, modechars, modeparams);
	}


	/// Property: get
	final char[] channelName() // getter
	{
		return target;
	}
}


///
class IrcMessage: IrcFrom
{
	///
	this(char[] from, char[] target, char[] message)
	{
		_target = target;
		_msg = message;
		super(from);
	}


	/// Property: get
	final char[] target() // getter
	{
		return _target;
	}


	/// Property: get
	final char[] message() // getter
	{
		return _msg;
	}


	private:
	char[] _target, _msg;
}


///
class IrcUserMessage: IrcMessage
{
	///
	this(char[] from, char[] target, char[] message)
	{
		super(from, target, message);
	}
}


///
class IrcChannelMessage: IrcMessage
{
	/// Params:
	/// 	target = actual channel _target, such as "@#D".
	/// 	channelName = the target without prefix symbols, such as "#D".
	this(char[] from, char[] target, char[] channelName, char[] message)
	{
		_chan = channelName;
		super(from, target, message);
	}


	/// Property: get
	final char[] channelName()
	{
		return _chan;
	}


	private:
	char[] _chan;
}


/// The message is the CTCP's arguments.
class CtcpMessage: IrcMessage
{
	///
	this(char[] from, char[] target, char[] ctcp, char[] message)
	{
		_ctcp = ctcp;
		super(from, target, message);
	}


	/// Property: get
	final char[] ctcp() // getter
	{
		return _ctcp;
	}


	private:
	char[] _ctcp;
}


///
class CtcpUserMessage: CtcpMessage
{
	///
	this(char[] from, char[] target, char[] ctcp, char[] message)
	{
		super(from, target, ctcp, message);
	}
}


///
class CtcpChannelMessage: CtcpMessage
{
	///
	this(char[] from, char[] target, char[] channelName, char[] ctcp, char[] message)
	{
		_chan = channelName;
		super(from, target, ctcp, message);
	}


	/// Property: get
	final char[] channelName()
	{
		return _chan;
	}


	private:
	char[] _chan;
}


///
class IrcQuit: IrcFrom
{
	///
	this(char[] from, char[] reason)
	{
		_reason = reason;
		super(from);
	}


	/// Property: get
	final char[] reason() // getter
	{
		return _reason;
	}


	private:
	char[] _reason;
}


/// from is the kicker.
class ChannelKick: IrcFrom
{
	///
	this(char[] from, char[] channelName, char[] kickedNick, char[] reason)
	{
		_chan = channelName;
		_kicked = kickedNick;
		_reason = reason;
		super(from);
	}


	/// Property: get
	final char[] channelName() // getter
	{
		return _chan;
	}


	/// Property: get
	final char[] kickedNick() // getter
	{
		return _kicked;
	}


	/// Property: get
	final char[] reason() // getter
	{
		return _reason;
	}


	private:
	char[] _chan, _kicked, _reason;
}


///
class ChannelJoin: IrcFrom
{
	///
	this(char[] from, char[] channelName)
	{
		_chan = channelName;
		super(from);
	}


	/// Property: get
	final char[] channelName() // getter
	{
		return _chan;
	}


	private:
	char[] _chan;
}


///
class ChannelPart: IrcFrom
{
	///
	this(char[] from, char[] channelName, char[] reason)
	{
		_chan = channelName;
		_reason = reason;
		super(from);
	}


	/// Property: get
	final char[] channelName() // getter
	{
		return _chan;
	}


	/// Property: get
	final char[] reason() // getter
	{
		return _reason;
	}


	private:
	char[] _chan, _reason;
}


///
class IrcNick: IrcFrom
{
	///
	this(char[] from, char[] newNick)
	{
		_nnick = newNick;
		super(from);
	}


	/// Property: get the user's new nickname.
	final char[] newNick() // getter
	{
		return _nnick;
	}


	private:
	char[] _nnick;
}


///
class ChannelTopicReply
{
	///
	this(char[] channelName, char[] topic)
	{
		_chan = channelName;
		_topic = topic;
	}


	/// Property: get
	final char[] channelName() // getter
	{
		return _chan;
	}


	/// Property: get
	final char[] topic() // getter
	{
		return _topic;
	}


	private:
	char[] _chan, _topic;
}


///
class ChannelTopicWhoTimeReply
{
	///
	this(char[] channelName, char[] setter, uint ctime)
	{
		_chan = channelName;
		_setter = setter;
		_ctime = ctime;
	}


	/// Property: get
	final char[] channelName() // getter
	{
		return _chan;
	}


	/// Property: get who set the topic, usually either just a nickname or a server name.
	final char[] setter() // getter
	{
		return _setter;
	}


	/// Property: get time corresponding to C's time().
	final uint ctime() // getter
	{
		return _ctime;
	}


	private:
	char[] _chan, _setter;
	uint _ctime;
}


/// IRC protocol that does not rely on any particular transport means.
/// The memory used in events may be part of a huge block, so it may be preferable to duplicate the memory if storing portions.
/// Usage: serverConnected must be called to log into the server. serverDisconnected must be called to finalize things. serverReadData must be called when data has been added to the queue.
class IrcProtocol
{
	///
	const char[] VERSION = "D irclib: www.dprogramming.com";


	///
	this(char[] nick = "MrFoo", char[] userName = "mrfoo", char[] fullName = VERSION)
	{
		_scmp = &strcmpRfc1459;

		_nick = nick;
		_userName = userName;
		_fullName = fullName;
	}


	/// Channel and user messages.
	protected void onMessageReceived(IrcMessage imsg)
	{
	}


	/// Message target is a user, probably me.
	protected void onUserMessageReceived(IrcUserMessage imsg)
	{
	}


	/// Message target is a channel, probably one I'm on.
	protected void onChannelMessageReceived(IrcChannelMessage imsg)
	{
	}


	///
	protected void onActionReceived(IrcMessage imsg)
	{
	}


	///
	protected void onUserActionReceived(IrcUserMessage imsg)
	{
	}


	///
	protected void onChannelActionReceived(IrcChannelMessage imsg)
	{
	}


	///
	protected void onMode(IrcMode imode)
	{
	}


	/// Mode target is probably me.
	protected void onUserMode(IrcUserMode iumode)
	{
	}


	/// Mode target is a channel, probably one I'm on.
	protected void onChannelMode(IrcChannelMode icmode)
	{
	}


	///
	protected void onTopicChanged(ChannelTopic ctopic)
	{
	}


	/// When issuing /TOPIC <chan>, this is the reply. Upon joining a channel, a topic is also often sent. Note that the "from" is usually only a nick or a server.
	protected void onTopicReply(ChannelTopicReply ctr)
	{
	}


	/// Usually called after onTopicReply() with more information.
	protected void onTopicWhoTimeReply(ChannelTopicWhoTimeReply ctwtr)
	{
	}


	///
	protected void onCtcpReceived(CtcpMessage cmsg)
	{
		if(!ilStringICmp(cmsg.ctcp, "VERSION"))
		{
			sendCtcpReply(cmsg.fromNick, "VERSION", VERSION);
		}
		else if(!ilStringICmp(cmsg.ctcp, "PING"))
		{
			char[] msg;
			msg = cmsg.message;
			if(msg.length > 32)
				msg = msg[0 .. 32];
			sendCtcpReply(cmsg.fromNick, "PING", msg);
		}
	}


	///
	protected void onUserCtcpReceived(CtcpUserMessage cmsg)
	{
	}


	///
	protected void onChannelCtcpReceived(CtcpChannelMessage cmsg)
	{
	}


	/// Channel and user notices.
	protected void onNoticeReceived(IrcMessage imsg)
	{
	}


	/// Notice target is a user, probably me.
	protected void onUserNoticeReceived(IrcUserMessage imsg)
	{
	}


	/// Notice target is a channel, probably one I'm on.
	protected void onChannelNoticeReceived(IrcChannelMessage imsg)
	{
	}


	///
	protected void onCtcpReplyReceived(CtcpMessage cmsg)
	{
	}


	///
	protected void onUserCtcpReplyReceived(CtcpUserMessage cmsg)
	{
	}


	/+
	///
	protected void onChannelCtcpReplyReceived(CtcpChannelMessage cmsg)
	{
	}
	+/


	/// A user has joined a channel.
	protected void onChannelJoin(ChannelJoin cjoin)
	{
	}


	/// A user has parted a channel.
	protected void onChannelPart(ChannelPart cpart)
	{
	}


	/// A user has quit IRC.
	protected void onQuit(IrcQuit iquit)
	{
	}


	/// A user has kicked another user out of a channel.
	protected void onChannelKick(ChannelKick ckick)
	{
	}


	/// A user has changed their nickname.
	protected void onNick(IrcNick inick)
	{
	}


	/// Property: set whether or not to send UTF-8 text instead of Latin-1.
	/// Sending Latin-1 is currently only supported on Windows. This property is now enabled by default.
	final void sendUtf8(bool byes) // setter
	{
		_sendUtf8 = byes;
	}


	/// Property: get whether or not to send UTF-8 text instead of Latin-1.
	final bool sendUtf8() // getter
	{
		version(Win32)
		{
			return _sendUtf8;
		}
		else
		{
			return true;
		}
	}


	/+
	private char[] firstline(char[] s)
	{
		size_t iw;
		for(iw = 0; iw != s.length; iw++)
		{
			if('\r' == s[iw] || '\n' == s[iw])
				return s[0 .. iw];
		}
		return s;
	}
	+/


	/// Send a line of text.
	/// The line is not to contain any newline characters; they are sent automatically.
	void sendLine(char[] line)
	in
	{
		foreach(char ch; line)
		{
			assert(ch != '\n' && ch != '\r'); // -line- cannot contain newline characters.
		}
	}
	body
	{
		if(!queue || !line.length)
			return;

		debug(IRC_TRACE)
			printf("[IrcProtocol.sendLine] %.*s\n", cast(uint)line.length, line.ptr);

		version(Win32)
		{
			if(_sendUtf8)
			{
				sutf8:
				queue.write(line);
				queue.write(\r\n);
			}
			else
			{
				// Only bother with conversion if there's a non-ASCII character.
				size_t iw;
				for(iw = 0; iw != line.length; iw++)
				{
					if(line[iw] >= 0x80)
						goto to_latin1;
				}
				// Fell through, no conversion needed.
				queue.write(line);
				queue.write(\r\n);
				return;

				to_latin1:
				wchar* wsz;
				size_t len;
				ubyte* buf;

				wsz = ilToUTF16z(line);
				len = WideCharToMultiByte(1252, 0, wsz, -1, null, 0, null, null);
				//assert(len > 0);
				if(len <= 0)
					goto sutf8; // Conversion failed, so just send the UTF-8.

				// Include the \r\n to avoid copies.
				if(len > 1024 - 2) // Shouldn't happen, IRC limit is less.
					buf = (new ubyte[len + 2]).ptr;
				else
					buf = cast(ubyte*)ilAlloca(1024);

				len = WideCharToMultiByte(1252, 0, wsz, -1, cast(char*)buf, len, null, null);
				assert(len > 0);

				// Now insert the \r\n.
				buf[++len] = '\r';
				buf[++len] = '\n';

				queue.write(buf[0 .. len]);
			}
		}
		else
		{
			queue.write(line);
			queue.write(\r\n);
		}
	}


	/// Property: get
	final bool isConnected() // getter
	{
		return _isConnected;
	}


	/// Property: get
	final bool isLoggedIn() // getter
	{
		return _isLoggedIn;
	}


	///
	protected void onConnected()
	{
	}


	///
	protected void onDisconnected()
	{
	}


	///
	protected void onLoggedIn()
	{
	}


	/// Property: get the queue.
	protected final IQueue queue() // getter
	{
		return _queue;
	}


	/// Property: get my nickname.
	final char[] nick() // getter
	{
		return _nick;
	}


	/// Property: set my nickname.
	/// If connected, this is delayed until the server replies.
	final void nick(char[] newNick) // setter
	{
		if(isConnected)
		{
			sendLine("NICK " ~ newNick);
		}
		else
		{
			_nick = newNick;
		}
	}


	/// Property: set my user name.
	final void userName(char[] user) // setter
	{
		_userName = user;
	}


	/// Property: get my user name.
	final char[] userName() // getter
	{
		return _userName;
	}


	/// Property: set my full name.
	final void fullName(char[] name) // setter
	{
		_fullName = name;
	}


	/// Property: get my full name.
	final char[] fullName() // getter
	{
		return _fullName;
	}


	/// Send a PRIVMSG command.
	final void sendMessage(char[] target, char[] message)
	{
		sendLine("PRIVMSG " ~ target ~ " :" ~ message);
	}


	/// Send a NOTICE command.
	final void sendNotice(char[] target, char[] message)
	{
		sendLine("NOTICE " ~ target ~ " :" ~ message);
	}


	///
	final void sendCtcp(char[] target, char[] ctcp, char[] ctcpParams)
	{
		if(!ctcpParams.length)
			sendMessage(target, "\1" ~ ctcp ~ "\1");
		else
			sendMessage(target, "\1" ~ ctcp ~ " " ~ ctcpParams ~ "\1");
	}


	///
	final void sendCtcpReply(char[] target, char[] ctcp, char[] ctcpParams)
	{
		if(!ctcpParams.length)
			sendNotice(target, "\1" ~ ctcp ~ "\1");
		else
			sendNotice(target, "\1" ~ ctcp ~ " " ~ ctcpParams ~ "\1");
	}


	/// Send an action, commonly known as "/ME".
	final void sendAction(char[] target, char[] message)
	{
		sendCtcp(target, "ACTION", message);
	}


	/// Change modes.
	final void sendMode(char[] target, char[] modes, char[][] modeparams ...)
	{
		char[] cmd;
		cmd = "MODE " ~ target ~ " " ~ modes;

		foreach(char[] s; modeparams)
		{
			cmd ~= " " ~ s;
		}

		sendLine(cmd);
	}


	/// Property: get _network name received from the server. null if not received.
	final char[] network() // getter
	{
		return _network;
	}


	/// Property: get user _prefixes for channel status. e.g. "(ov)@+"
	final char[] prefix() // getter
	{
		return _prefix;
	}


	/// Property: get user prefix symbols for channel status.
	/// Indices match up with prefixModes.
	final char[] prefixSymbols() // getter
	{
		return _prefixSymbols;
	}


	/// Property: get mode characters for user prefix symbols for channel status.
	/// Indices match up with prefixSymbols.
	final char[] prefixModes() // getter
	{
		return _prefixModes;
	}


	/// Property: get maximum number of entries allowed in WATCH list.
	/// Supports WATCH list if nonzero.
	final uint maximumWatch() // getter
	{
		return _maximumWatch;
	}


	/// Property: get maximum number of channels allowed to join at once.
	final uint maximumChannels() // getter
	{
		return _maximumChannels;
	}


	/// Property: get the type of channels. e.g. "#&"
	final char[] channelTypes() // getter
	{
		return _channelTypes;
	}


	/// Property: get maximum number of modes allowed in one MODE command.
	final uint maximumModes() // getter
	{
		return _maximumModes;
	}


	/// Property: get maximum number of entries allowed in SILENCE list.
	/// Supports SILENCE list if nonzero.
	final uint maximumSilence() // getter
	{
		return _maximumSilence;
	}


	/// Property: get how letter cases should be handled in nicks and channel names. e.g. "rfc1459" or "ascii"
	final char[] caseMapping() // getter
	{
		return _caseMapping;
	}


	/// Property: get
	final uint maximumNickLength() // getter
	{
		return _maximumNickLength;
	}


	/// Property: get
	final char[] channelModes() // getter
	{
		return _channelModes;
	}


	/// Compare strings case insensitively using ASCII.
	/// Returns: 0 on match, < 0 if less, or > 0 if greater.
	static int strcmpAscii(char[] s1, char[] s2)
	{
		return ilStringICmp(s1, s2);
	}


	/// Compare strings case insensitively using RFC 1459 rules.
	/// Returns: 0 on match, < 0 if less, or > 0 if greater.
	static int strcmpRfc1459(char[] s1, char[] s2)
	{
		size_t iw, len;
		len = s1.length;
		if(s1.length > s2.length)
			len = s2.length;

		for(iw = 0; iw != len; iw++)
		{
			if(s1[iw] != s2[iw])
			{
				char ch;
				ch = s1[iw];

				// {}|~ are the lowercase of []\^
				// Convert -ch- to the opposite case and compare with s2[iw].
				switch(ch)
				{
					case '{': ch = '['; break;
					case '}': ch = ']'; break;
					case '|': ch = '\\'; break;
					case '~': ch = '^'; break;
					case '[': ch = '{'; break;
					case ']': ch = '}'; break;
					case '\\': ch = '|'; break;
					case '^': ch = '~'; break;

					default:
						if(ch >= 'A' && ch <= 'Z')
						{
							ch = ilCharToLower(ch);
						}
						else if(ch >= 'a' && ch <= 'z')
						{
							ch = ilCharToUpper(ch);
						}
						else // There is no opposite case, no match.
						{
							return s1[iw] - s2[iw];
						}
				}

				if(ch != s2[iw])
					return s1[iw] - s2[iw];
			}
		}
		if(s1.length != s2.length)
			return s1.length - s2.length;
		return 0; // Fell through, all equal.
	}


	/// Uses the current server's case mapping to compare case insensitive strings.
	/// Returns: 0 on match, < 0 if less, or > 0 if greater.
	int strcmp(char[] s1, char[] s2)
	in
	{
		assert(!(_scmp is null));
	}
	body
	{
		return _scmp(s1, s2);
	}


	private void fillPrefix()
	{
		char[] clientPrefix;
		int i;

		clientPrefix = _prefix;
		if(!clientPrefix.length)
			goto empty_prefix;
		if(clientPrefix[0] != '(')
			goto empty_prefix;
		clientPrefix = clientPrefix[1 .. clientPrefix.length];
		i = ilCharFindInString(clientPrefix, ')');
		if(i == -1)
			goto empty_prefix;
		_prefixModes = clientPrefix[0 .. i];
		_prefixSymbols = clientPrefix[i + 1 .. clientPrefix.length];
		if(_prefixModes.length != _prefixSymbols.length)
			goto empty_prefix;
		return; // Successful.

		empty_prefix:
		_prefix = null;
		_prefixModes = null;
		_prefixSymbols = null;
	}


	private void process005(char[] cmdParams)
	{
		char[][] each;

		each = ilStringSplit(cmdParams, " ");
		foreach(char[] foo; each)
		{
			if(foo.length)
			{
				if(foo[0] == ':')
					break;

				char[] entry, equ;
				int i;
				i = ilCharFindInString(foo, '=');
				if(i == -1)
				{
					entry = foo;
					//equ = null;
				}
				else
				{
					entry = foo[0 .. i];
					equ = foo[i + 1 .. foo.length];
				}

				switch(ilStringToUpper(entry))
				{
					case "SILENCE":
						try
						{
							_maximumSilence = ilStringToUint(equ);
						}
						catch
						{
						}
						break;

					case "MAXCHANNELS":
						try
						{
							_maximumChannels = ilStringToUint(equ);
						}
						catch
						{
						}
						break;

					case "MODES":
						try
						{
							_maximumModes = ilStringToUint(equ);
						}
						catch
						{
						}
						break;

					case "NETWORK":
						_network = equ.dup;
						break;

					case "PREFIX":
						_prefix = equ.dup;
						fillPrefix();
						break;

					case "CHANTYPES":
						_channelTypes = equ.dup;
						break;

					case "CASEMAPPING":
						_caseMapping = equ.dup;

						if(!ilStringICmp(_caseMapping, "ascii"))
							_scmp = &strcmpAscii;
						else // Assume rfc1459.
							_scmp = &strcmpRfc1459;
						break;

					case "WATCH":
						try
						{
							_maximumWatch = ilStringToUint(equ);
						}
						catch
						{
						}
						break;

					case "NICKLEN":
						try
						{
							_maximumNickLength = ilStringToUint(equ);
						}
						catch
						{
						}
						break;

					case "CHANMODES":
						_channelModes = equ.dup;
						break;

					default: ;
				}
			}
		}
	}


	/// Returns: channel name, or null if not a channel. e.g. returns "#D" from "@+#D"
	final char[] channelNameFromTarget(char[] target)
	{
		// _channelTypes

		size_t iw = 0;

		// Skip prefix symbols.
		for(;; iw++)
		{
			if(iw == target.length)
				return null;

			if(ilCharFindInString(_prefixSymbols, target[iw]) == -1)
				break;
		}

		// Make sure char after optional prefix symbols is a channel type.
		assert(iw < target.length);
		if(ilCharFindInString(_channelTypes, target[iw]) == -1)
			return null;

		// All set.
		return target[iw .. target.length];
	}


	/// Determines if the string is a channel name.
	/// Note: channel mode prefixes are not considered, use channelNameFromTarget in that case.
	final bool isChannelName(char[] s)
	{
		return s.length && ilCharFindInString(_channelTypes, s[0]) != -1;
	}


	/// Returns: the CTCP name and updates message; or null if not CTCP.
	private char[] getCtcp(inout char[] message)
	{
		if(message.length && message[0] == '\1')
		{
			int i;
			char[] s;
			s = message[1 .. message.length];

			i = ilCharFindInString(s, '\1');
			if(i != -1)
			{
				char[] result;

				s = s[0 .. i];
				i = ilCharFindInString(s, ' ');
				if(i == -1)
				{
					result = s;
					s = null;
				}
				else
				{
					result = s[0 .. i];
					s = s[i + 1 .. s.length];
				}

				if(result.length)
				{
					message = s;
					return result;
				}
			}
		}
		return null;
	}


	private enum _MsgType
	{
		PRIVMSG,
		NOTICE,
	}


	private template processMsg(_MsgType TYPE)
	{
		private void processMsg(IrcProtocol proto, char[] cmdPrefix, char[] cmdParams)
		{
			with(proto)
			{
				char[] target, message, chan, ctcp;
				target = ircParam(cmdParams);
				message = ircParam(cmdParams);
				chan = channelNameFromTarget(target);
				ctcp = getCtcp(message);

				if(chan.length)
				{
					// Check if PRIVMSG here because a CTCP reply cannot be sent to a channel.
					if(TYPE == _MsgType.PRIVMSG && ctcp.length)
					{
						if(!ilStringICmp("ACTION", ctcp))
						{
							auto IrcChannelMessage imsg = new IrcChannelMessage(cmdPrefix, target, chan, message);
							onActionReceived(imsg);
							onChannelActionReceived(imsg);
						}
						else
						{
							ctcp = ctcp;

							auto CtcpChannelMessage imsg = new CtcpChannelMessage(cmdPrefix, target, chan, ctcp, message);
							if(TYPE == _MsgType.PRIVMSG)
							{
								onCtcpReceived(imsg);
								onChannelCtcpReceived(imsg);
							}
						}
					}
					else
					{
						auto IrcChannelMessage imsg = new IrcChannelMessage(cmdPrefix, target, chan, message);
						if(TYPE == _MsgType.PRIVMSG)
						{
							onMessageReceived(imsg);
							onChannelMessageReceived(imsg);
						}
						else if(TYPE == _MsgType.NOTICE)
						{
							onNoticeReceived(imsg);
							onChannelNoticeReceived(imsg);
						}
					}
				}
				else
				{
					if(ctcp.length)
					{
						if(TYPE == _MsgType.PRIVMSG && !ilStringICmp("ACTION", ctcp))
						{
							auto IrcUserMessage imsg = new IrcUserMessage(cmdPrefix, target, message);
							onActionReceived(imsg);
							onUserActionReceived(imsg);
						}
						else
						{
							ctcp = ctcp;

							auto CtcpUserMessage imsg = new CtcpUserMessage(cmdPrefix, target, ctcp, message);
							if(TYPE == _MsgType.PRIVMSG)
							{
								onCtcpReceived(imsg);
								onUserCtcpReceived(imsg);
							}
							else if(TYPE == _MsgType.NOTICE)
							{
								onCtcpReplyReceived(imsg);
								onUserCtcpReplyReceived(imsg);
							}
						}
					}
					else
					{
						auto IrcUserMessage imsg = new IrcUserMessage(cmdPrefix, target, message);
						if(TYPE == _MsgType.PRIVMSG)
						{
							onMessageReceived(imsg);
							onUserMessageReceived(imsg);
						}
						else if(TYPE == _MsgType.NOTICE)
						{
							onNoticeReceived(imsg);
							onUserNoticeReceived(imsg);
						}
					}
				}
			}
		}
	}


	private void processJoin(char[] prefix, char[] cmdParams)
	{
		char[] chan;
		chan = ircParam(cmdParams);

		auto ChannelJoin cjoin = new ChannelJoin(prefix, chan);
		onChannelJoin(cjoin);
	}


	private void processPart(char[] prefix, char[] cmdParams)
	{
		char[] chan, reason;
		chan = ircParam(cmdParams);
		reason = ircParam(cmdParams);

		auto ChannelPart cpart = new ChannelPart(prefix, chan, reason);
		onChannelPart(cpart);
	}


	private void processQuit(char[] prefix, char[] cmdParams)
	{
		char[] reason;
		reason = ircParam(cmdParams);

		auto IrcQuit iquit = new IrcQuit(prefix, reason);
		onQuit(iquit);
	}


	private void processKick(char[] prefix, char[] cmdParams)
	{
		char[] chan, kicked, reason;
		chan = ircParam(cmdParams);
		kicked = ircParam(cmdParams);
		reason = ircParam(cmdParams);

		auto ChannelKick ckick = new ChannelKick(prefix, chan, kicked, reason);
		onChannelKick(ckick);
	}


	private void processMode(char[] prefix, char[] cmdParams)
	{
		char[] target, modechars, modeparams;
		target = ircParam(cmdParams);
		modechars = ircParam(cmdParams);
		modeparams = cmdParams;

		if(isChannelName(target))
		{
			auto IrcChannelMode icmode = new IrcChannelMode(prefix, target, modechars, modeparams);
			onMode(icmode);
			onChannelMode(icmode);
		}
		else
		{
			auto IrcUserMode iumode = new IrcUserMode(prefix, target, modechars, modeparams);
			onMode(iumode);
			onUserMode(iumode);
		}
	}


	private void processTopic(char[] prefix, char[] cmdParams)
	{
		char[] chan, topic;
		chan = ircParam(cmdParams);
		topic = ircParam(cmdParams);

		auto ChannelTopic ctopic = new ChannelTopic(prefix, chan, topic);
		onTopicChanged(ctopic);
	}


	private void processNick(char[] prefix, char[] cmdParams)
	{
		char[] nnick;
		nnick = ircParam(cmdParams);

		try
		{
			auto IrcNick inick = new IrcNick(prefix, nnick);
			onNick(inick);
		}
		finally
		{
			if(nickFromSource(prefix) == _nick)
				_nick = nnick.dup;
		}
	}


	private void processRplTopic(char[] prefix, char[] cmdParams)
	{
		char[] chan, topic;
		ircParam(cmdParams); // Skip my nick;
		chan = ircParam(cmdParams);
		topic = ircParam(cmdParams);

		ChannelTopicReply ctr = new ChannelTopicReply(chan, topic);
		onTopicReply(ctr);
	}


	private void processRplTopicWhoTime(char[] prefix, char[] cmdParams)
	{
		char[] chan, setter, sctime;
		ircParam(cmdParams); // Skip my nick;
		chan = ircParam(cmdParams);
		setter = ircParam(cmdParams);
		sctime = ircParam(cmdParams);

		uint ctime;
		try
		{
			ctime = ilStringToUint(sctime);
		}
		catch
		{
		}

		auto ChannelTopicWhoTimeReply ctwtr = new ChannelTopicWhoTimeReply(chan, setter, ctime);
		onTopicWhoTimeReply(ctwtr);
	}


	private void processWelcome(char[] prefix, char[] cmdParams)
	{
		// This is the first response when the server accepts my USER/NICK.
		// It contains my current nickname, so store it.

		char[] nnick;
		nnick = ircParam(cmdParams);
		if(nnick.length)
			_nick = nnick.dup;
	}


	/// Process a command from the server.
	protected void onCommand(char[] prefix, char[] cmd, char[] cmdParams)
	{
		switch(cmd)
		{
			case "PRIVMSG":
				processMsg!(_MsgType.PRIVMSG)(this, prefix, cmdParams);
				break;

			case "NOTICE":
				processMsg!(_MsgType.NOTICE)(this, prefix, cmdParams);
				break;

			case "JOIN":
				processJoin(prefix, cmdParams);
				break;

			case "PART":
				processPart(prefix, cmdParams);
				break;

			case "QUIT":
				processQuit(prefix, cmdParams);
				break;

			case "KICK":
				processKick(prefix, cmdParams);
				break;

			case "NICK":
				processNick(prefix, cmdParams);
				break;

			case "MODE":
				processMode(prefix, cmdParams);
				break;

			case "TOPIC":
				processTopic(prefix, cmdParams);
				break;

			case "332": // RPL_TOPIC
				processRplTopic(prefix, cmdParams);
				break;

			case "333": // RPL_TOPICWHOTIME
				processRplTopicWhoTime(prefix, cmdParams);
				break;

			case "001": // RPL_WELCOME
				processWelcome(prefix, cmdParams);
				break;

			case "005": // RPL_PROTOCTL
				process005(cmdParams);
				break;

			case "376": // RPL_ENDOFMOTD
				if(!_isLoggedIn)
				{
					_isLoggedIn = true;
					onLoggedIn();
				}
				break;

			case "422": // ERR_NOMOTD
				if(!_isLoggedIn)
				{
					_isLoggedIn = true;
					onLoggedIn();
				}
				break;

			case "PING":
				sendLine("PONG :" ~ ircParam(cmdParams));
				break;

			default: ;
		}
	}


	/// A line of text received from the server. Must not contain newline characters.
	protected void onLine(char[] line)
	{
		debug(IRC_TRACE)
			printf("[IrcProtocol.onLine] %.*s\n", cast(uint)line.length, line.ptr);

		char[] prefix;
		char[] cmd;

		cmd = nextWord(line);
		if(!cmd.length)
			return;
		if(cmd[0] == ':')
		{
			if(cmd.length == 1)
				return;
			prefix = cmd[1 .. cmd.length];
			cmd = nextWord(line);
			if(!cmd.length)
				return;
		}

		onCommand(prefix, ilStringToUpper(cmd), line);
	}


	private static char[] _latin1toUtf8(ubyte[] data)
	{
		size_t rlen = 0;
		foreach(ub; data)
		{
			if(ub >= 0x80)
				rlen += 2;
			else
				rlen++;
		}
		if(rlen == data.length)
			return cast(char[])data; // It's just ASCII.

		char[] result;
		result = new char[rlen + 1];
		rlen = 0;
		foreach(ub; data)
		{
			if(ub >= 0x80)
			{
				result[rlen++] = cast(char)((ub >> 6) | 0xC0);
				result[rlen++] = cast(char)((ub & 0x3F) | 0x80);
			}
			else
			{
				result[rlen++] = cast(char)ub;
			}
		}
		result[rlen] = 0;
		return result[0 .. rlen];
	}


	private void _gotLine(ubyte[] data)
	{
		if(!data.length)
			return;

		size_t iw;
		for(iw = 0; iw != data.length; iw++)
		{
			if(data[iw] >= 0x80)
				goto not_ascii;
		}
		// Fell through, all ASCII.
		onLine(cast(char[])data);
		return;

		not_ascii:
		char[] str;
		try
		{
			ilValidateUtf8(cast(char[])data[iw .. data.length]);
			str = cast(char[])data;
		}
		catch(ilUtfException e)
		{
			str = _latin1toUtf8(data);
		}
		onLine(str);
	}


	/// Call when new data has been added to the queue. The queue does not need to contain newline characters.
	protected final void serverReadData()
	in
	{
		assert(_isConnected); // Call serverConnected() first.
		assert(!(_queue is null));
	}
	body
	{
		int i;
		ubyte[] data;

		again:
		data = cast(ubyte[])queue.peek();
		if(!data.length)
			return;
		for(i = 0; i != data.length; i++)
		{
			switch(data[i])
			{
				case '\r':
					i++;
					if(i == data.length)
					{
						queue.read();
						data = data[0 .. i - 1];
						if(data.length)
							_gotLine(data);
						return;
					}
					else
					{
						if(data[i] == '\n')
						{
							i++;
							queue.read(i);
							data = data[0 .. i - 2];
							if(data.length)
								_gotLine(data);
						}
						else
						{
							queue.read(i);
							data = data[0 .. i - 1];
							if(data.length)
								_gotLine(data);
						}
					}
					goto again;

				case '\n':
					i++;
					queue.read(i);
					data = data[0 .. i - 1];
					if(data.length)
						_gotLine(data);
					goto again;

				default:
					break;
			}
		}
	}


	/// Send USER and NICK commands.
	/// Params:
	/// 	serverHost = the server host name for the 3rd parameter of USER.
	protected void sendLoginInfo(char[] serverHost)
	{
		sendLine("USER " ~ _userName ~ " \"\" \"" ~ serverHost ~ "\" :" ~ _fullName);
		sendLine("NICK " ~ _nick);
	}


	/// Call when a connection to the server has been made.
	/// Params:
	/// 	queue = the data queue for this connection.
	/// 	serverHost = the name of the server host.
	protected void serverConnected(IQueue queue, char[] serverHost)
	in
	{
		assert(!_isConnected); // Make sure a connection is not already established.
		assert(_queue is null);
		assert(!(queue is null)); // New queue cannot be null.
	}
	body
	{
		// Reset network-specific stuff.
		_network = _network_INIT;
		_prefix = _prefix_INIT;
		_prefixSymbols = _prefixSymbols_INIT;
		_prefixModes = _prefixModes_INIT;
		_maximumWatch = _maximumWatch_INIT;
		_maximumChannels = _maximumChannels_INIT;
		_channelTypes = _channelTypes_INIT;
		_maximumModes = _maximumModes_INIT;
		_maximumSilence = _maximumSilence_INIT;
		_caseMapping = _caseMapping_INIT;
		//_scmp = _scmp_INIT;
		_scmp = &strcmpRfc1459;
		_maximumNickLength = _maximumNickLength_INIT;
		_channelModes = _channelModes_INIT;

		_isConnected = true;
		_queue = queue;

		onConnected();
		sendLoginInfo(serverHost);
	}


	/// Call when the connection to the server has been severed; either by the local or remote side.
	protected void serverDisconnected()
	{
		_isConnected = false;
		_isLoggedIn = false;
		_queue = null;

		onDisconnected();
	}


	private:
	char[] _nick;
	char[] _userName;
	char[] _fullName;
	IQueue _queue;
	bool _isConnected = false;
	bool _isLoggedIn = false;
	bool _sendUtf8 = true; //false;

	const char[] _network_INIT = "";
	char[] _network = _network_INIT;
	const char[] _prefix_INIT = "(ov)@+";
	char[] _prefix = _prefix_INIT;
	const char[] _prefixSymbols_INIT = "@+";
	char[] _prefixSymbols = _prefixSymbols_INIT;
	const char[] _prefixModes_INIT = "ov";
	char[] _prefixModes = _prefixModes_INIT;
	const uint _maximumWatch_INIT = 0;
	uint _maximumWatch = _maximumWatch_INIT;
	const uint _maximumChannels_INIT = 10;
	uint _maximumChannels = _maximumChannels_INIT;
	const char[] _channelTypes_INIT = "#&";
	char[] _channelTypes = _channelTypes_INIT;
	const uint _maximumModes_INIT = 3;
	uint _maximumModes = _maximumModes_INIT;
	const uint _maximumSilence_INIT = 0;
	uint _maximumSilence = _maximumSilence_INIT;
	const char[] _caseMapping_INIT = "rfc1459";
	char[] _caseMapping = _caseMapping_INIT;
	//const int function(char[], char[]) _scmp_INIT; // = &strcmpRfc1459;
	int function(char[], char[]) _scmp; // = _scmp_INIT;
	const uint _maximumNickLength_INIT = 9;
	uint _maximumNickLength = _maximumNickLength_INIT;
	const char[] _channelModes_INIT = "bIe,k,l";
	char[] _channelModes = _channelModes_INIT;
}

