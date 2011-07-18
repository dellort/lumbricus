module luatest;

import framework.lua;
import cinit = common.init;
import framework.filesystem;

import utils.misc;
import utils.stream;
import utils.strparser;
import utils.vector2;
import utils.rect2;
import utils.time;


class Bar {
    string meh;
    int something = 666;

    void blu(int x) {
        something = x;
    }
    int blu() {
        return something;
    }

    //test the same, with reversed setter/getter (think about "&blo")
    int blo() {
        return something;
    }
    void blo(int s) {
        something = s;
    }

    void test(char[] msg) {
        Trace.formatln("Called Bar.test('%s')", msg);
    }

    string blurgh() {
        return meh;
    }
}

class Evul {
}

enum Test {
    a = 1,
    b,
    c,
}

class Foo {
    string bla;
    Test muh;

    string test(int x, float y = 99.0, string msg = "Default") {
        return myformat("hello from D! got: %s %s '%s'", x, y, msg);
    }

    string test2(string bla = "huhu") {
        return bla;
    }

    void passBar(Bar the_bar) {
        Trace.formatln("received a bar: '%s'", the_bar.classinfo.name);
        if (the_bar)
            assert(!!cast(Bar)cast(Object)the_bar);
    }

    Bar createBar() {
        auto b = new Bar();
        b.meh = "I'm a bar.";
        return b;
    }

    Evul createEvul() {
        return new Evul();
    }

    void vector(Vector2i v) {
        Trace.formatln("%s", v);
    }

    Vector2i makeVector(int x, int y) {
        return Vector2i(x, y);
    }

    void vectors(Vector2i[] v) {
        Trace.formatln("vectors: %s", v);
    }

    int[] array(int[] a) {
        Trace.formatln("%s", a);
        return a;
    }

    void aarray(int[char[]] a) {
        Trace.formatln("%s", a);
    }

    char[][] makeArray(char[] a, char[] b, char[] c) {
        char[][] ret;
        ret ~= a; ret ~= b; ret ~= c;
        return ret;
    }

    void callCb(void delegate() cb) {
        cb();
    }

    Time makeTime(long msecs) {
        return timeMsecs(msecs);
    }

    void arg(bool check) {
        argcheck(check);
    }
}

LuaRegistry scripting;

static this() {
    scripting = new typeof(scripting)();
    scripting.methods!(Foo, "test", "test2", "createBar", "createEvul",
        "passBar");
    scripting.methods!(Foo, "vector", "makeVector", "vectors", "array",
        "aarray", "makeArray", "callCb", "makeTime", "arg");
    scripting.properties!(Foo, "bla", "muh");
    scripting.properties!(Bar, "blu", "blo", "something")();
    scripting.methods!(Bar, "test", "blurgh")();
    scripting.func!(funcBlub)();
    enumStrings!(Test, "a,b,c");
    scripting.func!(funcBlab)();
    scripting.func!(funcRef)();
}

void funcBlub(char[] arg) {
    Trace.formatln("Plain old function, yay! Got '%s'", arg);
}

struct TehEvil {
    int foo;
    TehEvil[] sub;
}

void funcBlab(TehEvil evil) {
    Trace.formatln("ok");
}

LuaReference funcRef(LuaReference r) {
    Trace.formatln("ref as int: %s", r.get!(int)());
    return r;
}

void main(string[] args) {
    //xxx this is unkosher, but we need the full filesystem
    cinit.init(args[1..$]);
    LuaState s = new LuaState();
    s.register(scripting);

    auto foo = new Foo();
    s.addSingleton(foo);

    void loadexec(string code, string name = "blub") {
        s.loadScript(name, code);
    }

    void loadscript(string filename) {
        filename = "lua/" ~ filename;
        auto st = gFS.open(filename);
        scope(exit) st.close();
        s.loadScript(filename, cast(string)st.readAll());
    }

    loadscript("vector2.lua");
    s.addScriptType!(Vector2i)("Vector2");
    s.addScriptType!(Vector2f)("Vector2");
    loadscript("rect2.lua");
    s.addScriptType!(Rect2i)("Rect2");
    s.addScriptType!(Rect2f)("Rect2");
    loadscript("time.lua");
    s.addScriptType!(Time)("Time");

    loadscript("utils.lua");

    loadexec(`
        print("Hello world")
        print(Foo:test(1, -4.2, "Foobar"))
        print(Foo:test(1, -4.2))
        print(Foo:test(1))
        print(Foo:test2())
        print(Foo:test2("x"))
        Foo:set_bla("durf")
        print(Foo:bla())
        printf("enum = {}", Foo:muh())
        Foo:set_muh(2)
        printf("enum = {}", Foo:muh())
        Foo:set_muh("c") -- automatic string -> enum conversion
        printf("enum = {}", Foo:muh())
        b = Foo:createBar()
        Bar.test(b, "hurf")

        x = Vector2(1,2)
        rectable = {"bla"}
        rectable["blu"] = rectable
        printf("number: {} str: {} table: {} arr: {} " ..
            "table_with_tostring: {} mixed_aa_arr: {} empty_table: {} " ..
            "rectable: {} userdata: {} nil: {} " ..
            "noarg: {}",
            123, "hello", {x="this_is_x", y="this_is_y"}, {1,2,3}, Vector2(1,2),
            {[{}] = 123, 4, "huh", [6] = 5, meh = 6}, {}, rectable, b, nil);

        printf("2={2} 1={1} 2={} 1q={1:q}", "a", "b", "c")

        function test(arg)
            print(string.format("Called Lua function test('%s')", arg))
            return "blabla"
        end

        Foo:passBar(b)

        v1 = Foo:makeVector(2, 3)
        v2 = Vector2(5)
        vv = v1 + v2
        vv:print()
        Foo:vector({4, 5})
        Foo:vector(Foo:makeVector(23, 42))

        --t = Foo:makeTime(500)
        --t:print()
        --timeMins(30):print()

        r = Rect2(3, 3, 7, 7)
        r:print()
        printf("Size: {}", r:size())
        r2 = Rect2.Span(Vector2(3), Vector2(5))
        printf("Size: {} Center: {}", r2:size(), r2:center())


        Foo:array({1, 2, 3, 4})
        Foo:aarray({x = 10, y = 20})
        ar = Foo:makeArray("a", "b", "c")
        for k,v in ipairs(ar) do
            print(string.format("  %s -> %s", k, v))
        end
        funcBlub("asdfx");
        Foo:callCb(function()
            print("Got callback!")
        end)

        stuff = { some_string = "hello", some_b = b }
        stuff["circle"] = stuff

        -- accessors
        assert(Bar.blu(b) == 666)
        Bar.set_blu(b, 123)
        assert(Bar.blu(b) == 123)
        Bar.set_blo(b, 456)
        assert(Bar.blo(b) == 456)
        printf("blo={}", Bar.blo(b))
        -- fields
        assert(Bar.something(b) == 456)
        Bar.set_something(b, 789)
        printf("something={}", Bar.something(b))

        Foo:vectors({Vector2(1,0), Vector2(5,7)})

        -- the table x is constructed so, that iteration with pairs()/lua_next
        --  returns the (key,value) pair (2,2) first
        local x = {}
        x[100] = 4
        x[400] = 5
        x[2] = 2
        x[1] = 1
        x[100] = nil
        x[400] = nil
        -- this failed with the old marshaller code, because it assumed lua_next
        --  would iterate the indices in a sorted way
        assert(array.equal(Foo:array(x), {1, 2}))

        printf("12 == {}", funcRef(12))
    `);

    s.call("test", "Blubber");
    s.call("test", "Blubber");

    Trace.formatln("got: '%s'", s.callR!(char[])("test", "..."));

    s.setGlobal("d_global", 123);
    assert(s.getGlobal!(int)("d_global") == 123);

    struct Closure {
       int test(int a, char[] b) { return a + b.length; }
    }

    s.scriptExec(`
        local cb = ...
        assert(cb(4, "abc") == 7)
        print("cb test ok")
    `, &(new Closure).test);

    //some nested error case that probably failed before
    struct Closure2 {
        void delegate() fail;
        void test() {
            try {
                fail();
            } catch (LuaException e) {
                Trace.formatln("nested error ok!: %s", e);
            }
        }
    }
    auto test2 = new Closure2;
    test2.fail = s.scriptExecR!(void delegate())(
        `return function() error("muuuh") end`);
    s.scriptExec(`
        faildel = ...
        faildel()
    `, &test2.test);

    //provoke sstack overflow, somewhat helps with testing lua_checkstack
    //run with Lua API check enabled
    struct Closure3 {
        LuaState s;
        alias void delegate(int a1, int a2, int a3, int a4, int a5, int a6,
            int a7, int a8, int a9, int a10, int a11, int a12, int a13, int a14,
            int a15, int a16, int a17, int a18, int a19, int a20, int a21) X;
        void test(X x, int a1, int a2, int a3, int a4, int a5, int a6, int a7,
            int a8, int a9, int a10, int a11, int a12, int a13, int a14,
            int a15, int a16, int a17, int a18, int a19)
        {
            if (a1 == 1) {
                x(a1,a2,a3,a4,a5,a6,a7,a8,a9,a10,a11,a12,a13,a14,a15,16,17,18,
                    19, 20, 21);
            } else {
                //only function I found that uses some stack unprotected
                //xxx didn't provoke the bug, but who cares
                s.reftableSize();
            }
        }
    }
    auto test3 = new Closure3;
    test3.s = s;
    s.scriptExec(`
        local f = ...
        f(function(...) print (...) end, 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,
            18,19)
        f(function(...) print (...) end, 2,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,
            18,19)
    `, &test3.test);

    //trivial userdata metatable test
    //Foo is a variable of type Foo because it was added as singleton
    loadexec(`print(Foo:test2("huhuh"))`);

    //GC test - don't try this without version Lua_In_D_Memory

    Trace.formatln("GC test...");

    //get some garbage, trigger GC and overwriting of free'd data, etc.
    for (int i = 0; i < 5000000; i++) {
        new ubyte[1];
    }

    loadexec(`
        print(Bar.blurgh(b))
    `);

    //end GC test

    //these are expected to fail (type checks etc.)

    void fail(string code) {
        try {
            loadexec(code);
        } catch (LuaException e) {
            Trace.formatln("OK, %s", e.msg);
            return;
        }
        throw new Exception("Should have thrown.");
    }

    //this fails for two reasons: parse error + invalid utf-8
    //the utf-8 one because (I guess) Lua outputs only one byte of two
    fail(`ä`);
    //too many args
    fail(`Bar.test(b, "a", "b")`);
    fail(`Foo:test(1, 2, "Bla", "Too much")`);
    //too few args
    fail(`Bar.test()`);
    fail(`Foo:test()`);
    //wrong type
    fail(`Foo:passBar(Foo:createEvul())`);
    fail(`Foo:passBar("err")`);
    fail(`Foo:test("wrong", 1.3, "bla")`);
    fail(`Foo:test(1, 1.3, nil)`);
    fail(`local a
        local b
        Bar.test("a")`);
    fail(`Bar.test(Foo:createEvul(), "a")`);
    //script errors
    fail(`invalid code`);
    fail(`error("Thrown from Lua")`);
    fail(`math.cos("Hello")`);
    //lolwut fail(`math.cos("1")`);
    //invalid index, because Vector2 has only 2 items
    fail(`Foo:vector({4, 5, 6})`);
    //mixed by-name/by-index access
    fail(`Foo:vector({4, y=5})`);
    fail(`Foo:vector({x=4, 5})`);
    //'z' doesn't exist
    fail(`Foo:vector({x=1, z=4})`);
    //using non-integer as index
    fail(`Foo:vector({[1]=1, [2.4]=4})`);
    //this shouldn't work either (it's stupid)
    fail(`Foo:vector({[1]=1, ["2"]=4})`);
    fail(`Foo:arg(false)`);
    fail("assert(false)");
    //loadexec(`Foo:vector({[1]=1, ["2"]=4})`);
    //demarshalling s into struct TehEvil would result in an infinite sized data
    //  structure (demarshaller treats arrays as values, not references)
    //the Lua stack size is limited and it will be catched quickly by checkstack
    fail(`local s = {foo=123}; s.sub = {s}; funcBlab(s)`);
}
