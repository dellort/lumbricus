module luatest;

import framework.lua;
import tango.core.tools.TraceExceptions;

import utils.misc;
import utils.stream;
import utils.vector2;
import utils.time;


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

    Time makeTime(long msecs) {
        return timeMsecs(msecs);
    }
}

LuaRegistry scripting;

static this() {
    scripting = new typeof(scripting)();
    scripting.methods!(Foo, "test", "createBar", "createEvul", "passBar");
    scripting.methods!(Foo, "vector", "makeVector", "array", "aarray",
        "makeArray", "callCb", "makeTime");
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

const cVectorLib = `
    Vector2 = {}
    Vector2.__index = Vector2
    setmetatable(Vector2, {__call = function(self, x, y)
        if (y) then
            return setmetatable({x = x, y = y}, Vector2)
        else
            return setmetatable({x = x, y = x}, Vector2)
        end
    end})

    function Vector2:__add(v)
        return Vector2(self.x + v.x, self.y + v.y)
    end

    function Vector2:__sub(v)
        return Vector2(self.x - v.x, self.y - v.y)
    end

    function Vector2:__mul(v)
        if type(v) == "table" then
            return self.x * v.x + self.y * v.y;
        else
            return Vector2(self.x * v, self.y * v)
        end
    end

    function Vector2:__div(v)
        if type(v) == "table" then
            return Vector2(self.x / v.x, self.y / v.y)
        else
            return Vector2(self.x / v, self.y / v)
        end
    end

    function Vector2:__unm()
        return Vector2(-self.x, -self.y)
    end

    function Vector2:__len()
        return math.sqrt(self.x*self.x, self.y*self.y)
    end

    function Vector2:__eq(v)
        return self.x == v.x and self.y == v.y
    end

    function Vector2:quad_length()
        return self.x*self.x + self.y*self.y
    end

    function Vector2:toAngle()
        return math.atan2(self.y, self.x)
    end

    function Vector2:print()
        print(string.format("(%d, %d)", self.x, self.y))
    end
`;

const cTimeLib = `
    Time = {}
    Time.__index = Time
    setmetatable(Time, {__call = function(self, timeVal)
        return setmetatable({timeVal = timeVal}, Time)
    end})

    Time.Null = Time(0)

    function Time:__add(v)
        return Time(self.timeVal + v.timeVal)
    end
    function Time:__sub(v)
        return Time(self.timeVal - v.timeVal)
    end
    function Time:__mul(v)
        return Time(self.timeVal * v)
    end
    function Time:__div(v)
        return Time(self.timeVal / v)
    end
    function Time:__unm()
        return Time(-self.timeVal)
    end

    function Time:__eq(v)
        return self.timeVal == v.timeVal
    end
    function Time:__lt(v)
        return self.timeVal < v.timeVal
    end
    function Time:__le(v)
        return self.timeVal <= v.timeVal
    end

    function Time:print()
        print(string.format("%f s", self:secs()))
    end

    function Time:musecs()
        return self.timeVal/1000
    end
    function Time:msecs()
        return self.timeVal/1000000
    end
    function Time:secs()
        return self:msecs()/1000
    end
    function Time:mins()
        return self:msecs()/60000
    end

    function timeMusecs(v)
        return Time(v*1000)
    end
    function timeMsecs(v)
        return Time(v*1000000)
    end
    function timeSecs(v)
        return timeMsecs(v*1000)
    end
    function timeMins(v)
        return timeMsecs(v*60000)
    end
`;

void main(char[][] args) {
    LuaState s = new LuaState();
    s.register(scripting);

    auto foo = new Foo();
    s.addSingleton(foo);

    void loadexec(char[] code, char[] name = "blub") {
        s.stack0();
        s.luaLoadAndPush(name, code);
        s.luaCall!(void)();
        s.stack0();
    }

    loadexec(cVectorLib, "vector2.lua");
    s.addScriptType!(Vector2i)("Vector2");
    s.addScriptType!(Vector2f)("Vector2");
    loadexec(cTimeLib, "time.lua");
    s.addScriptType!(Time)("Time");

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
        v2 = Vector2(5)
        vv = v1 + v2
        vv:print()
        t = Foo_makeTime(500)
        t:print()
        timeMins(30):print()
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
