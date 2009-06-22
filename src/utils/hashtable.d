//stolen from minid/hash.d
//modified in quite some ways (reformatting, functional changes, removing
//  minid-isms like Allocator, removing string mixins (hey wtf?), some comments)
//  (license header left intact because I must? IANAL)

/*
License:
Copyright (c) 2008 Jarrett Billingsley

This software is provided 'as-is', without any express or implied warranty.
In no event will the authors be held liable for any damages arising from the
use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it freely,
subject to the following restrictions:

    1. The origin of this software must not be misrepresented; you must not
        claim that you wrote the original software. If you use this software in a
        product, an acknowledgment in the product documentation would be
        appreciated but is not required.

    2. Altered source versions must be plainly marked as such, and must not
        be misrepresented as being the original software.

    3. This notice may not be removed or altered from any source distribution.
*/

module utils.hashtable;

//this hashmap uses 'is' instead of '==' to do comparisions
//allows only classes as key
//(original implementation allowed anything and used '==')
//if you want a general hashtable impl., use tango.util.container.HashMap
final class RefHashTable(K, V) {
    //could allow pointers as index too; not sure about structs; arrays are out
    static assert(is(K == class));

    private {
        struct Node {
            K key;
            V value;
            Node* next;
            bool used;
        }

        Node[] mNodes;
        uint mHashMask;
        Node* mColBucket;
        size_t mSize;
    }

    this() {
    }

    private void outofbounds() {
        int[int] x;
        int y = x[0];
        assert(false);
    }

    private uint gethash(K k) {
        //address as hash
        //would fail if D had a moving garbage collector
        //note that Object.toHash() returns the same
        return cast(size_t)cast(void*)k;
    }

    void prealloc(size_t size) {
        if(size <= mNodes.length)
            return;

        size_t newSize = 4;
        for(; newSize < size; newSize <<= 1) {}
        resizeArray(newSize);
    }

    //overwrite old value if already exists
    void insert(K key, V value) {
        assert(!!key, "no null keys permitted");

        uint hash = gethash(key);

        if(auto val = lookup(key, hash)) {
            *val = value;
            return;
        }

        auto colBucket = getColBucket();

        if(colBucket is null) {
            rehash();
            colBucket = getColBucket();
            assert(colBucket !is null);
        }

        auto mainPosNode = &mNodes[hash & mHashMask];

        if(mainPosNode.used) {
            auto otherNode = &mNodes[gethash(mainPosNode.key) & mHashMask];

            if(otherNode is mainPosNode) {
                // other node is the head of its list, defer to it.
                colBucket.next = mainPosNode.next;
                mainPosNode.next = colBucket;
                mainPosNode = colBucket;
            } else {
                // other node is in the middle of a list, push it out.
                while(otherNode.next !is mainPosNode)
                        otherNode = otherNode.next;

                otherNode.next = colBucket;
                *colBucket = *mainPosNode;
                mainPosNode.next = null;
            }
        } else {
            mainPosNode.next = null;
        }

        mainPosNode.key = key;
        mainPosNode.used = true;
        mSize++;

        mainPosNode.value = value;
    }

    bool remove(K key) {
        if (!key) //?
            return false;

        uint hash = gethash(key);
        auto n = &mNodes[hash & mHashMask];

        if(!n.used)
            return false;

        if (n.key is key) {
            // Removing head of list.
            if (n.next is null) {
                // Only item in the list.
                markUnused(n);
            } else {
                // Other items.  Have to move the next item into where the head used to be.
                auto next = n.next;
                *n = *next;
                markUnused(next);
            }

            return true;
        } else {
            for(; n.next !is null && n.next.used; n = n.next) {
                if (n.next.key is key) {
                    // Removing from the middle or end of the list.
                    markUnused(n.next);
                    n.next = n.next.next;
                    return true;
                }
            }

            // Nonexistent key.
            return false;
        }
    }

    V* lookup(K key) {
        if(mNodes.length == 0)
            return null;
        if (!key) //?
            return null;

        return lookup(key, gethash(key));
    }

    private V* lookup(K key, uint hash) {
        if(mNodes.length == 0)
            return null;

        for(auto n = &mNodes[hash & mHashMask]; n !is null && n.used; n = n.next) {
            if(n.key is key)
                return &n.value;
        }

        return null;
    }

    private bool next(ref size_t idx, ref K* key, ref V* val) {
        for(; idx < mNodes.length; idx++) {
            if(mNodes[idx].used) {
                key = &mNodes[idx].key;
                val = &mNodes[idx].value;
                idx++;
                return true;
            }
        }

        return false;
    }

    int opApply(int delegate(ref K, ref V) dg) {
        foreach(ref node; mNodes) {
            if(node.used)
                if(auto result = dg(node.key, node.value))
                    return result;
        }

        return 0;
    }

    int opApply(int delegate(ref V) dg) {
        foreach(ref node; mNodes) {
            if(node.used)
                if(auto result = dg(node.value))
                    return result;
        }

        return 0;
    }

    size_t length() {
        return mSize;
    }

    void minimize() {
        if(mSize == 0) {
            clear();
        } else {
            size_t newSize = 4;
            for(; newSize < mSize; newSize <<= 1) {}
            resizeArray(newSize);
        }
    }

    void clear() {
        mNodes = null;
        mHashMask = 0;
        mColBucket = null;
        mSize = 0;
    }

    private void markUnused(Node* n) {
        assert(n >= mNodes.ptr && n < mNodes.ptr + mNodes.length);

        n.used = false;

        if(n < mColBucket)
            mColBucket = n;

        mSize--;
    }

    void rehash() {
        if(mNodes.length != 0) {
            resizeArray(mNodes.length * 2);
        } else {
            resizeArray(4);
        }
    }

    private void resizeArray(size_t newSize) {
        auto oldNodes = mNodes;

        mNodes = new Node[newSize];
        mHashMask = mNodes.length - 1;
        mColBucket = mNodes.ptr;
        mSize = 0;

        foreach(ref node; oldNodes) {
            if(node.used)
                insert(node.key, node.value);
        }

        delete oldNodes;
    }

    private Node* getColBucket() {
        for(auto end = mNodes.ptr + mNodes.length; mColBucket < end; mColBucket++)
            if(mColBucket.used == false)
                return mColBucket;

        return null;
    }

    //AA compatibility
    V opIndex(K k) {
        V* v = lookup(k);
        if (!v) {
            outofbounds();
        }
        return *v;
    }
    void opIndexAssign(V value, K key) {
        insert(key, value);
    }
    V* opIn_r(K k) {
        return lookup(k);
    }
    private T[] getvalues(T, bool keys)() {
        T[] res;
        res.length = length();
        int idx = 0;
        foreach(ref node; mNodes) {
            if(node.used) {
                T* v = &res[idx];
                idx++;
                static if (keys) {
                    *v = node.key;
                } else {
                    *v = node.value;
                }
            }
        }
        return res;
    }
    K[] keys() {
        return getvalues!(K, true)();
    }
    V[] values() {
        return getvalues!(V, false)();
    }
}
