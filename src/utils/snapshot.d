module utils.snapshot;

import utils.perf;
import utils.reflect.all;
import utils.log;
import utils.misc;
import utils.time;
import utils.hashtable;
import utils.array : Appender;

import str = utils.string;
import memory = tango.core.Memory;

//hack
import utils.mybox;

private LogStruct!("utils.snapshot") log;

/+
xxx TODO:
    arrays are not handled correctly: on snapshot rollback, the current slice
    memory is overwritten with the old contents, even if the slices were set to
    something else (e.g. "snap(); array = somethingelse; unsnap();" =>
    "somethingelse" gets overwritten, instead of the old array)
    solution: compare the slice descriptors on rollback, which means we have to
    store the slice descriptors in memory scanned by the GC...
+/


class SnapDescriptors {
    private {
        Types types;
        SnapDescriptor[Class] class2desc;
        //actually used during writing
        RefHashTable!(ClassInfo, SnapDescriptor) ci2desc;
    }

    this(Types a_types) {
        types = a_types;
        ci2desc = new typeof(ci2desc);
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
        //especially important if there should be transient members
        //(they are unknown/unhandled by the snapshot mechanism)
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
        foreach (c; ck.hierarchy()) {
            foreach (ClassMember m; c.nontransientMembers()) {
                addMember(m.type(), offset + m.offset());
            }
        }
    }

    private void addMember(Type mt, size_t offset) {
        //PODs => just copy
        //function pointers always point to static data, so it's POD
        if ((!!cast(BaseType)mt) || (!!cast(EnumType)mt)
            || (!!cast(FunctionType)mt))
        {
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
        //xxx this is beyond dangerous
        if (mt.typeInfo is typeid(MyBox)) {
            //so assume a box never adds new objects to the object graph
            //further assume the box value never changes (else we had to deal
            //  with the referenced array, MyBox.mDynamicData)
            assert((mt.size % 4) == 0);
            for (int i = 0; i < mt.size / 4; i++) {
                pod32 ~= offset;
                offset += 4;
            }
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
        assert (false, "unknown type: "~mt.toString()
            ~ " inside " ~ type.toString());
    }
}

class Snapshot {
    private {
        SnapDescriptors mTypes;
        ubyte[] snap_data;
        size_t snap_cur; //data position in snap_data
        size_t snap_read_pos; //same, for reading
        Appender!(Object) snap_objects;
        RefHashTable!(Object, bool) snap_objmarked;
    }

    this(SnapDescriptors a_types) {
        assert(!!a_types);
        mTypes = a_types;
        snap_objmarked = new typeof(snap_objmarked);
    }

    //a is the size of the underlying type - for alignment
    //x86 doesn't need alignment, so it's not used yet
    private void reserve(size_t s, size_t a) {
        while (snap_data.length < snap_cur + s) {
            ubyte[] old_data = snap_data;
            snap_data.length = snap_data.length*2;
            if (old_data.ptr !is snap_data.ptr)
                delete old_data;
            if (snap_data.length == 0)
                snap_data.length = 64*1024;
        }
    }

    private void write(T)(T* ptr) {
        size_t s = T.sizeof;
        //align! assume s is power of 2
        //snap_cur = (snap_cur + (s-1)) & ~(s-1);
        reserve(s, T.sizeof);
        T* dest = cast(T*)&snap_data[snap_cur];
        *dest = *ptr;
        snap_cur += s;
    }

    private void write_items(T)(void* base, size_t[] offsets) {
        if (!offsets.length)
            return;

        size_t s = T.sizeof * offsets.length;
        reserve(s, T.sizeof);
        T* dest = cast(T*)&snap_data[snap_cur];
        snap_cur += s;

        foreach (size_t offs; offsets) {
            *dest++ = *cast(T*)(base + offs);
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
        size_t s = T.sizeof * offsets.length;
        assert (snap_read_pos + s <= snap_data.length);
        T* src = cast(T*)&snap_data[snap_read_pos];
        snap_read_pos += s;

        foreach (size_t offs; offsets) {
            *cast(T*)(base + offs) = *src++;
        }
    }

    void snap(Object snapObj) {
        //size_t oldsize = snap_data.length;
        PerfTimer timer = new PerfTimer(true);
        timer.start();

        snap_cur = 0;
        snap_objects[] = null; //clear references for the GC
        snap_objects.length = 0;
        //xxx: memory is never freed
        //on the other hand, we don't want to allocate memory on each snapshot
        snap_objmarked.clear(false);

        int lookups;

        void queueObject(Object o) {
            if (!o)
                return;
            lookups++;
            bool* pmark = snap_objmarked.insert_lookup(o);
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
            foreach (SnapDescriptor.ArrayMember m; desc.arrays) {
                SafePtr ap = SafePtr(m.t, ptr + m.offset);
                ArrayType.Array arr = m.t.getArray(ap);
                assert (arr.ptr.type is m.item.type);
                size_t len = arr.length;
                write(&len);
                if (!m.item.is_full_pod) {
                    //write normally, item-by-item
                    for (int i = 0; i < len; i++) {
                        writeItem(arr.get(i).ptr, m.item);
                    }
                } else {
                    //optimization for cases where this is possible:
                    //write all items in one go
                    size_t copy = len * arr.ptr.type.size;
                    reserve(copy, 1);
                    void* pdest = &snap_data[snap_cur];
                    pdest[0..copy] = arr.ptr.ptr[0..copy];
                    snap_cur += copy;
                }
            }
            foreach (SnapDescriptor.MapMember m; desc.maps) {
                SafePtr mp = SafePtr(m.t, ptr + m.offset);
                size_t len = m.t.getLength(mp);
                write(&len);
                m.t.iterate(mp, (SafePtr key, SafePtr value) {
                    writeItem(key.ptr, m.key);
                    writeItem(value.ptr, m.value);
                });
            }
            foreach (SnapDescriptor.DgMember m; desc.dgs) {
                SafePtr dp = SafePtr(m.t, ptr + m.offset);
                Object dg_o;
                ClassMethod dg_m;
                //we only need the object pointer to follow the object graph
                //dg_m isn't needed, but readDelegate must look it up anyway
                //xxx why is this code duplicated from serialize.d
                if (!dp.readDelegate(dg_o, dg_m)) {
                    mTypes.types.readDelegateError(dp, "snapshot");
                }
                queueObject(dg_o);
                alias void delegate() Dg;
                Dg* dgp = cast(Dg*)dp.ptr;
                write(dgp);
            }
        }

        queueObject(snapObj);

        size_t snap_last_object;
        while (snap_last_object < snap_objects.length) {
            Object o = snap_objects[snap_last_object];
            snap_last_object++;
            auto desc = mTypes.lookupSnapDescriptor(o);
            //if null, maybe an external object (or it is an error)
            if (desc) {
                writeItem(cast(void*)o, desc);
            }
        }

        timer.stop();
        log("snap t={}, oc={}, ls={}, size={} ({})",
            timer.time, snap_objects.length, lookups, str.sizeToHuman(snap_cur),
            str.sizeToHuman(snap_data.length));
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
            arr_loop: foreach (SnapDescriptor.ArrayMember m; desc.arrays) {
                SafePtr ap = SafePtr(m.t, ptr + m.offset);
                size_t len;
                read(&len);
                //NOTE: never write into the data segment, because it may be
                //  write-only, and thus would crash (is the case for string
                //  literals on Linux; windows doesn't write protect because
                //  optlink or some other stupidity)
                ArrayType.Array arr = m.t.getArray(ap);
                if (arr.length != len) {
                    m.t.setLength(ap, len);
                    arr = m.t.getArray(ap);
                }
                assert (arr.ptr.type is m.item.type);
                assert (arr.length == len);
                if (len == 0)
                    continue arr_loop;
                //solve the problem mentioned above
                //only write into GC allocated memory blocks
                //addrOf returns null for unknown pointers, or the start of
                //  the memory block if was allocated by the GC
                bool is_gc_allocated = (arr.length == 0) ||
                    (memory.GC.addrOf(arr.ptr.ptr) !is null);
                void force_realloc() {
                    //force reallocation of the array (also clears it hurr)
                    m.t.assign(ap, m.t.initPtr());
                    m.t.setLength(ap, len);
                    arr = m.t.getArray(ap);
                }
                if (!m.item.is_full_pod) {
                    if (!is_gc_allocated)
                        force_realloc();
                    for (int i = 0; i < len; i++) {
                        readItem(arr.get(i).ptr, m.item);
                    }
                } else {
                    size_t copy = len * arr.ptr.type.size;
                    assert (snap_read_pos + copy <= snap_data.length);
                    void* psrc = &snap_data[snap_read_pos];
                    snap_read_pos += copy;
                    if (!is_gc_allocated) {
                        //for efficiency: if the data wasn't modified, there's
                        //  no reason to realloc and copy back the old data
                        void* pdest = arr.ptr.ptr;
                        if (psrc[0..copy] == pdest[0..copy]) {
                            continue arr_loop;
                        }
                        force_realloc();
                    }
                    void* pdest = arr.ptr.ptr;
                    pdest[0..copy] = psrc[0..copy];
                }
            }
            foreach (SnapDescriptor.MapMember m; desc.maps) {
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
            foreach (SnapDescriptor.DgMember m; desc.dgs) {
                SafePtr dp = SafePtr(m.t, ptr + m.offset);
                alias void delegate() Dg;
                Dg* dgp = cast(Dg*)dp.ptr;
                read(dgp);
            }
        }

        PerfTimer timer = new PerfTimer(true);
        timer.start();

        foreach (Object o; snap_objects[]) {
            assert (!!o);
            //NOTE: could store the desc with the object array
            auto desc = mTypes.lookupSnapDescriptor(o);
            if (desc) {
                readItem(cast(void*)o, desc);
            }
        }

        timer.stop();
        log("restore t={}", timer.time);
    }
}
