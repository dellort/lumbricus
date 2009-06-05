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


//The 3rd iteration of our list class follows...
//This is my approach to write a serializable, doubly-linked list with all
//  the features listed above, but no exposed pointers so serialization is
//  not an issue.
//Another feature is that the listnode name is only needed once at declaration,
//  and is transparent to the user after that.
//O(1) insert, contains, remove, count without having to mess with node pointers
//Drawbacks: - might be a little slower because of more pointer calculations
//           - works only for class-type items
//           - and the worst: ObjListNode member has to be public (but all
//             struct members are private, so you can't cause much mayhem)
//If you don't need serialization, use List2 instead

struct ObjListNode(T) {
    private T prev, next;
    private Object owner;
}

//create with item type, and name of the ObjListNode member
//Note: the member name is checked at compile-time
//xxx T : Object doesn't work (does not match template declaration etc.)
class ObjectList(T, char[] member) {
    //static assert(is(T == class));

    alias ObjListNode!(T) Node;

    //some string-mixin magic, so we can access the ObjListNode embedded in the
    //  item class
    private Node* node(T inst) {
        const getnode = `&inst.`~member;
        //if something is wrong, try to output a nice error message
        static if (!is(typeof(mixin(getnode)) == Node*)) {
            static assert(false, typeof(this).stringof ~ ": type '"~T.stringof
                ~"' doesn't have member '"~member~"', or is not of type "
                ~Node.stringof);
        }
        return mixin(getnode);
    }

    private {
        //the first item of the list
        //this is an actual list item (in contrast to List2)
        T head_item;
        //item count is stored, for O(1) count()
        int mCount;
    }

    this() {
    }
    this (ReflectCtor c) {
    }

    T head() {
        return head_item;
    }
    T tail() {
        if (head_item)
            return node(head_item).prev;
        return null;
    }

    bool empty() {
        return !head_item;
    }

    //O(n)
    void clear() {
        while (!empty()) {
            remove(head()); //(how cruel)
        }
    }

    void add(T item) {
        insert_before(item, null);
    }
    alias add insert_tail;

    void insert_head(T item) {
        insert_before(item, head_item);
    }

    //O(1)
    void insert_before(T item, T succ) {
        assert(!!item);
        assert(!!head_item || !succ);
        if (succ is head_item)  //also catches head_item == null
            head_item = item; //before head -> new item is new head
        if (!succ)
            succ = head_item; //no successor -> insert before head (append)
        Node* n = node(item);
        assert(!n.owner);
        n.owner = this;
        Node* succn = node(succ);
        assert(succn.owner is this);
        n.next = succ;
        n.prev = succn.prev;
        node(n.next).prev = item;
        node(n.prev).next = item;
        mCount++;
    }

    //O(1)
    void insert_after(T item, T pred) {
        if (!pred || !head_item) {
            insert_before(item, head_item);
            return;
        }
        assert(!!item && !!pred);
        Node* n = node(item);
        assert(!n.owner);
        n.owner = this;
        Node* predn = node(pred);
        assert(predn.owner is this);
        n.prev = pred;
        n.next = predn.next;
        node(n.next).prev = item;
        node(n.prev).next = item;
        mCount++;
    }

    //O(1)
    bool contains(T item) {
        return item && node(item).owner is this;
    }

    //O(1)
    void remove(T item) {
        Node* n = node(item);
        if (n.owner !is this)
            throw new Exception("not in list");
        if (item is head_item) {
            if (n.next is item)
                head_item = null;
            else
                head_item = n.next;
        }
        node(n.next).prev = n.prev;
        node(n.prev).next = n.next;
        n.next = n.prev = null;
        n.owner = null;
        mCount--;
    }

    //O(n)
    int opApply(int delegate(inout T) del) {
        if (!head_item)
            return 0;
        T cur = head_item;
        T headTmp;
        do {
            //cache next element, as cur could get invalid during the call
            T nextTmp = node(cur).next;
            headTmp = head_item;
            int res = del(cur);
            if (res)
                return res;
            cur = nextTmp;
        } while (cur !is headTmp);
        return 0;
    }

    //O(1)
    bool hasAtLeast(int n) {
        return mCount >= n;
    }

    //O(1)
    int count() {
        return mCount;
    }

    T ring_next(T cur) {
        //nothing special here, head() is just another list item
        Node* n = node(cur);
        assert(n.owner is this);
        return n.next;
    }
    T ring_prev(T cur) {
        Node* n = node(cur);
        assert(n.owner is this);
        return n.prev;
    }
    //returns null if cur is the last item
    T next(T cur) {
        Node* n = node(cur);
        assert(n.owner is this);
        if (n.next is head_item)
            return null;
        return n.next;
    }
    //return null if cur is the head
    T prev(T cur) {
        Node* n = node(cur);
        assert(n.owner is this);
        if (cur is head_item)
            return null;
        return n.prev;
    }
}

unittest {
    class TestItem {
        int val;
        ObjListNode!(typeof(this)) tl_node;
        this(int i) {
            val = i;
        }
    }

    ObjectList!(TestItem, "tl_node") testList;
    testList = new typeof(testList);

    auto i1 = new TestItem(1);
    auto i2 = new TestItem(2);
    auto i3 = new TestItem(3);
    testList.add(i1);
    testList.insert_after(i2, i1);
    testList.insert_after(i3, i2);
    assert(testList.head is i1);
    assert(i1.tl_node.next is i2);
    assert(i2.tl_node.next is i3);
    assert(i3.tl_node.next is i1);
    assert(i1.tl_node.prev is i3);
    assert(i2.tl_node.prev is i1);
    assert(i3.tl_node.prev is i2);
    testList.remove(i1);
    assert(i2.tl_node.next is i3);
    assert(i3.tl_node.next is i2);
    assert(i1.tl_node.owner is null);
    assert(!testList.contains(i1));
    assert(testList.head is i2);
    testList.remove(i2);
    testList.remove(i3);
    assert(testList.empty());
    testList.add(i1);
    testList.add(i2);
    testList.add(i3);
    int i = 0;
    foreach (it; testList) {
        i++;
        assert(it.val == i);
        testList.remove(it);
    }
    assert(testList.empty());
    testList.add(i1);
    testList.add(i2);
    testList.clear();
    assert(testList.empty());
}
