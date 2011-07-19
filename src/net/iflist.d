module net.iflist;

//This file contains highly platform dependant, hacky code to get the
//broadcast addresses of all network interfaces in the system

import tango.net.device.Socket;
import tango.net.device.Berkeley;
import tango.sys.Common;

alias IPv4Address.sockaddr_in sockaddr_in;

version (Win32) {
    private import tango.sys.win32.WsaSock : WSAIoctl;

    uint _IOR(T)(ubyte x, ubyte y) {
        return IOC_OUT | ((cast(uint)(T.sizeof)&IOCPARM_MASK)<<16) | (x<<8) | y;
    }
    enum IOC_OUT = 0x40000000;
    enum IOCPARM_MASK = 0x7f;
    enum SIO_GET_INTERFACE_LIST = _IOR!(uint)('t', 127);

    union sockaddr_gen {
        ubyte[16]  Address;
        sockaddr_in  AddressIn;
        ubyte[24] AddressIn6;  //we don't need this
    }

    struct INTERFACE_INFO {
        uint          iiFlags;            /* Interface flags */
        sockaddr_gen  iiAddress;          /* Interface address */
        sockaddr_gen  iiBroadcastAddress; /* Broadcast address */
        sockaddr_gen  iiNetmask;          /* Network mask */
    }
    alias INTERFACE_INFO* LPINTERFACE_INFO;

    enum {
        IFF_UP           = 0x00000001, /* Interface is up */
        IFF_BROADCAST    = 0x00000002, /* Broadcast is  supported */
        IFF_LOOPBACK     = 0x00000004, /* this is loopback interface */
        IFF_POINTTOPOINT = 0x00000008, /* this is point-to-point interface */
        IFF_MULTICAST    = 0x00000010, /* multicast is supported */
    }



    //Returns: an array of available broadcast addresses for the system's net
    //  interfaces, e.g. 192.168.0.255
    public string[] getBroadcastInterfaces() {
        //Note: tango.net.device.Berkeley does the WSAStartup() call
        //WSAIoctl needs a socket handle
        Berkeley bs;
        bs.open(AddressFamily.INET, SocketType.STREAM, ProtocolType.TCP);
        scope(exit) bs.detach();
        assert (bs.handle != -1);
        INTERFACE_INFO[20] interfaceList;

        uint nBytes;
        //request interface list
        if (WSAIoctl(cast(HANDLE)bs.handle, SIO_GET_INTERFACE_LIST, null, 0,
            interfaceList.ptr, 20*INTERFACE_INFO.sizeof, &nBytes, null,
            null) == SOCKET_ERROR)
        {
            //error, use global broadcast address
            return ["255.255.255.255"];
        }

        string[] res;
        scope addr = new IPv4Address(12345);
        int nNumInterfaces = nBytes / INTERFACE_INFO.sizeof;
        for (int i = 0; i < nNumInterfaces; i++) {
            uint flags = interfaceList[i].iiFlags;
            if ((flags & IFF_UP) && (flags & IFF_BROADCAST)
                && !(flags & IFF_LOOPBACK))
            {
                //broadcast address is the interface address, but set to 255
                //  where the netmask is 0
                sockaddr_in ia = interfaceList[i].iiAddress.AddressIn;
                sockaddr_in mask = interfaceList[i].iiNetmask.AddressIn;
                ia.sin_addr = ia.sin_addr | (~mask.sin_addr);

                //nice work tango guys...(could use inet_ntoa, but it's private)
                *cast(sockaddr_in*)addr.name = ia;
                res ~= addr.toAddrString();
            }
        }

        return res;
    }
}

version (linux) {
    private:

    import tango.stdc.posix.sys.socket : AF_INET, sockaddr;

    extern(C) {
        int getifaddrs(ifaddrs** ifap);
        void freeifaddrs(ifaddrs* ifa);
    }

    struct ifaddrs {
        ifaddrs* ifa_next;      /* Next item in list */
        char* ifa_name;         /* Name of interface */
        uint ifa_flags;         /* Flags from SIOCGIFFLAGS */
        sockaddr* ifa_addr;     /* Address of interface */
        sockaddr* ifa_netmask;  /* Netmask of interface */
        union {
            sockaddr* ifa_broadaddr;
                                /* Broadcast address of interface */
            sockaddr* ifa_dstaddr;
                                /* Point-to-point destination address */
        }
        void* ifa_data;         /* Address-specific data */
    }

    //SIOCGIFFLAGS flags
    enum {
        IFF_UP = 0x1,               /* Interface is up.  */
        IFF_BROADCAST = 0x2,        /* Broadcast address valid.  */
        IFF_DEBUG = 0x4,            /* Turn on debugging.  */
        IFF_LOOPBACK = 0x8,         /* Is a loopback net.  */
        IFF_POINTOPOINT = 0x10,     /* Interface is point-to-point link.  */
        IFF_MULTICAST = 0x1000,     /* Supports multicast.  */
    }

    public string[] getBroadcastInterfaces() {
        ifaddrs* first;
        if (getifaddrs(&first) < 0) {
            //error, use global broadcast address
            return ["255.255.255.255"];
        }

        string[] res;
        scope addr = new IPv4Address(12345);
        ifaddrs* cur = first;
        while (cur) {
            uint flags = cur.ifa_flags;
            //xxx code duplication, but minor differences make it hard to unify
            if ((flags & IFF_UP) && (flags & IFF_BROADCAST)
                && !(flags & IFF_LOOPBACK)
                && cur.ifa_addr.sa_family == AF_INET
                && cur.ifa_netmask.sa_family == AF_INET)
            {
                sockaddr_in ia = *cast(sockaddr_in*)(cur.ifa_addr);
                sockaddr_in mask = *cast(sockaddr_in*)(cur.ifa_netmask);
                ia.sin_addr = ia.sin_addr | (~mask.sin_addr);

                *cast(sockaddr_in*)addr.name = ia;
                res ~= addr.toAddrString();
            }
            cur = cur.ifa_next;
        }
        freeifaddrs(first);

        return res;
    }
}
