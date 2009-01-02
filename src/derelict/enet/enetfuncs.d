module derelict.enet.enetfuncs;

extern(C):

import derelict.enet.enettypes;
import derelict.util.loader;

typedef int function() pfenet_initialize;
typedef int function(ENetVersion ver, ENetCallbacks* inits) pfenet_initialize_with_callbacks;
typedef void function() pfenet_deinitialize;
pfenet_initialize enet_initialize;
pfenet_initialize_with_callbacks enet_initialize_with_callbacks;
pfenet_deinitialize enet_deinitialize;

typedef enet_uint32 function() pfenet_time_get;
typedef void function(enet_uint32) pfenet_time_set;
pfenet_time_get enet_time_get;
pfenet_time_set enet_time_set;

typedef ENetSocket function(ENetSocketType, ENetAddress*) pfenet_socket_create;
typedef ENetSocket function(ENetSocket, ENetAddress*) pfenet_socket_accept;
typedef int function(ENetSocket, ENetAddress*) pfenet_socket_connect;
typedef int function(ENetSocket, ENetAddress*, ENetBuffer*, size_t) pfenet_socket_send;
typedef int function(ENetSocket, ENetAddress*, ENetBuffer*, size_t) pfenet_socket_receive;
typedef int function(ENetSocket, enet_uint32*, enet_uint32) pfenet_socket_wait;
typedef void function(ENetSocket) pfenet_socket_destroy;
pfenet_socket_create enet_socket_create;
pfenet_socket_accept enet_socket_accept;
pfenet_socket_connect enet_socket_connect;
pfenet_socket_send enet_socket_send;
pfenet_socket_receive enet_socket_receive;
pfenet_socket_wait enet_socket_wait;
pfenet_socket_destroy enet_socket_destroy;

typedef int function(ENetAddress* address, char* hostName) pfenet_address_set_host;
typedef int function(ENetAddress* address, char* hostName, size_t nameLength) pfenet_address_get_host_ip;
typedef int function(ENetAddress* address, char* hostName, size_t nameLength) pfenet_address_get_host;
pfenet_address_set_host enet_address_set_host;
pfenet_address_get_host_ip enet_address_get_host_ip;
pfenet_address_get_host enet_address_get_host;

typedef ENetPacket* function(void*, size_t, enet_uint32) pfenet_packet_create;
typedef void function(ENetPacket*) pfenet_packet_destroy;
typedef int function(ENetPacket*, size_t) pfenet_packet_resize;
pfenet_packet_create enet_packet_create;
pfenet_packet_destroy enet_packet_destroy;
pfenet_packet_resize enet_packet_resize;

typedef ENetHost* function(ENetAddress*, size_t, enet_uint32, enet_uint32) pfenet_host_create;
typedef void function(ENetHost*) pfenet_host_destroy;
typedef ENetPeer* function(ENetHost*, ENetAddress*, size_t) pfenet_host_connect;
typedef int function(ENetHost*, ENetEvent*, enet_uint32) pfenet_host_service;
typedef void function(ENetHost*) pfenet_host_flush;
typedef void function(ENetHost*, enet_uint8, ENetPacket*) pfenet_host_broadcast;
typedef void function(ENetHost*, enet_uint32, enet_uint32) pfenet_host_bandwidth_limit;
pfenet_host_create enet_host_create;
pfenet_host_destroy enet_host_destroy;
pfenet_host_connect enet_host_connect;
pfenet_host_service enet_host_service;
pfenet_host_flush enet_host_flush;
pfenet_host_broadcast enet_host_broadcast;
pfenet_host_bandwidth_limit enet_host_bandwidth_limit;

typedef int function(ENetPeer*, enet_uint8, ENetPacket*) pfenet_peer_send;
typedef ENetPacket* function(ENetPeer*, enet_uint8) pfenet_peer_receive;
typedef void function(ENetPeer*) pfenet_peer_ping;
typedef void function(ENetPeer*) pfenet_peer_reset;
typedef void function(ENetPeer*, enet_uint32) pfenet_peer_disconnect;
typedef void function(ENetPeer*, enet_uint32) pfenet_peer_disconnect_now;
typedef void function(ENetPeer*, enet_uint32) pfenet_peer_disconnect_later;
typedef void function(ENetPeer*, enet_uint32, enet_uint32, enet_uint32) pfenet_peer_throttle_configure;
pfenet_peer_send enet_peer_send;
pfenet_peer_receive enet_peer_receive;
pfenet_peer_ping enet_peer_ping;
pfenet_peer_reset enet_peer_reset;
pfenet_peer_disconnect enet_peer_disconnect;
pfenet_peer_disconnect_now enet_peer_disconnect_now;
pfenet_peer_disconnect_later enet_peer_disconnect_later;
pfenet_peer_throttle_configure enet_peer_throttle_configure;


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
