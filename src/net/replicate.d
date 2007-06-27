module net.replicate;
import std.stream;
import utils.mylist;

alias uint FrameID;
alias ulong ObjectID;

//serialize/unserialize
alias void delegate(OutputStream stream, void* data) SerializeDelegate;
alias void delegate(InputStream stream, void* data) DeserializeDelegate;

private struct NetworkSerializer {
    SerializeDelegate serialize;
    DeserializeDelegate deserialize;
}

//singleton, which contains all the stuff (both static and normal information)
//i.e. Connections, NetClasses, NetObjects...
class NetBase {
    private {
        NetworkSerializer[TypeInfo] mNetworkSerializers;

        //allocation of uids, which shall be unique in space and time
        //(actually, uids could be per NetClass, but in this way, this
        // simplifies cross-references)
        ObjectID mUidAlloc;

        FrameID mCurrentFrame;

        //all registered lists and NetObject classes (NetList.itemType())
        NetList[] mLists;

        Connection[] mConnections;

        //some default serializers/deserializers
        //(trivial code, but the generic handling of data is the problem)
        void serInt(OutputStream stream, void* data) {
            stream.write(*cast(int*)data);
        }
        void deserInt(InputStream stream, void* data) {
            stream.read(*cast(int*)data);
        }
        void serLong(OutputStream stream, void* data) {
            stream.write(*cast(long*)data);
        }
        void deserLong(InputStream stream, void* data) {
            stream.read(*cast(long*)data);
        }
        //actually only serialized NetObject references (not their data)
        void serNetObject(OutputStream stream, void* data) {
            ulong id = (*cast(NetObject*)data).uid;
            stream.write(id);
        }
        void deserNetObject(InputStream stream, void* data) {
            ulong id;
            stream.read(id);
            *cast(NetObject*)data = findNetObject(id);
        }

        //called from Connection.this()
        private void registerConnection(Connection conn) {
            assert(conn.base is this);
            mConnections ~= conn;
        }
    }

    ObjectID allocUid() {
        return ++mUidAlloc;
    }

    FrameID currentFrame() {
        return mCurrentFrame;
    }

    //find a NetObject by ID
    //  type = expected class, to type-check stuff or to speed up things
    //         can be null
    //return null if not found
    NetObject findNetObject(ObjectID id, NetClass type = null) {
        NetObject found;
        foreach (NetList l; mLists) {
            found = l.find(id);
        }
        if (type) {
            assert(found.mType is type);
        }
        return found;
    }

    void registerSerializer(T)(SerializeDelegate serialize,
        DeserializeDelegate deserialize)
    {
        TypeInfo type = typeid(T);
        if (type in mNetworkSerializers) {
            assert(false, "type already registered");
        }
        NetworkSerializer s;
        s.serialize = serialize;
        s.deserialize = deserialize;
        mNetworkSerializers[type] = s;
    }

    this() {
        //register the default serializers
        registerSerializer!(int)(&serInt, &deserInt);
        registerSerializer!(uint)(&serInt, &deserInt); //works, but is unclean
        registerSerializer!(long)(&serLong, &deserLong);
        registerSerializer!(ulong)(&serLong, &deserLong); //dito

        registerSerializer!(NetObject)(&serNetObject, &deserNetObject);
    }
}

class Connection {
    private NetBase mBase;
    //to add: Channel object from NetLayer (which also needs to be added)

    NetBase base() {
        return mBase;
    }

    this(NetBase base) {
        mBase = base;
        mBase.registerConnection(this);
    }
}

//NOTE: for simplicity, there's only one NetList per NetClass and NetBase
class NetClass {
    private {
        struct FieldInfo {
            TypeInfo type;
            uint id;
            char[] name;
            NetworkSerializer serialize;
        }

        uint[char[]] mFieldLookup;
        FieldInfo[] mFields;
        //true if adding fields is not allowed anymore
        bool mFieldsDone;
        NetBase mBase;
    }

    /// Add a field.
    void add(T)(char[] name) {
        if (mFieldsDone) {
            assert(false, "adding fields not allowed anymore");
        }
        FieldInfo info;
        info.name = name;
        info.id = mFields.length;
        info.type = typeid(T);
        if (!(info.type in gNetworkSerializer)) {
            assert(false, "no serializer found for this type");
        }
        info.serialize = gNetworkSerializer[info.type];
    }

    package void prepareInstantiate() {
        if (!mFieldsDone) {
            //do whatever you need to do before actually creating a NetObject of
            //this type:
            //...
            mFieldsDone = true;
        }
    }

    this(NetBase base, char[] className) {
        mBase = base;
    }
}

//used for delta compression, exists per Connection and NetObject
private struct ReferenceFrame {
    bool valid;
    FrameID age;
    //for now: raw stream data
    void[] data;
}

class NetList {
    private {
        NetClass mType;
        NetBase mBase;
        //active objects; sorted by uid (corresponds to creation time)
        List!(NetObject) mObjects;
        FrameID mDidChange;
    }

    package void activate(NetObject obj) {
        //NOTE: order in that list is awfully important (sorted by age == uid)
        mObjects.insert_tail(obj);
        mDidChange = mBase.currentFrame();
    }

    NetClass itemType() {
        return mType;
    }

    /// return an object managed by this list
    NetObject find(ObjectID uid) {
        foreach (NetObject o; mObjects) {
            if (o.mUid == uid)
                return o;
        }
        return null;
    }

    /// Callbacks on specific events for objects
    void delegate(NetObject o) onAdd;
    void delegate(NetObject o) onRemove;

    this(NetBase base, NetClass aItemType) {
        mObjects = new typeof(mObjects)(NetObject.node.getListNodeOffset());
        mType = aItemType;
        mBase = base;
    }

    //the funny part (including delta coding)
    void serialize(Connection conn, OutputStream stream) {
        foreach (NetObject o; mObjects) {
            //xxx: since all NetObjects of one class need the same size (at
            //     least if the serializer functions agree -> wrong for char[]),
            //     one could reuse that memory buffer, but: *sigh*.
            auto temp = new MemoryStream();
            o.serialize(temp);
            void[] data = temp.data();
            delete temp;
            //compare against old frame
            ReferenceFrame refframe = o.mReferenceFrames[o.mReferenceFrameCur];
            if (refframe.valid) {
                //check for changes
                if (refframe.data != data) {
                    //- enter into o.mReferenceFrames ringlist
                    //- delta code against client's last acked frame o.mLastAcked
                }
            }
        }
    }
}

//number of frames the server remembers for delta compression
const MAX_REMEMBERED_FRAMES = 2;

class NetObject {
    private {
        ObjectID mUid;
        NetList mOwner;
        NetClass mType;
        Object mInstance; //user object
        void*[] mData; //pointers to data fields
        bool mActive, mDead;
        //NetList.mObjects
        mixin ListNodeMixin node;

        //reference frames for delta compression
        //this is per Connection and also per NetObject
        FrameID[Connection] mLastAcked;
        //last frame this NetObject was updated (might be != currentFrame)
        FrameID mLastFrame;
        //stupid ring list of frames in the past
        //   mReferenceFrames[mReferenceFrameCur+0] = current
        //   mReferenceFrames[mReferenceFrameCur+n % $] = n frames in the past
        int mReferenceFrameCur;
        ReferenceFrame[MAX_REMEMBERED_FRAMES] mReferenceFrames;
    }

    /// free for use
    Object userdata;

    public final Object userInstance() {
        return mInstance;
    }

    public final ObjectID uid() {
        return mUid;
    }

    /// if active, i.e. synced across network
    public final bool active() {
        return mActive;
    }

    void setPtr(T)(char[] name, T* ptr) {
        if (mActive || mDead) {
            assert(false, "now it's too late");
        }

        TypeInfo type = typeid(T);
        uint id = name in mFieldLookup;

        if (mType.mFields[id].type !is type) {
            //type must be exactly the same
            assert(false, "wrong type!");
        }

        mData[id] = ptr;
    }

    public void activate() {
        if (mDead) {
            //because of uid problems
            assert(false, "can't be re-activated");
        }

        if (mActive) {
            assert(false);
        }

        //check if all fields are there (at least for a client, not giving a
        //pointer for a field could maybe allowed)
        foreach (void* p; mData) {
            assert(p !is null);
        }

        mActive = true;
        mOwner.activate(this);
    }

    //write all the data
    //the NetList cares about metadata (like uid)
    void serialize(OutputStream stream) {
        foreach (int index, void* ptr; mData) {
            mType.mFields[index].serialize.serialize(stream, ptr);
        }
    }
    void deserialize(InputStream stream) {
        foreach (int index, void* ptr; mData) {
            mType.mFields[index].serialize.deserialize(stream, ptr);
        }
    }

    //create as item of that list
    this(NetClass type, NetList list, Object instance) {
        if (!type.mFieldsDone) {
            //why do you think I created that spiffy function
            assert(false, "argh, you didn't call prepareInstantiate()");
        }

        mInstance = instance;
        mOwner = list;
        mType = type;
        //does that make sense? but conceptually, they're different
        assert(mOwner.itemType() is mType);
        //allocate a uid; can be done even if this object isn't yet "activated"
        mUid = mOwner.mBase.allocUid();

        mData.length = mType.mFields.length;
    }
}

