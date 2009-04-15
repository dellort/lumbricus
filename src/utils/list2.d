//drop-in replacement for the horrible mylist.d; it's not necessarily less
// horrible, but it causes less problems for serialization
//it's kept as simple as possible
//except for the support of O(1) remove()/contains()
module utils.list2;

import utils.reflection;

//xxx: I do not know why, but referencing this as List2(T).Node causes linker
//     errors... dmd is a goddamn piece of garbage, I hope LDC is useable soon
//Note that any use of this object from "outside" is an optimization anyway.
class ListNode {
    private Object owner;
    this() {
    }
    this (ReflectCtor c) {
    }
}

class List2(T) {
    Node head_tail;

    static class Node : ListNode {
        private Node prev, next;
        T value;
        this() {
        }
        this (ReflectCtor c) {
        }
    }

    this() {
        head_tail = new Node();
        head_tail.owner = this;
        clear();
    }

    this (ReflectCtor c) {
        c.types().registerClass!(Node);
    }

    //O(n)
    void clear() {
        Node cur = head_tail.next;
        while (cur && cur !is head_tail) {
            cur.owner = null;
        }
        head_tail.next = head_tail.prev = head_tail;
    }

    //O(1), no checks against double inserts
    Node add(T value) {
        return insert_before(value, head_tail);
    }

    //uh
    void addNode(ListNode node) {
        auto n = cast(Node)node;
        assert (!!n);
        assert (!n.owner);
        n.owner = this;
        n.next = head_tail;
        n.prev = head_tail.prev;
        n.next.prev = n;
        n.prev.next = n;
    }

    alias add insert_tail;

    Node insert_head(T value) {
        return insert_after(value, head_tail);
    }

    //O(1), if succ == null (no successor), append
    Node insert_before(T value, ListNode succ) {
        Node succn = cast(Node)succ;
        if (!succn)
            succn = head_tail;
        assert(succn.owner is this);
        Node n = new Node();
        n.value = value;
        n.owner = this;
        n.next = succn;
        n.prev = succn.prev;
        n.next.prev = n;
        n.prev.next = n;
        return n;
    }

    //O(1), if pred == null (no predecessor), like insert_head
    Node insert_after(T value, ListNode pred) {
        Node predn = cast(Node)pred;
        if (!predn)
            predn = head_tail;
        assert(predn.owner is this);
        Node n = new Node();
        n.value = value;
        n.owner = this;
        n.prev = predn;
        n.next = predn.next;
        n.next.prev = n;
        n.prev.next = n;
        return n;
    }

    //O(n)
    Node find(T value) {
        Node cur = head_tail.next;
        while (cur !is head_tail) {
            if (cur.value is value)
                return cur;
            cur = cur.next;
        }
        return null;
    }

    //O(n)
    bool contains(T value) {
        return !!find(value);
    }

    //O(1)
    //null as argument is supported and returns false
    bool contains(ListNode node) {
        return node && node.owner is this;
    }

    //O(n)
    void remove(T value) {
        Node n = find(value);
        if (!n)
            throw new Exception("not in list");
        remove(n);
    }

    //O(1)
    void remove(ListNode node) {
        if (node.owner !is this)
            throw new Exception("not in list (2)");
        Node n = cast(Node)node;
        assert (!!n);
        n.next.prev = n.prev;
        n.prev.next = n.next;
        n.owner = null;
    }

    //O(n)
    void move_to_list(List2 other) {
        Node cur = head_tail.next;
        while (cur !is head_tail) {
            Node next = cur.next;
            remove(cur);
            other.addNode(cur);
            cur = next;
        }
    }

    int opApply(int delegate(inout T) del) {
        Node cur = head_tail.next;
        while (cur !is head_tail) {
            //cache next element, as cur could get invalid during the call
            Node nextTmp = cur.next;
            int res = del(cur.value);
            if (res)
                return res;
            cur = nextTmp;
        }
        return 0;
    }

    //cheap but functional; it's a struct, so memory managment isn't an issue
    //the iterator always points to either an element in the list, or to "null"
    //"null" has the first element as next element, and the last as previous
    //(and actually, "null" points to head_tail)
    //if the element, that the iterator points to, is removed, undefined
    //behaviour results (except Iterator.remove); all other modifcations are ok
    struct Iterator {
        private {
            List2 owner;
            Node current;
        }

        static Iterator opCall(List2 a_owner) {
            assert (!!a_owner);
            Iterator iter;
            iter.owner = a_owner;
            iter.current = a_owner.head_tail;
            iter.head();
            return iter;
        }

        //points to an actual element
        bool valid() {
            assert (!!current);
            return current !is owner.head_tail;
        }

        T value() {
            if (!valid())
                throw new Exception("value() called for null element");
            return current.value;
        }

        //return T.init if iterator points to null element
        T peek() {
            if (!valid()) {
                T t;
                return t; //shouldn't T.init work here
            }
            return current.value;
        }

        //remove the current element (illegal if !valid())
        //after this, the iterator points to the previous element, or null, if
        //this element was the first element in the list
        void remove() {
            assert (!!current);
            if (!valid())
                throw new Exception("trying to remove null element");
            Node r = current;
            current = r.prev;
            owner.remove(r);
        }

        //seek to first element
        void head() {
            assert (!!owner);
            current = owner.head_tail.next;
        }

        void next() {
            assert (!!current);
            current = current.next;
        }
    }

    //iterator will point to first element (or null if list empty)
    Iterator iterator() {
        return Iterator(this);
    }
}
