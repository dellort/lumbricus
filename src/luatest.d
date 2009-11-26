module luatest;

import framework.lua;
import tango.core.tools.TraceExceptions;

import utils.misc;
import utils.stream;
import utils.vector2;


class Bar {
    char[] meh;

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
}

LuaRegistry scripting;

static this() {
    scripting = new typeof(scripting)();
    scripting.methods!(Foo, "test", "createBar", "createEvul", "passBar");
    scripting.method!(Foo, "vector")();
    scripting.method!(Foo, "makeVector")();
    scripting.method!(Foo, "array")();
    scripting.method!(Foo, "aarray")();
    scripting.method!(Foo, "makeArray")();
    scripting.method!(Foo, "callCb")();
    scripting.method!(Bar, "test")();
    scripting.method!(Bar, "blurgh")();
    scripting.func!(funcBlub)();

    //lua.method!(Sprite, "setState")();
    //lua.method!(GameEngine, "explosion")();
}

/*void startgame() {
    lua.addSingleton!(GameEngine)("GameEngine", engine);
}*/

void funcBlub(char[] arg) {
    Trace.formatln("Plain old function, yay! Got '{}'", arg);
}

void main(char[][] args) {
    LuaState s = new LuaState();
    s.register(scripting);

    auto foo = new Foo();
    s.addSingleton(foo);

    void loadexec(char[] code) {
        s.stack0();
        s.luaLoadAndPush("blub", code);
        s.luaCall!(void)();
        s.stack0();
    }

    loadexec(`
        Vector2 = {}
        Vector2.__index = Vector2

        function Vector2:new(x, y)
            v = { x = x, y = y }; setmetatable(v, Vector2); return v
        end

        function Vector2:__add(v)
            return Vector2:new(self.x + v.x, self.y + v.y)
        end

        function Vector2:__sub(v)
            return Vector2:new(self.x - v.x, self.y - v.y)
        end

        function Vector2:print()
            print(string.format("(%d, %d)", self.x, self.y))
        end
    `);
    s.addScriptType!(Vector2i)("Vector2");
    s.addScriptType!(Vector2f)("Vector2");

    loadexec(`
        print("Hello world")
        print(Foo_test(1, -4.2, "Foobar"))
        print(Foo_test(1, -4.2))
        print(Foo_test(1))
        b = Foo_createBar()
        Bar_test(b, "hurf")

        function test(arg)
            print(string.format("Called Lua function test('%s')", arg))
            return "blabla"
        end

        Foo_passBar(b)
        v1 = Foo_makeVector(2, 3)
        v2 = Foo_makeVector(1, 7)
        vv = v1 + v2
        -- for k,v in pairs(v1) do
        --    print(string.format("  %s -> %s", k, v))
        -- end
        vv:print()
        Foo_vector({4, 5})
        Foo_vector(Foo_makeVector(23, 42))
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
    `);
    s.call("test", "Blubber");
    s.call("test", "Blubber");

    Trace.formatln("got: '{}'", s.callR!(char[], char[])("test", "..."));

    //don't try this without version Lua_In_D_Memory

    //get some garbage, trigger GC and overwriting of free'd data, etc.
    for (int i = 0; i < 5000000; i++) {
        new ubyte[1];
    }

    loadexec(`
        print(Bar_blurgh(b))
    `);

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

    //these are expected to fail (type checks etc.)
    //I don't know how to fail "gracefully", so all commented out

    //too many args
    ex(loadexec(`Bar_test(b, "a", "b")`));
    ex(loadexec(`Foo_test(1, 2, "Bla", "Too much")`));
    //too few args
    ex(loadexec(`Bar_test()`));
    ex(loadexec(`Foo_test()`));
    //wrong type
    ex(loadexec(`Foo_passBar(Foo_createEvul())`));
    ex(loadexec(`Foo_passBar("err")`));
    ex(loadexec(`Foo_test("wrong", 1.3, "bla")`));
    ex(loadexec(`Foo_test(1, 1.3, nil)`));
    ex(loadexec(`local a
        local b
        Bar_test("a")`));
    ex(loadexec(`Bar_test(Foo_createEvul(), "a")`));
    //script errors
    ex(loadexec(`invalid code`));
    ex(loadexec(`error("Thrown from Lua")`));
    ex(loadexec(`math.cos("Hello")`));
}

void ex(T)(lazy T v) {
    try {
        v();
    } catch(LuaException e) {
        Trace.formatln("OK, {}", e.msg);
        return;
    }
    throw new Exception("Should have thrown.");
}
