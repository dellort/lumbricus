//drop-in replacement for the horrible mylist.d; it's not necessarily less
// horrible, but it causes less problems for serialization
//it's kept as simple as possible
//except for the support of O(1) remove()/contains()
module utils.list2;

//xxx: I do not know why, but referencing this as List2(T).Node causes linker
//     errors... dmd is a goddamn piece of garbage, I hope LDC is useable soon
//Note that any use of this object from "outside" is an optimization anyway.
class ListNode {
    private Object owner;
}

class List2(T) {
    Node head_tail;

    static class Node : ListNode {
        private Node prev, next;
        T value;
    }

    this() {
        head_tail = new Node();
        head_tail.owner = this;
        clear();
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
        Node n = new Node();
        n.value = value;
        n.owner = this;
        n.next = head_tail;
        n.prev = head_tail.prev;
        n.next.prev = n;
        n.prev.next = n;
        return n;
    }

    alias add insert_tail;

    Node insert_head(T value) {
        Node n = new Node();
        n.value = value;
        n.owner = this;
        n.prev = head_tail;
        n.next = head_tail.next;
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
            throw new Exception("not in list");
        Node n = cast(Node)node;
        assert (!!n);
        n.next.prev = n.prev;
        n.prev.next = n.next;
        n.owner = null;
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
}
