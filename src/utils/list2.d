module utils.list2;

import utils.reflection;

struct ListNode(T) {
    List2!(T) owner;
    private ListNode* prev, next;
    T value;
}

/++
 + Doubly linked list.
 + Features:
 +  - unintrusive (e.g. list items don't need to be derived from a ListNode
 +    class, and an object can be in multiple lists)
 +  - optional: avoid additional memory allocations for list nodes; you can
 +    allocate the ListNode struct yourself (e.g. put them into the list item
 +    directly, if the list item is a class)
 +  - O(1) remove() and contains(), if you keep the node pointer around
 + The list also provides a O(1) contains() and a O(n) clear(), which is a bit
 + unusual for linked lists. This is because each ListNode contains an "owner"-
 + field.
 +
 + Serialization: this sucks.
 +/
final class List2(T) {
    alias ListNode!(T) Node;

    private {
        Node head_tail;
    }

    this() {
        head_tail.owner = this;
        head_tail.next = head_tail.prev = &head_tail;
    }

    this (ReflectCtor c) {
        //c.types().registerClass!(Node);
    }

    //return first and last element, or sentinel if list empty
    //that means, if the list is empty, an invalid pointer is returned
    Node* head() {
        return head_tail.next;
    }
    Node* tail() {
        return head_tail.prev;
    }

    bool empty() {
        return head_tail.next is &head_tail;
    }

    //O(n)
    void clear() {
        while (!empty()) {
            remove(head()); //(how cruel)
        }
    }

    //O(1), no checks against double inserts
    //storage: use list node in storage, instead of allocating a new node
    //         (allows for micro-optimizations)
    //         leave it null if you want it simple
    Node* add(T value, Node* storage = null) {
        assert(head_tail.owner is this);
        return insert_before(value, &head_tail, storage);
    }

    alias add insert_tail;

    Node* insert_head(T value, Node* storage = null) {
        return insert_after(value, &head_tail, storage);
    }

    private Node* newnode(T value, Node* storage) {
        Node* n = storage ? storage : (new Node);
        n.value = value;
        n.owner = this;
        return n;
    }

    //O(1), if succ == null (no successor), append
    Node* insert_before(T value, Node* succ, Node* storage = null) {
        if (!succ)
            succ = &head_tail;
        assert(succ.owner is this);
        auto n = newnode(value, storage);
        n.next = succ;
        n.prev = succ.prev;
        n.next.prev = n;
        n.prev.next = n;
        return n;
    }

    //O(1), if pred == null (no predecessor), like insert_head
    Node* insert_after(T value, Node* pred, Node* storage = null) {
        if (!pred)
            pred = &head_tail;
        assert(pred.owner is this);
        auto n = newnode(value, storage);
        n.prev = pred;
        n.next = pred.next;
        n.next.prev = n;
        n.prev.next = n;
        return n;
    }

    //O(n)
    Node* find(T value) {
        Node* cur = head_tail.next;
        while (cur !is &head_tail) {
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
    bool contains(Node* node) {
        return node && node.owner is this;
    }

    //O(n)
    void remove(T value) {
        Node* n = find(value);
        if (!n)
            throw new Exception("not in list");
        remove(n);
    }

    //O(1)
    void remove(Node* node) {
        if (node.owner !is this)
            throw new Exception("not in list (2)");
        assert (!!node);
        assert (node !is &head_tail);
        node.next.prev = node.prev;
        node.prev.next = node.next;
        node.next = node.prev = null;
        node.owner = null;
    }

    //remove all items from 'this' and append them to 'other'
    //O(n)
    void move_to_list(List2 other) {
        Node* cur = head_tail.next;
        while (cur !is &head_tail) {
            Node* next = cur.next;
            remove(cur);
            other.add(cur.value, cur);
            cur = next;
        }
    }

    int opApply(int delegate(inout T) del) {
        Node* cur = head_tail.next;
        while (cur !is &head_tail) {
            //cache next element, as cur could get invalid during the call
            Node* nextTmp = cur.next;
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
            Node* current;
        }

        static Iterator opCall(List2 a_owner) {
            assert (!!a_owner);
            Iterator iter;
            iter.owner = a_owner;
            iter.current = &a_owner.head_tail;
            iter.head();
            return iter;
        }

        //points to an actual element
        bool valid() {
            assert (!!current);
            return current !is &owner.head_tail;
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
            Node* r = current;
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

    //-- trivial, but sometimes useful functions

    bool hasAtLeast(int n) {
        return count() >= n;
    }

    int count() {
        int r;
        foreach (_; this) {
            r++;
        }
        return r;
    }

    //"don't ask" functions
    Node* ring_next(Node* cur) {
        assert(cur.owner is this);
        cur = cur.next;
        if (cur is &head_tail)
            cur = cur.next;
        return cur;
    }
    Node* ring_prev(Node* cur) {
        assert(cur.owner is this);
        cur = cur.prev;
        if (cur is &head_tail)
            cur = cur.prev;
        return cur;
    }
    T next_value(Node* cur) {
        //return T.init on list end (sentinel contains it)
        return cur.next.value;
    }
}
