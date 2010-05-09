module physics.bih;

import physics.broadphase;
import physics.contact;
import utils.misc;
import utils.rect2;
import utils.vector2;

//paper: http://ainc.de/Research/BIH.pdf
//adapted from rayd
class BPBIH : BroadPhase {
    private {
        BIH_Node[] mStorage;
        uint mNodeAlloc; //mStorage[mNodeAlloc] is the next free BIH node
        PhysicObject[] mItems;
        Rect2f mBB;
    }

    //tuneable parameter: max. items per BIH leaf node
    const cMaxItemsPerNode = 8;

    struct BIH_Node {
        //right-shift to get index value
        const uint INDEX_SHIFT = 2;
        //bits to encode axis
        // bit0 bit1 Meaning
        //  0    0    x
        //  1    0    y
        //  ?    1    leaf node
        //could encode leaf node as all-index-bits-set to save a single bit
        //xxx: does encoding the axis make sense in 2D, or should it just
        //     alternate between x and y?
        const uint AXIS_MASK = 1;
        const uint LEAF_NODE = 2;

        //first INDEX_SHIFT bits: axis flags, after that, the child BIH index
        //if it's not a leaf node, child_index + 0 is the "left" sub node, and
        //  child_index + 1 the "right" sub node
        uint index_flags;

        union {
            struct { //leaf node
                uint item;  //index of item
                uint count; //number of items
            }
            float[2] clip; //internal node
        }
    }

    this(CollideFineDg col) {
        super(col);
    }

    private void build(Rect2f bb, uint node_index, uint index_start,
        uint index_end, uint max_depth)
    {
        /+ fails when bb uses split instead of left/right
        debug { //slow debug test: all objects within box?
            foreach (o; mItems[index_start .. index_end]) {
                assert(bb.contains(o.bb));
            }
        }
        +/

        BIH_Node* node = &mStorage[node_index];
        uint subcount = index_end - index_start;

        if (max_depth == 0 || subcount <= cMaxItemsPerNode) {
            //leaf node
            node.index_flags = BIH_Node.LEAF_NODE;
            node.item = index_start;
            node.count = subcount;
            return;
        }

        max_depth--;

        //split along longest axis
        //uint axis = (bb.p2.x - bb.p1.x) < (bb.p2.y - bb.p1.y) ? 1 : 0;
        uint axis = max_depth % 2;
        //splitting positions (left is top when axis=1 etc.)
        float left = bb.p1[axis];
        float right = bb.p2[axis];
        float split = left + (right - left) / 2.0;

        //group objects for the first or second split planes
        //in the end, [index_start...split_index] are objects on the side of
        //  the first split plane, and [split_index..index_end] on the second
        //this is like the divide/split step in quicksort
        uint index_split = index_start;
        for (uint i = index_start; i < index_end; i++) {
            assert(i >= index_split);
            if (objIsLeft(mItems[i], axis, split, left, right)) {
                swap(mItems[i], mItems[index_split]);
                index_split++;
            }
        }

        debug {
            float old_left = left;
            float old_right = right;
            for (uint i = index_start; i < index_split; i++) {
                assert((objIsLeft(mItems[i], axis, split, left, right)));
            }
            assert(old_left == left && old_right == right);
            for (uint i = index_split; i < index_end; i++) {
                assert(!(objIsLeft(mItems[i], axis, split, left, right)));
            }
            assert(old_left == left && old_right == right);
        }

        //adjust BBs for the sub nodes
        //orignal code uses split instead of left/right for stability or so
        //or maybe it's for even axis selection and splitting
        Rect2f bb1 = bb, bb2 = bb;
        bb1.p2[axis] = split;
        bb2.p1[axis] = split;
        //bb1.p2[axis] = left;
        //bb2.p1[axis] = right;

        uint children = mNodeAlloc;
        mNodeAlloc += 2;
        assert(mNodeAlloc <= mStorage.length);

        node.index_flags = (children << BIH_Node.INDEX_SHIFT) | axis;
        node.clip[0] = left;
        node.clip[1] = right;

        build(bb1, children, index_start, index_split, max_depth);
        build(bb2, children + 1, index_split, index_end, max_depth);
    }

    //see if object belongs to left (true) or right side (false)
    //the split plane is adjusted, so that e.g. obj.aabb.p2.x <= left (on true)
    private static bool objIsLeft(PhysicObject obj, uint axis, float split,
        ref float left, ref float right)
    {
        auto bb_min = obj.bb.p1[axis];
        auto bb_max = obj.bb.p2[axis];

        assert(bb_min <= bb_max);

        if (bb_max <= split) {
            left = max(left, bb_max);
            return true;
        } else if (bb_min >= split) {
            right = min(right, bb_min);
            return false;
        } else {
            //crosses both split planes, pick the best
            if (split - bb_min > bb_max - split) {
                left = max(left, bb_max);
                return true;
            } else {
                right = min(right, bb_min);
                return false;
            }
        }
    }

    void collide(PhysicObject[] shapes, CollideDelegate contactHandler) {
        //xxx replace bounding box by static world bounds, or so
        mBB = Rect2f.Abnormal();
        foreach (o; shapes) {
            mBB.extend(o.bb);
        }
        if (shapes.length == 0)
            mBB = Rect2f(0,0,0,0);
        //build BIH tree
        mItems = shapes;
        mStorage.length = shapes.length * 2 + 1; //conservative est. max size
        mNodeAlloc = 1; //node 0 is root
        build(mBB, 0, 0, mItems.length, uint.max);
        //collide
        foreach (uint index, PhysicObject o; mItems) {
            void recurse(BIH_Node* node, Rect2f bb) {
                if (node.index_flags & BIH_Node.LEAF_NODE) {
                    auto objs = mItems[node.item .. node.item + node.count];
                    foreach (PhysicObject o2; objs) {
                        if (o !is o2)
                            collideFine(o, o2, contactHandler);
                    }
                    return;
                }

                //not a leaf node
                uint axis = node.index_flags & BIH_Node.AXIS_MASK;
                uint next = node.index_flags >> BIH_Node.INDEX_SHIFT;

                Rect2f bb1 = bb, bb2 = bb;
                bb1.p2[axis] = node.clip[0];
                bb2.p1[axis] = node.clip[1];

                if (o.bb.intersects(bb1)) {
                    recurse(&mStorage[next+0], bb1);
                }
                if (o.bb.intersects(bb2)) {
                    recurse(&mStorage[next+1], bb2);
                }
            }
            recurse(&mStorage[0], mBB);
        }
    }
}

//similar to what the Chipmunk physics engine does ("cpSpaceHash")
//it's like a sparse grid of tiles
//objects with a large range of sizes or sizes very different from quantization
//  parameter make it less efficient
class BPTileHash : BroadPhase {
    private {
        struct Node {
            PhysicObject item;
            Node* next;
        }
        Node*[] mHash;
        uint mInUse;
        //quantization: size of the grid tile
        float mQuant = 5.0f;
        //xxx: use some sort of allocator instead
        Node[] mNodeStorage;
        uint mNodeAlloc;
        uint mQueryTimeStamp;
    }

    this(CollideFineDg col) {
        super(col);
        mHash.length = 10000;
    }

    //alloc uninitialized Node
    private Node* alloc_node() {
        mNodeAlloc++;
        if (mNodeStorage.length < mNodeAlloc)
            mNodeStorage.length = mNodeAlloc * 2;
        return &mNodeStorage[mNodeAlloc - 1];
    }

    //the Chipmunk source say that floor/ceil is a bottleneck, and implementing
    //  the functions yourself is better - believe them blindly
    private static int floor_int(float n) {
        int ni = cast(int)n;
        return (n < 0f && ni != n) ? ni - 1 : ni;
    }

    //return grid coordinates for the bounding box
    //the returned bottom/left coordinates are exclusive
    private Rect2i quantize(Rect2f bb) {
        Rect2i ret = void;
        ret.p1.x = floor_int(bb.p1.x / mQuant);
        ret.p1.y = floor_int(bb.p1.y / mQuant);
        ret.p2.x = floor_int(bb.p2.x / mQuant) + 1;
        ret.p2.y = floor_int(bb.p2.y / mQuant) + 1;
        return ret;
    }

    //return the pointer to the Node* entry in mHash for these coords
    private Node** hash_ptr(int x, int y) {
        //we need to hash (x, y) somehow, and fast
        //funfact: I know not enough about hash functions
        uint hash = x*2353135289 ^ y*5347923577;
        return &mHash[hash % mHash.length]; //unsigned for non-negative indices
    }

    private void add(PhysicObject item) {
        Rect2i q_bb = quantize(item.bb);
        for (int y = q_bb.p1.y; y < q_bb.p2.y; y++) {
            for (int x = q_bb.p1.x; x < q_bb.p2.x; x++) {
                Node* node = alloc_node();
                node.item = item;
                //insert
                Node** pnode = hash_ptr(x, y);
                node.next = *pnode;
                *pnode = node;
                //slot was unused
                if (!node.next)
                    mInUse++;
            }
        }
    }

    private void clear() {
        mHash[] = null;
        mInUse = 0;
        mNodeAlloc = 0;
    }

    void collide(PhysicObject[] shapes, CollideDelegate contactHandler) {
        //rebuild all
        //updates of individual objects would be possible (but if there are many
        //  objects, most objects are moving around, and would cause roughly the
        //  same work?)
        clear();
        foreach (o; shapes) {
            add(o);
        }
        //collide
        foreach (o; shapes) {
            mQueryTimeStamp++;
            Rect2i q_bb = quantize(o.bb);
            for (int y = q_bb.p1.y; y < q_bb.p2.y; y++) {
                for (int x = q_bb.p1.x; x < q_bb.p2.x; x++) {
                    Node* node = *hash_ptr(x, y);
                    while (node) {
                        PhysicObject o2 = node.item;
                        //timestamp stuff => never report a pair twice in the
                        //  same query
                        if (o2 !is o
                            && o2.broadphaseTimeStamp != mQueryTimeStamp)
                        {
                            o2.broadphaseTimeStamp = mQueryTimeStamp;
                            collideFine(o, o2, contactHandler);
                        }
                        node = node.next;
                    }
                }
            }
        }
        //Trace.formatln("in use: {}, nodes: {}", mInUse, mNodeAlloc);
    }
}
