-- utils is like a static class or a package
-- maybe this should be done differently; I don't know
utils = {}

-- searches for "search" and returns text before and after it
--  utils.split2("abcd", "c") == "ab", "cd"
--  utils.split2("abcd", "x") == "abcd", ""
function utils.split2(s, search)
    local idx = s:find(search, 1, true)
    if not idx then
        return s, ""
    else
        return s:sub(1, idx - 1), s:sub(idx)
    end
end

-- format anything (for convenience)
-- unlike string.format(), you can format anything, including table
-- it also uses Tango/C# style {} instead of %s
-- uses the __tostring function if available, else dumps table contents
-- allowed inside {}:
--      - ':q' if param is a string, quote it (other types aren't quoted)
--      - index, e.g. '{3}' gets the third parameter
function utils.sformat(fmt, ...)
    return utils.sformat_r({}, fmt, ...)
end

-- recursive version of sformat (done is simple used for table2string())
function utils.sformat_r(done, fmt, ...)
    if type(fmt) ~= "string" then
        assert(false, "sformat() expects a format string as first argument")
    end
    local res = ""
    local function out(x)
        res = res .. x
    end
    local args = {...}
    local next = 1
    local idx = 1
    for a, b in string.gmatch(fmt, "(){.-}()") do
        out(string.sub(fmt, next, a - 1))
        local f = string.sub(fmt, a, b - 1)
        assert(string.sub(f, 1, 1) == "{")
        assert(string.sub(f, #f, #f) == "}")
        f = string.sub(f, 2, #f - 1)
        -- do something with f, that contains format specifiers
        local pindex = nil
        local sidx, mods = utils.split2(f, ":")
        if #sidx > 0 then
            local tmp = tonumber(sidx)
            if tmp == nil then
                out("{error: parameter number in format string?}")
            else
                idx = tmp
            end
        end
        local quote_string = false
        if mods == ":q" then
            quote_string = true
        else
            if #mods > 0 then
                assert(false, "unknown format specifier: '"..mods.."'")
            end
        end
        -- format the parameter
        local param = args[idx]
        local ptype = type(param)
        if ptype == "userdata" then
            -- these functions need to be regged by D code
            if ObjectToString and d_islightuserdata and d_islightuserdata(param)
            then
                out(ObjectToString(param))
            else
                out("<unknown userdata>")
            end
        elseif ptype == "table" then
            out(utils.table2string(param, done))
        elseif ptype == "string" then
            if quote_string then
                out(string.format("%q", param))
            else
                out(param)
            end
        else
            out(tostring(param))
        end
        --
        idx = idx + 1
        next = b
    end
    out(string.sub(fmt, next, #fmt))
    return res
end

-- like sformat(), but print it (include a trailing newline)
function utils.formatln(fmt, ...)
    s = utils.sformat(fmt, ...)
    print(s)
end

-- format a table for debug purposes
-- mainly for use with sformat()
-- done_set can be nil; if not, it's expected to be a table with already
--  iterated tables as keys (to avoid recursion)
function utils.table2string(t, done_set)
    if t == nil then
        return "nil"
    end
    assert(type(t) == "table", "table2string accepts only tables")
    if done_set == nil then
        done_set = {}
    end
    if done_set[t] then
        return "#" .. tostring(done_set[t])
    end

    -- mark as done; use an ID as value (see above)
    local idx = done_set._new_table_index or 0
    done_set._new_table_index = idx + 1
    done_set[t] = idx

    -- only some tables define __tostring
    if t.__tostring then
        return tostring(t)
    end

    -- manually convert table to string
    -- try to follow the convention of table literals (see Lua manual)
    -- the tricky part is to produce useful results for both arrays and AAs
    -- (they can be mixed, too)
    local array_index = 1
    local res = "{"
    local function item(x)
        if #res > 1 then
            res = res .. ", "
        end
        res = res .. x
    end
    for k, v in pairs(t) do
        local keypart = ""
        if k == array_index then
            array_index = array_index + 1
        else
            if type(k) == "string" then
                -- xxx should only do this if string is a valid Lua ID
                keypart = k .. " = "
            else
                -- (:q means only quote strings)
                keypart = utils.sformat_r(done_set, "[{:q}] = ", k)
            end
        end
        item(utils.sformat_r(done_set, "{}{:q}", keypart, v))
    end
    return res .. "}"
end

-- global convenience functions (mainly when in interactive interpreter)
-- I consider them Lua language deficiencies *g*
-- to fix Lua, they just have to be global

-- show list of members in current scope
-- if t is not nil, list members of t instead
function dir(t)
    -- xxx should this recurse somehow into metatables or something?
    for k, v in pairs(t or _G) do
        utils.formatln("{} {}", type(v), k)
    end
end

-- just print something, and don't be as inconvenient as print()
-- but trailing (useless) arguments are ignored, unlike with print()
function printf(fmt, ...)
    if type(fmt) == "string" then
        utils.formatln(fmt, ...)
    else
        -- for the dumb and lazy
        utils.formatln("{}", fmt)
        if #{...} > 0 then
            printf(...)
        end
    end
end

-- ??
function min(a,b)
    if a <= b then
        return a
    else
        return b
    end
end
function max(a,b)
    if a >= b then
        return a
    else
        return b
    end
end

-- lua sure is a nice programming language
-- according to #lua, you have to concat array manually
-- table.concat and .. only work for strings or arrays of numbers (?!?!?!)
function concat(...)
    local res = {}
    local n = 1
    for i = 1, select("#", ...) do
        for k2, v2 in ipairs(select(i, ...)) do
            res[n] = v2
            n = n + 1
        end
    end
    return res
end

-- similar to cond?a:b, but a and b get always evaluated
function iif(cond, a, b)
    if cond then
        return a
    else
        return b
    end
end

-- return c if c is not nil, or a
-- useful instead of "c or a", when c can be false
-- e.g. foo(x) where x is a default argument, but you should also be able to
--  pass false: function foo(x) x = ifnil(x, true)  use(x) end
function ifnil(c, a)
    if c == nil then
        return a
    else
        return c
    end
end

-- duplicate the table (but not its values)
function table_copy(table)
    local ntable = {}
    for k, v in pairs(table) do
        ntable[k] = v
    end
    return ntable
end

-- mix two tables (if items exist in both tables, second has priority)
-- original tables aren't changed
function table_merge(t1, t2)
    local t = {}
    for k, v in pairs(t1) do
        t[k] = v
    end
    for k, v in pairs(t2) do
        t[k] = v
    end
    return t
end

-- return true or false whether the table is empty
-- I have no clue how to do this "right" (#table obviously doesn't always work)
function table_empty(table)
    local key, value = next(table)
    return not key
end

-- duplicate table with table_copy() and then copy in the values from modifications
function table_modified(table, modifications)
    local ntable = table_copy(table)
    for k, v in pairs(modifications) do
        ntable[k] = v
    end
    return ntable
end

-- a1 and a2 are expected to be arrays (basically means '#' should work)
-- items are compared with ==
function array_equal(a1, a2)
    local len1 = #a1
    local len2 = #a2
    if len1 ~= len2 then
        return false
    end
    for i = 1, len1 do
        if a1[i] ~= a2[i] then
            return false
        end
    end
    return true
end

-- remove table entry; remove its old value or the default
function pick(t, key, def)
    local val = t[key]
    t[key] = nil
    return ifnil(val, def)
end

-- returns the calling module's export table
-- equal to _G[ENV_NAME] (initialized to table if empty)
function export_table()
    -- use caller's environment
    setfenv(1, getfenv(2))
    if not _G[ENV_NAME] then
        _G[ENV_NAME] = {}
    end
    return _G[ENV_NAME]
end

-- import all (named) symbols from table into caller's environment
function import(table)
    -- get caller's environment
    local env = getfenv(2)
    for k, v in pairs(table) do
        env[k] = v
    end
end

-- emulation of some features of utils.randval.RandomValue
-- return a table suitable to be demarshalled to RandomValue
--  max is optional and will be set to min if nil
function utils.range(min, max)
    -- whatever you do here, cross-check with utils.range_sample for consistency
    max = max or min
    return setmetatable({ min = min, max = max }, utils.Range)
end
utils.Range = {} -- metatable just for marker purposes

function utils.is_range(r)
    return type(r) == "table" and getmetatable(r) == utils.Range
end

-- unittest
assert(not utils.is_range(5))
assert(not utils.is_range("huh"))
assert(utils.is_range(utils.range(5, 6)))
assert(utils.is_range(utils.range(5)))

-- range_sample() for RandomValue.sample()
-- this function has two forms:
--  range_sample(some_range_table)
--  range_sample(a)     -- return a
--  range_sample(a, b)  -- behaves like range_sample(range(a, b))
-- to see which version is applied, utils.is_range() is used
-- further, since Lua doesn't distinguish ints and floats, there are different
--  versions for each of them

-- integers
function utils.range_sample_i(...)
    return utils.range_sample_g(Random_rangei, ...)
end
-- floats
function utils.range_sample_f(...)
    return utils.range_sample_g(Random_rangef, ...)
end

-- any type that supports __add, __sub and __mul
-- e.g. works for Time
-- separate to not allocate a closure on each call
local function _range_any_random(a, b)
    return a + (b-a)*Random_rangef(0, 1)
end
function utils.range_sample_any(...)
    return utils.range_sample_g(_range_any_random, ...)
end

-- generic; have to pass a function
function utils.range_sample_g(fn, r, b)
    local min, max
    if utils.is_range(r) then
        min, max = r.min, r.max
    else
        -- similar to what utils.range does
        -- but don't construct a table for efficiency
        if b then
            min, max = r, b
        else
            -- not really a range
            return r
        end
    end
    return fn(min, max)
end
