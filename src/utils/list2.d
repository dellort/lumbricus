module utils.list2;

import utils.reflection;


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

struct ObjListNode(T) {
    private T prev, next;
    private Object owner;
}

//create with item type, and name of the ObjListNode member
//Note: the member name is checked at compile-time
//xxx T : Object doesn't work (does not match template declaration etc.)
final class ObjectList(T, char[] member) {
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
        //verify_not_contained(item);
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
        //verify_list();
    }

    //O(1)
    void insert_after(T item, T pred) {
        //verify_not_contained(item);
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
        //verify_list();
    }

    debug {
        void verify_not_contained(T item) {
            if (head_item) {
                T cur = head_item;
                do {
                    assert(cur !is item);
                    cur = node(cur).next;
                } while (cur !is head_item);
            }
        }

        void verify_list() {
            int mc = 0;
            if (head_item) {
                T cur = head_item;
                do {
                    assert(!!cur);
                    Node* ncur = node(cur);
                    assert(ncur.owner is this);
                    assert(!!ncur.next);
                    assert(!!ncur.prev);
                    Node* nnext = node(ncur.next);
                    assert(nnext.owner is this);
                    assert(nnext.prev is cur);
                    Node* nprev = node(ncur.prev);
                    assert(nprev.owner is this);
                    assert(nprev.next is cur);
                    mc++;
                    assert(mc <= mCount, "loop or too many elements");
                    cur = node(cur).next;
                } while (cur !is head_item);
            }
            assert(mCount == mc);
        }
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
