module net.netobject;

import net.encode;
import utils.misc;
import utils.mylist;

debug(noise) {
    import tango.io.Stdout;
}

//increment on incompatible protocol changes, hurhurhur
const cProtocolVersion = -1;

//must be unsigned; must not wrap around
//xxx: should it be ulong? maybe!
alias uint NetObjectID;
//never used value to signal errors or to specify null references
const NetObjectID cNetObjectIDNull = 0;

//4 bytes shall be enough (will be enough for 49 days for 1000 frames/second)
//must be unsigned
alias uint NetFrameID;
//invalid frame
const cNetFrameIDInvalid = 0;

///Piece of data to be shared over the net
///This is for both the client and the server side.
///There can be only one servant, but several clients. Only servants can do
///changes; changes by clients lead to undefined effects on the client side.
///Changes by the servant must be noticed by touch(); then the object's state
///will be synchronized with all clients on the next network frame.
abstract class NetObject {
    private {
        mixin ListNodeMixin list_node;

        NetObjectID mNetID;
        //last frame where this was changed; invalid when checkBit is true
        NetFrameID mFrameNumber;

        //if mCheckBit is true, mLastSnapshot might be invalid; see check()
        bool mCheckBit;
        bool mCreatedBit; //stupid bit for NetObjectsClientGeneric
        void* mLastSnapshot; //data pointed to must stay immutable

        //NetObjects mOwner;
    }

    ///each time a data field is written, this should be called
    ///else the network code _may_ overlook that this object was changed
    final void touch() {
        mCheckBit = true;
    }

    ///check for changes (server only)
    final void serverCheck(NetFrameID currentFrame) {
        assert(currentFrame >= mFrameNumber);
        if (mLastSnapshot) {
            //xxx: doing a comparision with hasChanges is questionable
            //     maybe just wastes time in almost all cases?
            if (!mCheckBit || !hasChanges(mLastSnapshot))
                return;
        }
        mLastSnapshot = snapshot();
        mFrameNumber = currentFrame;
        mCheckBit = false;
    }

    ///last frame this object was changed (only when mCheckBit == false)
    final NetFrameID frame() {
        return mFrameNumber;
    }

    final void* lastSnapshot() {
        return mLastSnapshot;
    }

    ///read from packet data and so whatever
    final void clientUpdate(NetFrameID nid, NetReader rd, void* delta) {
        assert(nid >= mFrameNumber);
        read(rd, delta);
        //if (nid > mFrameNumber) {
            mFrameNumber = nid;
            //xxx this is a waste of time and memory for the reliable case :(
            mLastSnapshot = snapshot();
        //}
    }

    final NetObjectID id() {
        return mNetID;
    }

    ///copy the state from data to this object
    ///data was obtained from the servant's snapshot()-function
    ///_only_ used for the local non-network case (to shortcut marshalling etc.)
    abstract void syncLocal(void* data);

    ///obtain a snapshot of the current state of this object
    ///the snapshot might be either used with syncLocal or read/write
    ///NOTE: might contain active pointers and stuff (relevant to GC)
    //xxx: for simplicity, the function just allocates a memory block and
    //     returns it; maybe one could reuse memory blocks later??
    abstract void* snapshot();

    ///fast check against a snapshot to see of they're the same
    abstract bool hasChanges(void* data);

    ///server-side: write changes into output, relative to delta (a snapshot)
    abstract void write(NetWriter output, void* delta);
    ///client-side: read changes from input, which might be relative to delta
    abstract void read(NetReader input, void* delta);

    //this assigns a new ID, the old one must not be used anymore (IDs are
    // unique in time across a connection)
    package void assign_id(NetObjectID id, NetFrameID frame) {
        mNetID = id;
        mFrameNumber = frame;
        mLastSnapshot = null;
    }

    ///called when it's being added to a NetObjectsServer, right after a new ID
    /// was assigned
    protected void onCreate() {
    }
}

class NetObjectMeta {
    abstract void* initSnapshot();
    abstract char[] typeHash();
    //actually just for debugging
    //crash if this metaclass isn't for the obj
    abstract void typeCheck(NetObject obj);
}

//xxx the following template was in an extra file, this import is only needed for that
import net.marshall2;

///Use this like:
///  class YourNetObject : NetObject {
///     struct YourStruct { ... }
///     YourStruct yourmember;
///     mixin NetObjectStruct!(yourmember);
///  }
///  and in the program:
///    auto server = new NetObjectsServer!(YourNetObject)();
///    auto client = new NetObjectsClient!(YourNetObject)();
///Really just connects the NetObject function to the Marshaller functions.
///Implements all required NetObject functionality.
template NetObjectStruct(alias struct_member) {
    alias typeof(struct_member) StructType;

    static assert(is(StructType == struct));
    static assert(is(typeof(this) : NetObject));

    //can be set from outside or is created on demand
    //xxx: should be in a static metaclass etc.
    //(the type isn't the problem, could just be a Marshaller as well)
    static StructMarshaller!(StructType) marshaller;

    private static void create_marshaller(MarshallContext ctx) {
        //create if marshaller wasn't set yet
        if (!marshaller) {
            if (!ctx) {
                ctx = new MarshallContext();
                registerBaseMarshallers(ctx);
            }
            marshaller = new typeof(marshaller)(ctx);
        }
    }

    override void syncLocal(void* data) {
        marshaller.syncLocal(&struct_member, data);
    }

    override void* snapshot() {
        return marshaller.snapshot(&struct_member);
    }

    override bool hasChanges(void* data) {
        return marshaller.hasChanges(&struct_member, data);
    }

    override void write(NetWriter output, void* delta) {
        marshaller.write(output, &struct_member, delta);
    }

    override void read(NetReader input, void* delta) {
        return marshaller.read(input, &struct_member, delta);
    }

    static NetObjectMeta netobject_meta;

    void createMeta(MarshallContext ctx = null) {
        if (netobject_meta)
            assert(false, "Metaclass already created.");
        netobject_meta = new MetaInfos(ctx);
    }

    static NetObjectMeta getMeta() {
        if (!netobject_meta) {
            netobject_meta = new MetaInfos(null);
        }
        return netobject_meta;
    }

    alias typeof(this) Halp;

    //hurhur
    private static class MetaInfos : NetObjectMeta {
        this(MarshallContext ctx) {
            create_marshaller(ctx);
        }
        void* initSnapshot() {
            StructType Bla;
            return marshaller.snapshot(&Bla);
        }
        char[] typeHash() {
            return marshaller.typeHash();
        }
        void typeCheck(NetObject obj) {
            if (obj && !cast(Halp)obj)
                assert(false, "typeCheck");
        }
    }
}

//check compilability on a simple example
debug {
private:
    class YourNetObject : NetObject {
         struct YourStruct { int blah, hah; }
         YourStruct yourmember;
         mixin NetObjectStruct!(yourmember);
    }
    YourNetObject foo;
}

//snapshot for a single object
private struct ObjectPiece {
    NetObjectID id;
    NetFrameID frame; //"time"
    void* snapshot_data;
    ObjectPiece* next;
}

//snapshot for a client's frame
private struct Frame {
    NetFrameID frame;
    ObjectPiece* list;
}

///per actual network client and NetObjectHome
///stores the state needed for that combination
///represents not strictly a network connection; can represent groups of
///connections as well, when reliable sequenced transport is used
///concrete Server- and Client classes derive from this
abstract class NetObjectEndpoint {
    protected {
        //object set which is replicated
        NetObjects mOwner;
        //if it uses reliable and sequenced transport
        //in this case, each frame is thought to be acked when it's sent
        //xxx only reliable=true implemented
        bool mReliable;
    }

    package void init(NetObjects owner) {
        mOwner = owner;
        mReliable = mOwner.mNoo.reliable_transport;
        assert(mReliable, "oh sorry, not implemented!");
    }
}

///This exists on the server-side for each client connection.
///(this also can be a multicast node)
///User can derive from this class.
///don't confuse with NetObjectsServer
class NetObjectServer : NetObjectEndpoint {
    private {
        //for reliable transport... only one snapshot needed (=> "single")
        Frame mSingleFrame;
        NetObjectsServerGeneric mServer;
    }

    ///last frame which was sent to client (not necessarily acked)
    final NetFrameID lastSentFrame() {
        return mSingleFrame.frame;
    }

    //set to connect-state (doesn't mean much currently)
    package void doConnect(NetObjectsServerGeneric s) {
        assert(!mServer);
        init(s);
        mServer = s;
        //kill snapshots and frame number, also marks connect-state
        mSingleFrame = Frame.init;
    }

    //
    package void doDisconnect() {
    }

    //servant writes stuff into a packet for his client
    package void write(NetWriter wr) {
        NetFrameID new_frame = mOwner.currentFrame;
        assert(mSingleFrame.frame <= new_frame);

        auto server_list = mOwner.mObjects;
        ObjectPiece** client_list = &mSingleFrame.list;
        auto obj_server = server_list.head;
        auto obj_client = *client_list; //client's (old) state

        NetObjectID last_id = 0;

        //write header for this object list
        write_integer_vlen(wr, new_frame);

        //write delta-coded ID (delta coded against last ID)
        void write_id(NetObjectID id) {
            write_integer_delta(wr, id, last_id);
            last_id = id;
        }

        if (mSingleFrame.frame == new_frame) {
            //no changes
            debug foreach (o; mOwner.mObjects) {
                assert(o.frame < new_frame);
            }
            assert(mServer.mLastAddRemoveFrame < new_frame);
            write_id(cNetObjectIDNull);
            return;
        }

        //remove obj_client from snapshot and write removal-event
        void do_delete() {
            debug(noise) Stdout.formatln("delete {}", obj_client.id);
            write_id(obj_client.id);
            write_bool(wr, false); //change flag
            //remove from list
            *client_list = obj_client.next;
            obj_client = obj_client.next;
        }

        debug(noise) {
            writef("list server: ");
            foreach(o; mOwner.mObjects) {
                writef("{} ",o.id);
            }
            Stdout.formatln();
            writef("client: ");
            auto p = mSingleFrame.list;
            while (p) {
                writef("{} ",p.id);
                p = p.next;
            }
            Stdout.formatln();
        }

        //synchronize both lists; write updates into stream if necessary
        while (obj_server && obj_client) {
            if (obj_server.id == obj_client.id) {
                //object was just changed?
                if (obj_server.frame > obj_client.frame) {
                    //write
                    write_id(obj_client.id);
                    write_bool(wr, true); //change flag
                    obj_server.write(wr, obj_client.snapshot_data);
                    //update local list
                    obj_client.snapshot_data = obj_server.lastSnapshot;
                    obj_client.frame = obj_server.frame;
                    debug(noise) Stdout.formatln("change {}", obj_server.id);
                } else
                    debug(noise) Stdout.formatln("nochange {}", obj_server.id);
                //advance both
                obj_server = server_list.next(obj_server);
                client_list = &obj_client.next;
                obj_client = *client_list;
            } else if (obj_server.id > obj_client.id) {
                //the client object must have died!
                do_delete();
            } else {
                assert(obj_server.id < obj_client.id);
                //can't happen because an old object must always be included in
                //the snapshot, and new objects have the highest id all around
                debug(noise) Stdout.formatln("ffff {} {}", obj_server.id, obj_client.id);
                assert(false);
            }
        }

        //trail of deleted objects
        while (obj_client) {
            do_delete();
        }

        //trail of new objects
        while (obj_server) {
            //new object (NOTE: no change-flag)
            write_id(obj_server.id);
            obj_server.write(wr, mOwner.init_snapshot);
            //new snapshot descriptor, and insert it
            obj_client = new ObjectPiece;
            *client_list = obj_client;
            client_list = &obj_client.next;
            //fill it out
            obj_client.id = obj_server.id;
            obj_client.snapshot_data = obj_server.lastSnapshot;
            obj_client.frame = obj_server.frame;

            debug(noise) Stdout.formatln("new {}", obj_server.id);

            obj_server = server_list.next(obj_server);
        }

        //stream termination
        write_id(cNetObjectIDNull);

        mSingleFrame.frame = new_frame;
    }

    //if you're a client and need to send an ack
    private void do_send_ack(NetFrameID frame) {
        assert(false);
    }
}

//covers a client connection
//internal because user doesn't need to know it
private class NetObjectClient : NetObjectEndpoint {
    private {
        NetFrameID mCurrentFrame;
        NetObjectsClientGeneric mClient;
    }

    this(NetObjectsClientGeneric owner) {
        init(owner);
        mClient = owner;
    }

    NetFrameID currentFrame() {
        return mCurrentFrame;
    }

    void read(NetReader rd) {
        //xxx: when having unreliable transport, you need to maintain several
        //     snapshot against which the incoming packet might be delta-coded
        //     (because it's not clear what frame-ack-message the server
        //     receives). but in the reliable case there's only one snapshot,
        //     and because the client doesn't change the local data at all, you
        //     actually could delta-code against the data stored in the object
        //     itself, so you waste memory and time in the reliable case :(

        auto client_list = mOwner.mObjects;
        auto obj_client = client_list.head;

        NetObjectID last_id = 0;

        //write header for this object list
        auto newframe = read_integer_vlen!(NetFrameID)(rd);
        bool same = (mCurrentFrame == newframe);
        //xxx replace by "network protocol error" or so
        assert((mCurrentFrame == cNetFrameIDInvalid) ||
            same ||
            (mCurrentFrame == newframe - 1));
        mCurrentFrame = newframe;

        NetObjectID read_id() {
            auto res = read_integer_delta(rd, last_id);
            last_id = res;
            return res;
        }

        auto nid = read_id();

        //xxx replace by protocol error
        if (same)
            assert(nid == cNetObjectIDNull, "same frame => no changes!");

        while (nid != cNetObjectIDNull) {
            //find object next to update
            while (obj_client && nid > obj_client.id)
                obj_client = client_list.next(obj_client);
            if (obj_client && nid < obj_client.id) {
                //trying to update a non-existing object? shouldn't happen
                //xxx replace crash by "protocol error" or so
                assert(false);
            }
            if (obj_client) {
                assert(obj_client.id == nid); //by logic
                bool change = read_bool(rd); //the changeflag
                if (change) {
                    //update this object
                    obj_client.clientUpdate(newframe, rd,
                        obj_client.lastSnapshot);
                } else {
                    //delete it
                    auto nobj = client_list.next(obj_client);
                    //moves it to a kill list (for notification)
                    mClient.deleteObject(obj_client);
                    obj_client = nobj;
                }
            } else {
                //new object
                auto nobj = mClient.newObject(nid);
                nobj.clientUpdate(newframe, rd, mOwner.init_snapshot);
            }
            //next
            nid = read_id();
        }
    }

    ///when an ack from the client was received
    void clientAck(NetFrameID frame) {
        assert(false);
    }
}

///Options which can be passed to the NetObjects constructors
struct NetObjectsOptions {
    ///Underlying transport is reliable (packet retransmission and sequenced)
    ///i.e. no acks need to be sent, delta-compression always to the last frame
    ///xxx only reliable implemented
    bool reliable_transport = true;
    ///User specific string which represents the version of the user's protocol
    ///(used for a protocol hash to check protocol compatibility)
    ///see NetObjects.protocolHash
    char[] protocol_hash = "none";

    char[] toString() {
        return myformat("[reliable={}, protocol_hash='{}']",
            reliable_transport, protocol_hash);
    }
}

///Manages and "owns" a set of NetObjects of the same type and controlls their
///lifetime and network synchronization. A NetObject gets created for a given
///NetObjectOwner, and if it's removed from it, the NetObject is dead forever
///(at least as seen over the network).
///client and server parts: NetObjectsServer, NetObjectOwnerClient
class NetObjects {
    //sorted by ID, newest state
    protected {
        List!(NetObject) mObjects;
        NetObjectMeta mMeta;
        NetObjectsOptions mNoo;
    }
    private {
        NetFrameID mCurrentFrame;
        void* mInitSnapshot;
    }

    this(NetObjectMeta meta, NetObjectsOptions noo) {
        mObjects = new typeof(mObjects)(NetObject.list_node.getListNodeOffset);
        mMeta = meta;
        mInitSnapshot = meta.initSnapshot();
        mNoo = noo;
        assert(noo.reliable_transport, "not implemented");
    }

    ///Return a string which represents the protocol version.
    ///Used to make a hash out of it and to test if the same protocol is used.
    final char[] protocolHash() {
        return myformat("NetObjects_v{}_{{}}_{{}}", cProtocolVersion,
            mNoo.protocol_hash, mMeta.typeHash);
    }

    final NetFrameID currentFrame() {
        return mCurrentFrame;
    }

    //frame is managed by subclasses
    protected void updateFrame(NetFrameID frame) {
        assert(frame >= mCurrentFrame);
        mCurrentFrame = frame;
    }

    ///snapshot for initial state (used to delta compress new objects)
    final void* init_snapshot() {
        return mInitSnapshot;
    }

    final NetObject findObject(NetObjectID id) {
        //xxx: can has faster than O(n) plz???
        foreach (o; mObjects) {
            if (o.id == id)
                return o;
        }
        return null;
    }

    ///returns a _read_only_ list of all objects
    ///access violations and segfaults will hunt you at the same time if you
    ///ever change the list or rely that the list doesn't change on updates
    final typeof(mObjects) object_list() {
        return mObjects;
    }
}

abstract class NetObjectsServerGeneric : NetObjects {
    private {
        //clients; can include (reliable) multicast "clients"
        NetObjectServer[] mClients;
        NetFrameID mLastAddRemoveFrame; //last time an object was added/removed
        NetObjectID mIDAlloc;
    }

    this(NetObjectMeta meta, NetObjectsOptions noo) {
        super(meta, noo);
    }

    private final NetObjectID allocID() {
        //currently per-NetObjects
        //it wouldn't be simple to have globally unique IDs, because client PCs
        //can have NetObjectsServers as well
        return ++mIDAlloc;
    }

    final void addObject(NetObject obj) {
        mMeta.typeCheck(obj);
        mLastAddRemoveFrame = currentFrame;
        obj.assign_id(allocID(), currentFrame);
        //inserted at end, IDs increase monotonically => sorted by ID
        mObjects.insert_tail(obj);
    }

    final void removeObject(NetObject obj) {
        assert(mObjects.contains(obj));
        mObjects.remove(obj);
        mLastAddRemoveFrame = currentFrame;
    }

    ///iterate through the object list, check for changes, possibly update
    ///snapshots
    ///also steps to the next frame, but only if something changed!
    ///returns if clients must be served at all
    final bool nextFrame() {
        auto nframe = currentFrame + 1;
        bool changed = mLastAddRemoveFrame == currentFrame;
        foreach (NetObject o; mObjects) {
            o.serverCheck(currentFrame);
            if (o.frame == currentFrame)
                changed = true;
        }
        if (changed)
            updateFrame(nframe);
        return changed;
    }

    ///write state changes of client to the packet wr
    ///should always done like this:
    ///   server.nextFrame();
    ///   for_each_client server.updateClient(client, client_wr);
    ///hm, only god knows why it's not a method of client directly!?!?
    final void updateClient(NetObjectServer client, NetWriter wr) {
        if (client.mOwner !is this)
            assert(false);
        client.write(wr);
    }

    ///add a client (the server part of the client)
    ///this will reset the protocol state
    final void connect(NetObjectServer client) {
        if (client.mServer)
            assert(false, "somewhere added already");
        mClients ~= client;
        client.doConnect(this);
        assert(client.mServer is this);
    }

    final void disconnect(NetObjectServer client) {
        if (client.mServer !is this)
            assert(false);
        client.doDisconnect();
    }

    ///return connected clients
    ///returned array must not be changed
    final NetObjectServer[] clients() {
        return mClients;
    }
}

///Type specific servant class.
///there's a shitty protocol: there must exist a "NetObjectMeta T.getMeta()",
///  which returns the metaclass for T. sorry for this bullshit :/
class NetObjectsServer(T : NetObject) : NetObjectsServerGeneric {
    ///same as findObject, but with the correct static type
    T find(NetObjectID id) {
        return castStrict!(T)(findObject(id)); //cast error is a logic error
    }

    this(NetObjectsOptions noo = NetObjectsOptions.init) {
        //major bullshittery :(
        super(T.getMeta, noo);
    }

    void add(T nobj) {
        addObject(nobj);
    }

    void remove(T obj) {
        removeObject(obj);
    }
}

abstract class NetObjectsClientGeneric : NetObjects {
    private {
        NetObjectClient mClient;
        List!(NetObject) mKillList;
        NetFrameID mLastUpdate;
    }

    this(NetObjectMeta meta, NetObjectsOptions noo) {
        super(meta, noo);
        mClient = new NetObjectClient(this);
        mKillList = new typeof(mObjects)(NetObject.list_node.getListNodeOffset);
    }

    abstract protected NetObject doAllocate();
    abstract protected void dispatchEvent(NetObject obj, bool create,
        bool remove);

    //called by protocol-code
    package void deleteObject(NetObject o) {
        assert(mObjects.contains(o));
        mObjects.remove(o);
        mKillList.insert_tail(o);
    }
    package NetObject newObject(NetObjectID id) {
        assert(id != cNetObjectIDNull);
        if (mObjects.tail)
            assert(id > mObjects.tail.id);
        NetObject nobj = doAllocate();
        nobj.assign_id(id, currentFrame);
        nobj.mCreatedBit = true;
        mObjects.insert_tail(nobj);
        return nobj;
    }

    ///read from a network packet
    final void read(NetReader rd) {
        mClient.read(rd);
        updateFrame(mClient.currentFrame);
    }

    ///dispatch local events
    ///returned value is always valid (except during updating)
    final bool needLocalUpdate() {
        return currentFrame > mLastUpdate;
    }

    ///dispatch update events
    final void localUpdate() {
        if (!needLocalUpdate)
            return;
        foreach (o; mObjects) {
            if (o.frame > mLastUpdate) {
                dispatchEvent(o, o.mCreatedBit, false);
                o.mCreatedBit = false;
            }
        }
        foreach (o; mKillList) {
            dispatchEvent(o, false, true);
        }
        mKillList.clear();
        mLastUpdate = currentFrame;
    }
}

///Type specific client class. Also see NetObjectsServer.
class NetObjectsClient(T : NetObject) : NetObjectsClientGeneric {
    this(NetObjectsOptions noo = NetObjectsOptions.init) {
        //major bullshittery :(
        //and also duplicated from above
        super(T.getMeta, noo);
    }

    protected void dispatchEvent(NetObject obj, bool create, bool remove) {
        assert(!(create && remove));
        T bla = castStrict!(T)(obj);

        if (create && onNewObject)
            onNewObject(bla);
        if (remove && onDeleteObject)
            onDeleteObject(bla);
        if ((!create && !remove) && onModifyObject)
            onModifyObject(bla);

        if (onChangeObject)
            onChangeObject(bla, create, remove);
    }

    ///see NetObjectsServer.find
    //duplicated from above grrr
    T find(NetObjectID id) {
        return castStrict!(T)(findObject(id)); //cast error is a logic error
    }

    override protected NetObject doAllocate() {
        if (onAllocate)
            return onAllocate();
        static if (!is(typeof(new T())))
            assert(false);
        else
            return new T();
    }

    ///If a new object is received from the server, allocate a new user specific
    ///NetObject instance. If null, the standard constructor is called.
    T delegate() onAllocate;

    ///called when a new object was created
    void delegate(T obj) onNewObject;
    ///called when an object's data was modified
    void delegate(T obj) onModifyObject;
    ///called when an object was removed
    void delegate(T obj) onDeleteObject;
    ///called when an object was created, modified or deleted
    ///invoked after the more specific events were notified (but only per
    ///object, i.e. modify(obj1) change(obj1) modify(obj2) change(obj2)...)
    ///create and destroy reflect what happened, create&&destroy is impossible
    void delegate(T obj, bool create, bool destroy) onChangeObject;
}
