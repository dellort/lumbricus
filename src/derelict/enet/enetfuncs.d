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
    bindFunc(enet_initialize)("enet_initialize",lib);
    bindFunc(enet_initialize_with_callbacks)("enet_initialize_with_callbacks",lib);
    bindFunc(enet_deinitialize)("enet_deinitialize",lib);

    bindFunc(enet_time_get)("enet_time_get",lib);
    bindFunc(enet_time_set)("enet_time_set",lib);

    bindFunc(enet_socket_create)("enet_socket_create",lib);
    bindFunc(enet_socket_accept)("enet_socket_accept",lib);
    bindFunc(enet_socket_connect)("enet_socket_connect",lib);
    bindFunc(enet_socket_send)("enet_socket_send",lib);
    bindFunc(enet_socket_receive)("enet_socket_receive",lib);
    bindFunc(enet_socket_wait)("enet_socket_wait",lib);
    bindFunc(enet_socket_set_option)("enet_socket_set_option",lib);
    bindFunc(enet_socket_destroy)("enet_socket_destroy",lib);

    bindFunc(enet_address_set_host)("enet_address_set_host",lib);
    bindFunc(enet_address_get_host_ip)("enet_address_get_host_ip",lib);
    bindFunc(enet_address_get_host)("enet_address_get_host",lib);

    bindFunc(enet_packet_create)("enet_packet_create",lib);
    bindFunc(enet_packet_destroy)("enet_packet_destroy",lib);
    bindFunc(enet_packet_resize)("enet_packet_resize",lib);

    bindFunc(enet_host_create)("enet_host_create",lib);
    bindFunc(enet_host_destroy)("enet_host_destroy",lib);
    bindFunc(enet_host_connect)("enet_host_connect",lib);
    bindFunc(enet_host_check_events)("enet_host_check_events",lib);
    bindFunc(enet_host_service)("enet_host_service",lib);
    bindFunc(enet_host_flush)("enet_host_flush",lib);
    bindFunc(enet_host_broadcast)("enet_host_broadcast",lib);
    bindFunc(enet_host_bandwidth_limit)("enet_host_bandwidth_limit",lib);

    bindFunc(enet_peer_send)("enet_peer_send",lib);
    bindFunc(enet_peer_receive)("enet_peer_receive",lib);
    bindFunc(enet_peer_ping)("enet_peer_ping",lib);
    bindFunc(enet_peer_reset)("enet_peer_reset",lib);
    bindFunc(enet_peer_disconnect)("enet_peer_disconnect",lib);
    bindFunc(enet_peer_disconnect_now)("enet_peer_disconnect_now",lib);
    bindFunc(enet_peer_disconnect_later)("enet_peer_disconnect_later",lib);
    bindFunc(enet_peer_throttle_configure)("enet_peer_throttle_configure",lib);
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
