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
module irclib.client;


package
{
	import irclib.protocol;
	
	
	version(Tango)
	{
		import tango.math.Random;
		
		uint ilRand()
		{
			return tango.math.Random.Random.shared.next();
		}
		
		
		import tango.text.convert.Integer;
		
		char[] ilSizetToString(size_t num)
		{
			char[16] buf;
			return tango.text.convert.Integer.format!(char, size_t)(buf, num).dup;
		}
		
		
		import tango.net.Socket;
		
		alias tango.net.Socket.NetHost ilInternetHost;
		
		alias tango.net.Socket.IPv4Address ilInternetAddress;
	}
	else
	{
		import std.random;
		
		alias std.random.rand ilRand;
		
		
		import std.string;
		
		alias std.string.toString ilSizetToString;
		
		
		import std.socket;
		
		alias std.socket.InternetHost ilInternetHost;
		
		alias std.socket.InternetAddress ilInternetAddress;
	}
}


///
class IrcClientException: IrcProtocolException
{
	///
	this(char[] msg)
	{
		super(msg);
	}
}


///
class IrcClient: IrcProtocol
{
	///
	const ushort DEFAULT_PORT = 6667;
	
	
	///
	this(char[] serverHost, ushort serverPort)
	{
		_serverHost = serverHost;
		_serverPort = serverPort;
	}
	
	
	/// "server.host" or "server.host:port"
	this(char[] serverHostAndPort)
	{
		int i;
		i = ilCharFindInString(serverHostAndPort, ':');
		if(i == -1)
		{
			_serverHost = serverHostAndPort;
			//_serverPort = DefaultPort;
		}
		else
		{
			_serverHost = serverHostAndPort[0 .. i];
			_serverPort = ilStringToUshort(serverHostAndPort[i + 1 .. serverHostAndPort.length]);
		}
	}
	
	
	///
	this()
	{
	}
	
	
	/// Property: set
	final void serverHost(char[] host) // setter
	{
		_serverHost = host;
	}
	
	
	/// Property: get
	final char[] serverHost() // getter
	{
		return _serverHost;
	}
	
	
	/// Property: set
	final void serverPort(ushort port) // setter
	{
		_serverPort = port;
	}
	
	
	/// Property: get
	final ushort serverPort() // getter
	{
		return _serverPort;
	}
	
	
	
	/// This function should begin resolving host and call finishHostResolve() when completed successfully.
	/// This implementation calls InternetHost.getHostByName(). Override to change behavior.
	protected void prepareHostResolve(char[] host)
	{
		scope ilInternetHost ih = new ilInternetHost;
		if(ih.getHostByName(host))
		{
			finishHostResolve(ih);
			return;
		}
		throw new IrcClientException("Unable to resolve host " ~ host ~ ".");
	}
	
	
	
	/// Calls connect() with a random address from the InternetHost and the serverPort. Override to change behavior.
	protected void finishHostResolve(ilInternetHost ih)
	in
	{
		assert(ih.addrList.length);
	}
	body
	{
		uint ipaddr;
		
		ipaddr = ih.addrList[ilRand() % ih.addrList.length];
		connect(new ilInternetAddress(ipaddr, _serverPort));
	}
	
	
	/// This function should begin connecting the socket to the specified address and call finishConnection() when connected successfully.
	/// This implementation calls Socket.connect(). Override to change behavior.
	/// The socket property should be used to get the socket to connect on.
	protected void prepareConnection(ilInternetAddress ia)
	{
		sock.connect(ia);
		finishConnection();
	}
	
	
	/// The connection is established and now it's time to communicate with the server.
	/// The socket *must not* be blocking by the time the IQueue is created.
	/// This function should call IrcProtocol.serverConnected() with a new IQueue and call waitForEvent() to wait for socket events.
	protected void finishConnection()
	{
		sock.blocking = false;
		serverConnected(_cqueue = new ClientQueue(sock), _serverHost);
		waitForEvent();
	}
	
	
	/// This function should wait for socket events, manipulate the queue, and call the appropriate server events of IrcProtocol.
	/// The IrcProtocol.queue property can be used to get the queue.
	/// This implementation calls Socket.select().  Override to change behavior.
	/// The socket property should be used to get the socket.
	protected void waitForEvent()
	{
		SocketSet ssread, sswrite;
		ssread = new SocketSet;
		sswrite = new SocketSet;
		
		const uint NUM_BYTES = 1024;
		ubyte[NUM_BYTES] _data = void;
		void* data = _data.ptr;
		
		for(;; ssread.reset(), sswrite.reset())
		{
			ssread.add(sock);
			if(_cqueue.writeBytes)
				sswrite.add(sock);
			
			int sl;
			sl = Socket.select(ssread, sswrite, null);
			if(-1 == sl) // Interrupted.
				continue;
			
			if(ssread.isSet(sock))
			{
				int sv;
				sv = sock.receive(data[0 .. NUM_BYTES]);
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
						_cqueue.onDataReceived(data[0 .. sv]);
						serverReadData(); // Tell the IrcProtocol about the new data.
				}
			}
			
			if(sswrite.isSet(sock))
			{
				_cqueue.onSendComplete();
			}
		}
	}
	
	
	///
	protected void onConnectionError()
	{
	}
	
	
	version(Tango)
		private const bool _IS_TANGO = true;
	else
		private const bool _IS_TANGO = false;
	
	static if(_IS_TANGO && is(typeof(&Socket.detach)))
	{
		final void socketClose()
		{
			sock.detach();
		}
	}
	else
	{
		final void socketClose()
		{
			sock.close();
		}
	}
	
	
	///
	protected override void serverDisconnected()
	{
		if(sock)
		{
			//sock.close();
			socketClose();
			sock = null;
		}
		
		_cqueue = null;
		
		super.serverDisconnected();
	}
	
	
	///
	final void connect()
	{
		uint ipaddr;
		ipaddr = ilInternetAddress.parse(_serverHost);
		if(ilInternetAddress.ADDR_NONE != ipaddr)
		{
			connect(new ilInternetAddress(ipaddr, _serverPort));
		}
		else
		{
			// Invalid IP address, attempt to resolve as a name.
			prepareHostResolve(_serverHost);
		}
	}
	
	
	/// Override to use different socket types.
	protected Socket createSocket()
	{
		//return new TcpSocket();
		return new Socket(cast(AddressFamily)AddressFamily.INET, SocketType.STREAM, ProtocolType.TCP);
	}
	
	
	/// Does not bother resolving serverHost and connects to remoteAddress.
	/// Params:
	/// 	remoteAddress = should be an IP address of serverHost.
	final void connect(ilInternetAddress remoteAddress)
	{
		sock = createSocket();
		prepareConnection(remoteAddress);
	}
	
	
	/// Property: get
	protected final Socket socket() // getter
	{
		return sock;
	}
	
	
	/// Property: get
	protected final ClientQueue clientQueue() // getter
	{
		return _cqueue;
	}
	
	
	private:
	Socket sock;
	ClientQueue _cqueue;
	char[] _serverHost;
	ushort _serverPort = DEFAULT_PORT;
}


/// The socket *must not* be blocking.
class ClientQueue: IQueue
{
	///
	this(Socket sock)
	{
		this.sock = sock;
	}
	
	
	///
	void onSendComplete()
	{
		if(writebuf.length)
		{
			void[] tempwritebuf;
			tempwritebuf = writebuf;
			writebuf = null; // In case of exception.
			int sv;
			sv = _writeNow(tempwritebuf);
			if(sv < tempwritebuf.length)
				writebuf = tempwritebuf[sv .. tempwritebuf.length];
		}
	}
	
	
	///
	void onDataReceived(void[] data)
	{
		readbuf ~= data;
	}
	
	
	// Returns the number of bytes written.
	private int _writeNow(void[] data)
	{
		void[] buf;
		if(data.length > 4096)
			buf = data[0 .. 4096];
		else
			buf = data;
		
		int sv;
		sv = sock.send(buf);
		if(Socket.ERROR == sv)
			throw new IrcClientException("Unable to send " ~ ilSizetToString(buf.length) ~ " bytes.");
		return sv;
	}
	
	
	///
	void write(void[] data)
	{
		// If buf.length == 0, go ahead and send, otherwise
		// I'm waiting for onSendComplete().
		
		if(!writebuf.length)
		{
			int sv;
			sv = _writeNow(data);
			if(sv == data.length)
			{
				//writebuf = null; // It's already null.
			}
			else
			{
				assert(sv < data.length);
				// Dup to allow append and saved reference.
				writebuf = data[sv .. writebuf.length].dup;
			}
		}
		else
		{
			writebuf ~= data;
		}
	}
	
	
	///
	void[] read(int nbytes)
	{
		void[] result;
		result = readbuf[0 .. nbytes];
		readbuf = readbuf[nbytes .. readbuf.length];
		return result;
	}
	
	
	///
	void[] read()
	{
		void[] result;
		result = readbuf;
		readbuf = null;
		return result;
	}
	
	
	///
	void[] peek()
	{
		return readbuf;
	}
	
	
	/// Property: get the number of bytes in the write queue.
	int writeBytes() // getter
	{
		return writebuf.length;
	}
	
	
	// Property: get the number of bytes in the read queue.
	int readBytes() // getter
	{
		return readbuf.length;
	}
	
	
	/// Property: get
	final Socket socket() // getter
	{
		return sock;
	}
	
	
	private:
	Socket sock;
	void[] writebuf, readbuf;
}

