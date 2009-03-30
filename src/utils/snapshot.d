module utils.snapshot;

import utils.perf;
import utils.reflection;
import utils.log;
import utils.misc;
import utils.time;

import str = stdx.string;

private LogStruct!("utils.snapshot") log;

class SnapDescriptors {
    private {
        Types types;
        SnapDescriptor[Class] class2desc;
        //actually used during writing
        SnapDescriptor[ClassInfo] ci2desc;
    }

    this(Types a_types) {
        types = a_types;
    }

    SnapDescriptor lookupSnapDescriptor(Object o) {
        assert (!!o);
        ClassInfo ci = o.classinfo;
        if (auto pdesc = ci in ci2desc) {
            return *pdesc;
        }
        Class c = types.findClass(o);
        if (!c)
            return null;
        return new SnapDescriptor(this, c);
    }
}

//1. "flat" representation of a class (no inheritance, no nested structs)
//2. data for dynamic arrays and maps
class SnapDescriptor {
    SnapDescriptors descs;
    Type type;
    Class klass; //only for classes; for structs this is null
    bool is_full_pod;
    //pod: byte wise copied
    //maybe it would be better to identify contiguous byte ranges, which can be
    //just copied with memcpy? (but attention: could contain hidden data, that
    //is dangerous to copy, like transient members (?) or the monitor or
    //interface descriptors in normal objects)
    size_t[] pod8, pod16, pod32, pod64;
    //special objects
    ArrayMember[] arrays;
    MapMember[] maps;
    RefMember[] objects;
    DgMember[] dgs;

    struct RefMember {
        size_t offset;
        ReferenceType type;
    }
    struct ArrayMember {
        size_t offset;
        ArrayType t;
        SnapDescriptor item;
    }
    struct MapMember {
        size_t offset;
        MapType t;
        SnapDescriptor key;
        SnapDescriptor value;
    }
    struct DgMember {
        size_t offset;
        DelegateType t;
    }

    //create as "root" (description for an Object)
    this(SnapDescriptors a_descs, Class c) {
        descs = a_descs;
        klass = c;
        assert (!!klass);
        type = klass.type();
        addMembers(klass, 0);
        descs.class2desc[klass] = this;
        descs.ci2desc[castStrict!(ReferenceType)(klass.type()).classInfo()]
            = this;
    }

    //create as some sub member (array items)
    //note that "t" can be a ReferenceType (== a class); then of course only a
    //object reference is added as a member to this descriptor
    this(SnapDescriptors a_descs, Type t) {
        descs = a_descs;
        type = t;
        addMember(type, 0);
        //analysis for is_full_pod
        //check if all bytes are covered by PODs
        bool[] fool;
        fool.length = type.size();
        void cover(size_t[] offs, size_t sz) {
            foreach (o; offs) {
                for (int n = o; n < o + sz; n++) {
                    fool[n] = true;
                }
            }
        }
        cover(pod8, 1);
        cover(pod16, 2);
        cover(pod32, 4);
        cover(pod64, 8);
        is_full_pod = true;
        foreach (b; fool) {
            if (!b)
                is_full_pod = false;
        }
        if (is_full_pod) {
            assert (arrays.length == 0);
            assert (maps.length == 0);
            assert (objects.length == 0);
            assert (dgs.length == 0);
            assert (!klass);
        }
    }

    private void addMembers(Class ck, size_t offset) {
        while (ck) {
            foreach (ClassMember m; ck.nontransientMembers()) {
                addMember(m.type(), offset + m.offset());
            }
            ck = ck.superClass();
        }
    }

    private void addMember(Type mt, size_t offset) {
        //PODs => just copy
        if ((!!cast(BaseType)mt) || (!!cast(EnumType)mt)) {
            switch (mt.size()) {
                case 1: pod8 ~= offset; break;
                case 2: pod16 ~= offset; break;
                case 4: pod32 ~= offset; break;
                case 8: pod64 ~= offset; break;
                default:
                    //cent? real?
                    assert (false);
            }
            return;
        }
        if (auto rt = cast(ReferenceType)mt) {
            //object references
            objects ~= RefMember(offset, rt);
            return;
        }
        if (auto st = cast(StructType)mt) {
            Class k = st.klass();
            assert (!!k);
            addMembers(k, offset);
            return;
        }
        if (auto art = cast(ArrayType)mt) {
            Type amt = art.memberType();
            if (art.isStatic()) {
                //add all array items as in-place variables
                //xxx: reflection.d should tell us about this, because this
                //     is more or less compiler/implementation dependent
                for (int n = 0; n < art.staticLength(); n++) {
                    addMember(amt, offset + n*amt.size());
                }
            } else {
                //here it would be better to copy arrays just bytewise, if
                //the items only consist of PODs
                arrays ~= ArrayMember(offset, art, new SnapDescriptor(descs,
                    amt));
            }
            return;
        }
        if (auto map = cast(MapType)mt) {
            maps ~= MapMember(offset, map, new SnapDescriptor(descs,
                map.keyType()), new SnapDescriptor(descs, map.valueType()));
            return;
        }
        if (auto dg = cast(DelegateType)mt) {
            dgs ~= DgMember(offset, dg);
            return;
        }
        assert (false);
    }
}

class Snapshot {
    private {
        SnapDescriptors mTypes;
        ubyte[] snap_data;
        size_t snap_cur; //data position in snap_data
        size_t snap_read_pos; //same, for reading
        size_t snap_last_object;
        Object[] snap_objects;
        bool[Object] snap_objmarked;
    }

    this(SnapDescriptors a_types) {
        assert(!!a_types);
        mTypes = a_types;
    }

    private void reserve(size_t s) {
        while (snap_data.length < snap_cur + s) {
            snap_data.length = snap_data.length*2;
            if (snap_data.length == 0)
                snap_data.length = 64*1024;
        }
    }

    private void write(T)(T* ptr) {
        size_t s = T.sizeof;
        //align! assume s is power of 2
        //snap_cur = (snap_cur + (s-1)) & ~(s-1);
        reserve(s);
        T* dest = cast(T*)&snap_data[snap_cur];
        *dest = *ptr;
        snap_cur += s;
    }

    private void write_items(T)(void* base, size_t[] offsets) {
        for (int n = 0; n < offsets.length; n++) {
            write!(T)(cast(T*)(base + offsets[n]));
        }
    }

    private void read(T)(T* ptr) {
        size_t s = T.sizeof;
        //snap_read_pos = (snap_read_pos + (s-1)) & ~(s-1);
        assert (snap_read_pos + s <= snap_data.length);
        T* src = cast(T*)&snap_data[snap_read_pos];
        *ptr = *src;
        snap_read_pos += s;
    }

    private void read_items(T)(void* base, size_t[] offsets) {
        for (int n = 0; n < offsets.length; n++) {
            read!(T)(cast(T*)(base + offsets[n]));
        }
    }

    void snap(Object snapObj) {
        snap_cur = 0;
        snap_objects.length = 0;
        //snap_objmarked
        snap_last_object = 0;

        int lookups;

        void queueObject(Object o) {
            if (!o)
                return;
            lookups++;
            bool* pmark = o in snap_objmarked;
            if (!pmark) {
                snap_objmarked[o] = false;
                pmark = o in snap_objmarked;
                assert (!!pmark);
            }
            if (*pmark)
                return;
            *pmark = true;
            snap_objects ~= o;
        }

        void writeItem(void* ptr, SnapDescriptor desc) {
            assert (!!desc);
            write_items!(ubyte)(ptr, desc.pod8);
            write_items!(ushort)(ptr, desc.pod16);
            write_items!(uint)(ptr, desc.pod32);
            write_items!(ulong)(ptr, desc.pod64);
            if (desc.is_full_pod)
                return;
            for (int n = 0; n < desc.objects.length; n++) {
                SnapDescriptor.RefMember m = desc.objects[n];
                void* raw = *cast(void**)(ptr + m.offset);
                write(&raw);
                //(actually, castFrom is only needed for interfaces)
                Object o = m.type.castFrom(raw);
                queueObject(o);
            }
            for (int n = 0; n < desc.arrays.length; n++) {
                SnapDescriptor.ArrayMember m = desc.arrays[n];
                SafePtr ap = SafePtr(m.t, ptr + m.offset);
                ArrayType.Array arr = m.t.getArray(ap);
                assert (arr.ptr.type is m.item.type);
                size_t len = arr.length;
                write(&len);
                if (!m.item.is_full_pod) {
                    //write normally
                    for (int i = 0; i < len; i++) {
                        writeItem(arr.get(i).ptr, m.item);
                    }
                } else {
                    //optimization for cases where this is possible
                    size_t copy = len * arr.ptr.type.size;
                    reserve(copy);
                    void* pdest = &snap_data[snap_cur];
                    pdest[0..copy] = arr.ptr.ptr[0..copy];
                    snap_cur += copy;
                }
            }
            for (int n = 0; n < desc.maps.length; n++) {
                SnapDescriptor.MapMember m = desc.maps[n];
                SafePtr mp = SafePtr(m.t, ptr + m.offset);
                size_t len = m.t.getLength(mp);
                write(&len);
                m.t.iterate(mp, (SafePtr key, SafePtr value) {
                    writeItem(key.ptr, m.key);
                    writeItem(value.ptr, m.value);
                });
            }
            for (int n = 0; n < desc.dgs.length; n++) {
                SnapDescriptor.DgMember m = desc.dgs[n];
                SafePtr dp = SafePtr(m.t, ptr + m.offset);
                Object dg_o;
                ClassMethod dg_m;
                //xxx why is this code duplicated from serialize.d
                if (!mTypes.types.readDelegate(dp, dg_o, dg_m)) {
                    D_Delegate* dgp = cast(D_Delegate*)dp.ptr;
                    char[] what = "enable version debug to see why";
                    debug {
                        log("hello, snapshot.d might crash here.");
                        what = myformat("dest-class: {} function: 0x{:x}",
                            (cast(Object)dgp.ptr).classinfo.name, dgp.funcptr);
                    }
                    throw new Exception("can't snapshot: "~what);
                }
                queueObject(dg_o);
                write(&dg_o);
                write(&dg_m);
            }
        }

        //size_t oldsize = snap_data.length;
        PerfTimer timer = new PerfTimer(true);
        timer.start();

        //xxx: memory is never freed
        foreach (k, ref v; snap_objmarked) {
            v = false;
        }

        queueObject(snapObj);

        while (snap_last_object < snap_objects.length) {
            Object o = snap_objects[snap_last_object];
            auto desc = mTypes.lookupSnapDescriptor(o);
            //if null, maybe an external object (or it is an error)
            if (desc) {
                writeItem(cast(void*)o, desc);
            }
            snap_last_object++;
        }

        timer.stop();
        log("t={}, oc={}, ls={}, size={} ({})",
            timer.time, snap_last_object, lookups, sizeToHuman(snap_cur),
            sizeToHuman(snap_data.length));
    }

    //write back what was stored with snap()
    void unsnap() {
        snap_read_pos = 0;

        Object readRef() {
            int id;
            read(&id);
            return (id==-1) ? null : snap_objects[id];
        }

        void readItem(void* ptr, SnapDescriptor desc) {
            assert (!!desc);
            assert (!!ptr);
            read_items!(ubyte)(ptr, desc.pod8);
            read_items!(ushort)(ptr, desc.pod16);
            read_items!(uint)(ptr, desc.pod32);
            read_items!(ulong)(ptr, desc.pod64);
            if (desc.is_full_pod)
                return;
            for (int n = 0; n < desc.objects.length; n++) {
                SnapDescriptor.RefMember m = desc.objects[n];
                void** raw = cast(void**)(ptr + m.offset);
                read(raw);
            }
            for (int n = 0; n < desc.arrays.length; n++) {
                SnapDescriptor.ArrayMember m = desc.arrays[n];
                SafePtr ap = SafePtr(m.t, ptr + m.offset);
                size_t len;
                read(&len);
                //NOTE: there's the following problem:
                // strings literals (char[]) are stored on the data segment (there
                // can be other data on the data segment too, but this doesn't
                // really matter here). stuff on the data segment is read-only, so
                // we can't simply copy back memory, even if the copy-back had no
                // effect (if it's constant data, nobody can/will change it).
                // so, there are three choices:
                //   1. try to find out, if the pointer points into the read-only
                //      data segment (not portable, not generally possible)
                //   2. reallocate the array memory (SLOW)
                //   3. compare the data, and only copy if it has changed (slow too)
                //      also, must force reallocation if something has changed
                //      we don't know if it points into the data segment!
                m.t.setLength(ap, len);
                ArrayType.Array arr = m.t.getArray(ap);
                assert (arr.ptr.type is m.item.type);
                assert (arr.length == len);
                //xxx assume the above problem about the data segment only happens
                //    with PODs; but in some cases, this could go wrong
                if (!m.item.is_full_pod) {
                    for (int i = 0; i < len; i++) {
                        readItem(arr.get(i).ptr, m.item);
                    }
                } else if (len > 0) {
                    size_t copy = len * arr.ptr.type.size;
                    assert (snap_read_pos + copy <= snap_data.length);
                    void* psrc = &snap_data[snap_read_pos];
                    assert (arr.ptr.ptr is arr.get(0).ptr);
                    void* pdest = arr.ptr.ptr;
                    if (psrc[0..copy] != pdest[0..copy]) {
                        //force reallocation
                        m.t.assign(ap, m.t.initPtr());
                        m.t.setLength(ap, len);
                        arr = m.t.getArray(ap);
                        pdest = arr.ptr.ptr;
                        pdest[0..copy] = psrc[0..copy];
                    }
                    snap_read_pos += copy;
                }
            }
            for (int n = 0; n < desc.maps.length; n++) {
                SnapDescriptor.MapMember m = desc.maps[n];
                SafePtr mp = SafePtr(m.t, ptr + m.offset);
                //NOTE: keys, that are in the snapshot and weren't removed until
                //      unsnap() is called, don't need to be removed; in these
                //      cases, clearing the map will cause unnecessary memory
                //      allocations; but we still need to get rid of keys that
                //      were added between snap() and unsnap()
                m.t.assign(mp, m.t.initPtr()); //clear map
                size_t len;
                read(&len);
                while (len > 0) {
                    m.t.setKey2(mp,
                        (SafePtr key) {
                            readItem(key.ptr, m.key);
                        },
                        (SafePtr value) {
                            readItem(value.ptr, m.value);
                        }
                    );
                    len--;
                }
            }
            for (int n = 0; n < desc.dgs.length; n++) {
                SnapDescriptor.DgMember m = desc.dgs[n];
                SafePtr dp = SafePtr(m.t, ptr + m.offset);
                Object dg_o;
                ClassMethod dg_m;
                read(&dg_o);
                read(&dg_m);
                //NOTE: because we know that the data is right, we could use an
                //      unchecked way to write the actual delegate...
                if (!mTypes.types.writeDelegate(dp, dg_o, dg_m))
                    assert (false);
            }
        }

        PerfTimer timer = new PerfTimer(true);
        timer.start();

        for (int n = 0; n < snap_objects.length; n++) {
            Object o = snap_objects[n];
            //NOTE: could store the desc with the object array
            auto desc = mTypes.lookupSnapDescriptor(o);
            if (desc) {
                assert (!!o);
                readItem(cast(void*)o, desc);
            }
        }

        timer.stop();
        log("t={}", timer.time);
    }
}
