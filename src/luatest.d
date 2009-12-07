module luatest;

import framework.lua;
import tango.core.tools.TraceExceptions;
import cinit = common.init;
import framework.filesystem;

import utils.misc;
import utils.stream;
import utils.vector2;
import utils.rect2;
import utils.time;


class Bar {
    char[] meh;
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
        Trace.formatln("Called Bar.test('{}')", msg);
    }

    char[] blurgh() {
        return meh;
    }
}

class Evul {
}

class Foo {
    char[] bla;

    char[] test(int x, float y = 99.0, char[] msg = "Default") {
        return myformat("hello from D! got: {} {} '{}'", x, y, msg);
    }

    void passBar(Bar the_bar) {
        Trace.formatln("received a bar: '{}'", the_bar.classinfo.name);
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
        Trace.formatln("{}", v);
    }

    Vector2i makeVector(int x, int y) {
        return Vector2i(x, y);
    }

    void vectors(Vector2i[] v) {
        Trace.formatln("vectors: {}", v);
    }

    void array(int[] a) {
        Trace.formatln("{}", a);
    }

    void aarray(int[char[]] a) {
        Trace.formatln("{}", a);
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
}

LuaRegistry scripting;

static this() {
    scripting = new typeof(scripting)();
    scripting.methods!(Foo, "test", "createBar", "createEvul", "passBar");
    scripting.methods!(Foo, "vector", "makeVector", "vectors", "array", "aarray",
        "makeArray", "callCb", "makeTime");
    scripting.property!(Foo, "bla");
    auto bar = scripting.defClass!(Bar)();
    bar.properties!("blu", "blo", "something")();
    bar.methods!("test", "blurgh")();
    scripting.func!(funcBlub)();
}

void funcBlub(char[] arg) {
    Trace.formatln("Plain old function, yay! Got '{}'", arg);
}

void main(char[][] args) {
    scope(exit) gMainTerminated = true;
    cinit.init(args);
    LuaState s = new LuaState();
    s.register(scripting);

    auto foo = new Foo();
    s.addSingleton(foo);

    void loadexec(char[] code, char[] name = "blub") {
        s.loadScript(name, code);
    }

    void loadscript(char[] filename) {
        filename = "lua/" ~ filename;
        auto st = gFS.open(filename);
        scope(exit) st.close();
        s.loadScript(filename, cast(char[])st.readAll());
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
        print(Foo_test(1, -4.2, "Foobar"))
        print(Foo_test(1, -4.2))
        print(Foo_test(1))
        Foo_set_bla("durf")
        print(Foo_bla())
        b = Foo_createBar()
        Bar_test(b, "hurf")

        x = Vector2(1,2)
        rectable = {"bla"}
        rectable["blu"] = rectable
        utils.formatln("number: {} str: {} table: {} arr: {} " ..
            "table_with_tostring: {} mixed_aa_arr: {} empty_table: {} " ..
            "rectable: {} userdata: {} nil: {} " ..
            "noarg: {}",
            123, "hello", {x="this_is_x", y="this_is_y"}, {1,2,3}, Vector2(1,2),
            {[{}] = 123, 4, "huh", [6] = 5, meh = 6}, {}, rectable, b, nil);

        utils.formatln("2={2} 1={1} 2={} 1q={1:q}", "a", "b", "c")

        function test(arg)
            print(string.format("Called Lua function test('%s')", arg))
            return "blabla"
        end

        Foo_passBar(b)

        v1 = Foo_makeVector(2, 3)
        v2 = Vector2(5)
        vv = v1 + v2
        vv:print()
        Foo_vector({4, 5})
        Foo_vector(Foo_makeVector(23, 42))

        t = Foo_makeTime(500)
        t:print()
        timeMins(30):print()

        r = Rect2(3, 3, 7, 7)
        r:print()
        utils.formatln("Size: {}", r:size())
        r2 = Rect2.Span(Vector2(3), Vector2(5))
        utils.formatln("Size: {} Center: {}", r2:size(), r2:center())


        Foo_array({1, 2, 3, 4})
        Foo_aarray({x = 10, y = 20})
        ar = Foo_makeArray("a", "b", "c")
        for k,v in ipairs(ar) do
            print(string.format("  %s -> %s", k, v))
        end
        funcBlub("asdfx");
        Foo_callCb(function()
            print("Got callback!")
        end)

        stuff = { some_string = "hello", some_b = b }
        stuff["circle"] = stuff

        -- accessors
        assert(Bar_blu(b) == 666)
        Bar_set_blu(b, 123)
        assert(Bar_blu(b) == 123)
        Bar_set_blo(b, 456)
        assert(Bar_blo(b) == 456)
        utils.formatln("blo={}", Bar_blo(b))
        -- fields
        assert(Bar_something(b) == 456)
        Bar_set_something(b, 789)
        utils.formatln("something={}", Bar_something(b))

        Foo_vectors({Vector2(1,0), Vector2(5,7)})
    `);

    s.call("test", "Blubber");
    s.call("test", "Blubber");

    Trace.formatln("got: '{}'", s.callR!(char[])("test", "..."));

    s.setGlobal("d_global", 123);
    assert(s.getGlobal!(int)("d_global") == 123);

    s.scriptExec(`
        local cb = ...
        assert(cb(4, "abc") == 7)
        print("cb test ok")
    `, (int a, char[] b) { return a + b.length; });

    //GC test - don't try this without version Lua_In_D_Memory

    //get some garbage, trigger GC and overwriting of free'd data, etc.
    for (int i = 0; i < 5000000; i++) {
        new ubyte[1];
    }

    loadexec(`
        print(Bar_blurgh(b))
    `);

    //end GC test

/+
    char[][Object] exts;
    Stream outs = //Stream.OpenFile("foo.out", File.ReadWriteCreate);
    new MemoryStream();//
    s.serialize("stuff", outs, (Object o) {
        if (!(o in exts))
            exts[o] = myformat("#{}", exts.length);
        return exts[o];
    });

    outs.position = 0;

    s.deserialize("meep", outs, (char[] s) {
        foreach (Object o, char[] id; exts) {
            if (s == id)
                return o;
        }
        //signals error
        //also, lol pathetic D type "inference" (more like type interference)
        return cast(Object)null;
    });

    loadexec(`
        print(string.format("deserialized: some_string=%s", meep.some_string));
        -- the printed string was actually not serialized
        print(string.format("deserialized: some_b=%s", Bar_blurgh(meep.some_b)));
    `);
+/

    //these are expected to fail (type checks etc.)

    void fail(char[] code) {
        try {
            loadexec(code);
        } catch (LuaException e) {
            Trace.formatln("OK, {}", e.msg);
            return;
        }
        throw new Exception("Should have thrown.");
    }

    //this fails for two reasons: parse error + invalid utf-8
    //the utf-8 one because (I guess) Lua outputs only one byte of two
    fail(`ä`);
    //too many args
    fail(`Bar_test(b, "a", "b")`);
    fail(`Foo_test(1, 2, "Bla", "Too much")`);
    //too few args
    fail(`Bar_test()`);
    fail(`Foo_test()`);
    //wrong type
    fail(`Foo_passBar(Foo_createEvul())`);
    fail(`Foo_passBar("err")`);
    fail(`Foo_test("wrong", 1.3, "bla")`);
    fail(`Foo_test(1, 1.3, nil)`);
    fail(`local a
        local b
        Bar_test("a")`);
    fail(`Bar_test(Foo_createEvul(), "a")`);
    //script errors
    fail(`invalid code`);
    fail(`error("Thrown from Lua")`);
    fail(`math.cos("Hello")`);
}
