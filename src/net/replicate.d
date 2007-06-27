module net.replicate;

//used for delta compression
class ReferenceFrame {
    ulong uid;
    MyBox[] data;
}

class NetClass {
    /// Add a field.
    void add(T)(char[] name);
}

class NetList {
    NetClass itemType();

    /// return an object managed by this list
    NetObject find(ulong uid);

    /// Callbacks on specific events for objects
    void delegate(NetObject o) onAdd;
    void delegate(NetObject o) onRemove;
}

class NetObject {
    /// free for use
    Object userdata;

    void setPtr(T)(char[] name, T* ptr);

    private MyBox[] mData;

    this(NetClass cl);

    public final ulong uid();
    /// if active, i.e. synced acrossed network
    public final bool active();

    void set(T)(int id);
    T get(T)(int id);
}

