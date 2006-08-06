module mylist;

//With this doubly linked list, I wanted to clone the OpenSolaris list.h
//interface. (Note: no code was copied from there)
//Sadly, it got a bit hacky and looks ugly.

private struct ListNode_T(T) {
    private ListNode_T* next_node;
    private ListNode_T* prev_node;
    private T data; //redundant in C, needed in D (because of the GC)
    //maybe the owner field should be removed for "release" code
    private List!(T) owner = null;
}

//yeah this is ugly

//this is to make the use of the List more typesafe
//(user is forced to pass a valid offset to the constructor of List)
public struct ListNodeOffset(T) {
    //The mixin's members seems to be under the same visibility rules like the
    //code where it has been mixed in. So that mixed in code (in ListNodeMixin)
    //couldn't access this struct's member if the members hwere private.
    //this sucks and I consider this to be a D design weakage
    //so make it (sadly) public and uglify it a bit
    public size_t ___whohahahaha_uglify____offset;
}

public template ListNodeMixin() {
    //interestingly enough, it can mix in the module-private type ListNode_T!
    private ListNode_T!(typeof(this)) __uglify_listnode;
    //the following method must be called by the user on List construction
    static ListNodeOffset!(typeof(this)) getListNodeOffset() {
        ListNodeOffset!(typeof(this)) t;
        t.___whohahahaha_uglify____offset = __uglify_listnode.offsetof;
        return t;
    }
}

/// Doubly linked list, see unittest on how to use it.
/// T must be a class or a pointer to a struct. T must also use the
/// ListNodeMixin, which contains the list node. There can be several such
/// mixins, so T can be in more than one List.
/// This List methods always take and return Ts directly (i.e. object
/// references or pointers to structs).
/// The List is initialized by the return value of the class' or struct's
/// ListNodeMixin.getListNodeOffset() function, i.e.
///     new List!(Type)(Type.anyname.getListNodeOffset()), where Type must have
/// a "mixin ListNodeMixin anyname;" declaration.
/// From the interface, it's a usual list with an head and a tail, but
/// internally, it's organized as ring.
/// The ListNodeT.owner field makes .clear() O(n) and .contains() O(1).
public class List(T) {
    private size_t object_node_offset;
    private alias ListNode_T!(T) ListNodeT;
    private ListNodeT* head_tail;
    
    //dirty C-like tricks to get T from a list node and reverse
    private T node_to_object(ListNodeT* node) {
        assert(node !is null);
        return cast(T)(cast(void*)node - object_node_offset);
    }
    private ListNodeT* object_to_node(T obj) {
        assert(obj !is null); //don't pass nulls to the List functions
        return cast(ListNodeT*)(cast(void*)obj + object_node_offset);
    }
    
    private void assert_own_node(ListNodeT* node) {
        assert(node !is null);
        assert(node.owner is this);
    }
    
    /// offset must be obtained by T's ListNodeMixin.getListNodeOffset()
    public this(ListNodeOffset!(T) offset) {
        object_node_offset = offset.___whohahahaha_uglify____offset;
        head_tail = null;
    }
    
    /// return the next/previous list item relative to "obj"
    /// "obj" must be !is null and also must be contained by the list
    /// returns null if the end of the list is reached
    public T next(T obj) {
        ListNodeT* node = object_to_node(obj);
        assert_own_node(node);
        node = node.next_node;
        if (node is head_tail)
            return null;
        return node_to_object(node);
    }
    public T prev(T obj) {
        ListNodeT* node = object_to_node(obj);
        assert_own_node(node);
        if (node is head_tail)
            return null;
        node = node.prev_node;
        return node_to_object(node);
    }
    
    /// like next()/prev(), but never return null and act as ring-list instead
    public T ring_next(T obj) {
        ListNodeT* node = object_to_node(obj);
        assert_own_node(node);
        node = node.next_node;
        return node_to_object(node);
    }
    public T ring_prev(T obj) {
        ListNodeT* node = object_to_node(obj);
        assert_own_node(node);
        node = node.prev_node;
        return node_to_object(node);
    }
    
    private void doRemove(ListNodeT* node) {
        assert_own_node(node);
        node.owner = null;
        //GC friendlyness
        node.next_node = node.prev_node = null;
    }
    
    private void doAdd(ListNodeT* node, T data) {
        assert(node.owner is null);
        node.owner = this;
        node.data = data;
    }
    
    /// remove all list items
    /// (O(n) because the owner field of each ListNodeT must be cleared)
    public void clear() {
        if (head_tail) {
            ListNodeT* cur = head_tail;
            do {
                ListNodeT* next = cur.next_node;
                doRemove(cur);
                cur = next;
            } while (cur !is head_tail);
        }
        head_tail = null;
    }
    
    /// return the head/tail of the list
    public T head() {
        if (head_tail is null)
            return null;
        return node_to_object(head_tail);
    }
    public T tail() {
        if (head_tail is null)
            return null;
        return node_to_object(head_tail.prev_node);
    }
    
    private void init_list_head(T insert) {
        ListNodeT* obj = object_to_node(insert);
        assert(head_tail is null);
        doAdd(obj, insert);
        head_tail = obj;
        head_tail.next_node = head_tail;
        head_tail.prev_node = head_tail;
    }
    
    /// insert "insert" before "before", so that "list.prev(before) is insert"
    /// "before" can be null to insert the element as list-head
    public void insert_before(T insert, T before) {
        ListNodeT* obj = object_to_node(insert);
        ListNodeT* bef;
        
        if (before is null) {
            if (head_tail is null) {
                init_list_head(insert);
                return;
            }
            bef = head_tail;
        } else {
            bef = object_to_node(before);
        }
        
        assert_own_node(bef);
        doAdd(obj, insert);
        
        obj.next_node = bef;
        obj.prev_node = bef.prev_node;
        bef.prev_node = obj;
        obj.prev_node.next_node = obj;
        if (head_tail is bef)
            head_tail = obj;
    }
    
    /// insert "insert" after "after", so that "list.next(after) is insert"
    /// "after" can be null to insert the element as list-tail
    public void insert_after(T insert, T after) {
        ListNodeT* obj = object_to_node(insert);
        ListNodeT* aft;
        
        if (after is null) {
            if (head_tail is null) {
                init_list_head(insert);
                return;
            }
            aft = head_tail.prev_node;
        } else {
            aft = object_to_node(after);
        }
        
        assert_own_node(aft);
        doAdd(obj, insert);
        
        obj.prev_node = aft;
        obj.next_node = aft.next_node;
        aft.next_node = obj;
        obj.next_node.prev_node = obj;
    }
    
    /// insert "insert" as list-head
    public void insert_head(T insert) {
        insert_before(insert, null);
    }
    
    /// insert "insert" as list-tail
    public void insert_tail(T insert) {
        insert_after(insert, null);
    }
    
    /// remove the item "object" from the list
    public void remove(T object) {
        ListNodeT* obj = object_to_node(object);
        
        assert_own_node(obj);
        
        obj.prev_node.next_node = obj.next_node;
        obj.next_node.prev_node = obj.prev_node;
        
        //stupid special cases
        if (obj is head_tail)
            head_tail = obj.next_node;
        if (obj is head_tail && obj.next_node is obj.prev_node)
            head_tail = null;
        
        doRemove(obj);
    }
    
    /// test whether "object" is an item of the list
    public bool contains(T object) {
        ListNodeT* node = object_to_node(object);
        return (node.owner is this);
    }
    
    /// return if .head is null
    public bool isEmpty() {
        return (head_tail is null);
    }
    
    /// loop over all elements
    public int opApply(int delegate(inout T) del) {
        T cur = head();
        while (cur !is null) {
            int res = del(cur);
            if (res)
                return res;
            cur = next(cur);
        }
        return 0;
    }
    
    /// count how many items are in the list (O(n))
    public uint count() {
        uint c = 0;
        T t = head();
        while (t !is null) {
            c++;
            t = next(t);
        }
        return c;
    }
    
    /// check if there are at least "n" elements in the list
    /// (like .count >= n, but more efficient)
    public bool hasAtLeast(int n) {
        T t = head();
        uint c = 0;
        while (t !is null) {
            c++;
            if (c >= n)
                return true;
            t = next(t);
        }
        //special case: no elements
        return (n<=0);
    }
    
    /// create and return an array with the contents of the list
    public T[] array() {
        T[] arr;
        arr.length = count();
        T cur = head();
        uint n = 0;
        while (cur) {
            arr[n++] = cur;
            cur = next(cur);
        }
        return arr;
    }
    
    /// append the items in "arr" to the list
    public void append(T[] arr) {
        foreach(T t; arr) {
            insert_tail(t);
        }
    }
    
    /// copy the list into an array, sort it, and reconstruct the list from it
    /// will always sort like "T[] arr = List.array(); arr.sort;"
    public void sort() {
        T[] arr = array();
        arr.sort;
        //don't use clear() + append(), because reconstructing the list manualy
        //is "faster" and will lead to more bugs (premature optimization!!!1)
        head_tail = null;
        if (arr.length >= 1) {
            head_tail = object_to_node(arr[0]);
            ListNodeT* last = head_tail;
            for (uint n = 1; n < arr.length; n++) {
                ListNodeT* tmp = object_to_node(arr[n]);
                last.next_node = tmp;
                tmp.prev_node = last;
                last = tmp;
            }
            last.next_node = head_tail;
            head_tail.prev_node = last;
        }
    }
    
    //justification: useful for debugging
    public uint indexOf(T object) {
        uint i = 0;
        T cur = head;
        while (cur !is object) {
            assert(cur !is null); //object not in list?
            cur = next(cur);
            i++;
        }
        return i;
    }
    
    //not a real D class invariant because it would be too slow (even in debug
    //mode), because it iterates through the list
    public void do_invariant() {
        T t = head();
        if (t is null) {
            assert(tail() is null);
            assert(count() == 0);
        } else {
            ListNodeT* node = object_to_node(t);
            assert_own_node(node);
            assert(node is head_tail);
            if (t is tail()) {
                assert(head_tail.next_node is head_tail);
                assert(head_tail.prev_node is head_tail);
                assert(count() == 1);
            }
            ListNodeT* last = head_tail;
            ListNodeT* cur = head_tail.next_node;
            while (cur !is head_tail) {
                assert_own_node(cur);
                assert(cur.prev_node is last);
                last = cur;
                cur = cur.next_node;
                assert(cur !is null);
            }
            assert(head_tail.prev_node is last);
        }
    }
}

//xxx not all functions and all cases tested
unittest {
    //classes
    class Test2 {
        uint sth;
        mixin ListNodeMixin l1;
        mixin ListNodeMixin l2;
        this(uint n) {
            sth = n;
        }
        int opCmp(Object o) {
            Test2 t = cast(Test2)o;
            return sth - t.sth;
        }
    }
    
    Test2 t1 = new Test2(1);
    Test2 t2 = new Test2(2);
    Test2 t3 = new Test2(3);
    Test2 t4 = new Test2(4);
    Test2 t5 = new Test2(5);
    
    //Strange compiler error when you give "Test2" directly instead through x
    Test2 x;
    List!(Test2) list1 = new List!(Test2)(x.l1.getListNodeOffset());
    List!(Test2) list2 = new List!(Test2)(x.l2.getListNodeOffset());
    list1.do_invariant();
    list1.insert_tail(t1);
    list1.insert_tail(t2);
    list1.insert_tail(t3);
    list1.do_invariant();
    list1.insert_before(t4, t2);
    list1.do_invariant();
    list1.insert_after(t5, t2);
    list1.do_invariant();
    
    list2.insert_tail(t3);
    list2.insert_tail(t1);
    list2.insert_tail(t2);
    list2.do_invariant();
    
    static uint[] result1 = [1, 4, 2, 5, 3];
    uint n = 0;
    foreach (Test2 t; list1) {
        assert(t.sth == result1[n]);
        n++;
    }
    assert(n == 5);
    static uint[] result2 = [3, 1, 2];
    n = 0;
    foreach (Test2 t; list2) {
        assert(t.sth == result2[n]);
        n++;
    }
    
    list1.sort;
    list1.do_invariant();
    static uint[] result3 = [1, 2, 3, 4, 5];
    n = 0;
    foreach (Test2 t; list1) {
        assert(t.sth == result3[n]);
        n++;
    }
    
    list1.remove(t5); list1.do_invariant();
    list1.remove(t1); list1.do_invariant();
    list1.remove(t3); list1.do_invariant();
    list1.remove(t4); list1.do_invariant();
    assert(list1.count == 1 && list1.head.sth == 2);
    list1.sort;
    list1.do_invariant();
    assert(list1.count == 1 && list1.head.sth == 2);
    
    //structs
    struct Test {
        uint sth;
        mixin ListNodeMixin;
    }
    
    static Test st1 = {1};
    static Test st2 = {2};
    static Test st3 = {3};
    static Test st4 = {4};
    static Test st5 = {5};
    
    List!(Test*) slist = new List!(Test*)(Test.getListNodeOffset());
    slist.insert_tail(&st1);
    slist.insert_tail(&st2);
    slist.insert_tail(&st3);
    slist.insert_before(&st4, &st2);
    slist.insert_after(&st5, &st2);
    static uint[] sresult = [1, 4, 2, 5, 3];
    n = 0;
    foreach (Test* t; slist) {
        assert(t.sth == sresult[n]);
        n++;
    }
}
