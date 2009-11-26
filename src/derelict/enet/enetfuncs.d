module derelict.enet.enetfuncs;

import derelict.enet.enettypes;
import derelict.util.loader;

extern(C):

int function() enet_initialize;
int function(ENetVersion ver, ENetCallbacks* inits) enet_initialize_with_callbacks;
void function() enet_deinitialize;

enet_uint32 function() enet_time_get;
void function(enet_uint32) enet_time_set;

//--> 1.2 stable
ENetSocket function(ENetSocketType, ENetAddress*) enet_socket_create;
ENetSocket function(ENetSocket, ENetAddress*) enet_socket_accept;
//<--
/*--> 1.2+ CVS
ENetSocket function(ENetSocketType) enet_socket_create;
int function(ENetSocket, const ENetAddress *) enet_socket_bind;
int function(ENetSocket, int) enet_socket_listen;
//<--*/
int function(ENetSocket, ENetAddress*) enet_socket_connect;
int function(ENetSocket, ENetAddress*, ENetBuffer*, size_t) enet_socket_send;
int function(ENetSocket, ENetAddress*, ENetBuffer*, size_t) enet_socket_receive;
int function(ENetSocket, enet_uint32*, enet_uint32) enet_socket_wait;
int function(ENetSocket, ENetSocketOption, int) enet_socket_set_option;
void function(ENetSocket) enet_socket_destroy;

int function(ENetAddress* address, char* hostName) enet_address_set_host;
int function(ENetAddress* address, char* hostName, size_t nameLength) enet_address_get_host_ip;
int function(ENetAddress* address, char* hostName, size_t nameLength) enet_address_get_host;

ENetPacket* function(void*, size_t, enet_uint32) enet_packet_create;
void function(ENetPacket*) enet_packet_destroy;
int function(ENetPacket*, size_t) enet_packet_resize;

ENetHost* function(ENetAddress*, size_t, enet_uint32, enet_uint32) enet_host_create;
void function(ENetHost*) enet_host_destroy;
ENetPeer* function(ENetHost*, ENetAddress*, size_t) enet_host_connect;
int function(ENetHost *, ENetEvent *) enet_host_check_events;
int function(ENetHost*, ENetEvent*, enet_uint32) enet_host_service;
void function(ENetHost*) enet_host_flush;
void function(ENetHost*, enet_uint8, ENetPacket*) enet_host_broadcast;
void function(ENetHost*, enet_uint32, enet_uint32) enet_host_bandwidth_limit;

int function(ENetPeer*, enet_uint8, ENetPacket*) enet_peer_send;
ENetPacket* function(ENetPeer*, enet_uint8) enet_peer_receive;
void function(ENetPeer*) enet_peer_ping;
void function(ENetPeer*) enet_peer_reset;
void function(ENetPeer*, enet_uint32) enet_peer_disconnect;
void function(ENetPeer*, enet_uint32) enet_peer_disconnect_now;
void function(ENetPeer*, enet_uint32) enet_peer_disconnect_later;
void function(ENetPeer*, enet_uint32, enet_uint32, enet_uint32) enet_peer_throttle_configure;


extern(D):

private void load(SharedLib lib) {
    *cast(void**)&enet_initialize = Derelict_GetProc(lib, "enet_initialize");
    *cast(void**)&enet_initialize_with_callbacks = Derelict_GetProc(lib, "enet_initialize_with_callbacks");
    *cast(void**)&enet_deinitialize = Derelict_GetProc(lib, "enet_deinitialize");

    *cast(void**)&enet_time_get = Derelict_GetProc(lib, "enet_time_get");
    *cast(void**)&enet_time_set = Derelict_GetProc(lib, "enet_time_set");

    *cast(void**)&enet_socket_create = Derelict_GetProc(lib, "enet_socket_create");
    *cast(void**)&enet_socket_accept = Derelict_GetProc(lib, "enet_socket_accept");
    *cast(void**)&enet_socket_connect = Derelict_GetProc(lib, "enet_socket_connect");
    *cast(void**)&enet_socket_send = Derelict_GetProc(lib, "enet_socket_send");
    *cast(void**)&enet_socket_receive = Derelict_GetProc(lib, "enet_socket_receive");
    *cast(void**)&enet_socket_wait = Derelict_GetProc(lib, "enet_socket_wait");
    *cast(void**)&enet_socket_set_option = Derelict_GetProc(lib, "enet_socket_set_option");
    *cast(void**)&enet_socket_destroy = Derelict_GetProc(lib, "enet_socket_destroy");

    *cast(void**)&enet_address_set_host = Derelict_GetProc(lib, "enet_address_set_host");
    *cast(void**)&enet_address_get_host_ip = Derelict_GetProc(lib, "enet_address_get_host_ip");
    *cast(void**)&enet_address_get_host = Derelict_GetProc(lib, "enet_address_get_host");

    *cast(void**)&enet_packet_create = Derelict_GetProc(lib, "enet_packet_create");
    *cast(void**)&enet_packet_destroy = Derelict_GetProc(lib, "enet_packet_destroy");
    *cast(void**)&enet_packet_resize = Derelict_GetProc(lib, "enet_packet_resize");

    *cast(void**)&enet_host_create = Derelict_GetProc(lib, "enet_host_create");
    *cast(void**)&enet_host_destroy = Derelict_GetProc(lib, "enet_host_destroy");
    *cast(void**)&enet_host_connect = Derelict_GetProc(lib, "enet_host_connect");
    *cast(void**)&enet_host_check_events = Derelict_GetProc(lib, "enet_host_check_events");
    *cast(void**)&enet_host_service = Derelict_GetProc(lib, "enet_host_service");
    *cast(void**)&enet_host_flush = Derelict_GetProc(lib, "enet_host_flush");
    *cast(void**)&enet_host_broadcast = Derelict_GetProc(lib, "enet_host_broadcast");
    *cast(void**)&enet_host_bandwidth_limit = Derelict_GetProc(lib, "enet_host_bandwidth_limit");

    *cast(void**)&enet_peer_send = Derelict_GetProc(lib, "enet_peer_send");
    *cast(void**)&enet_peer_receive = Derelict_GetProc(lib, "enet_peer_receive");
    *cast(void**)&enet_peer_ping = Derelict_GetProc(lib, "enet_peer_ping");
    *cast(void**)&enet_peer_reset = Derelict_GetProc(lib, "enet_peer_reset");
    *cast(void**)&enet_peer_disconnect = Derelict_GetProc(lib, "enet_peer_disconnect");
    *cast(void**)&enet_peer_disconnect_now = Derelict_GetProc(lib, "enet_peer_disconnect_now");
    *cast(void**)&enet_peer_disconnect_later = Derelict_GetProc(lib, "enet_peer_disconnect_later");
    *cast(void**)&enet_peer_throttle_configure = Derelict_GetProc(lib, "enet_peer_throttle_configure");
}

GenericLoader DerelictENet;
static this() {
    DerelictENet.setup(
        "enet.dll",
        "libenet.so.2",
        "",
        &load
    );
}
