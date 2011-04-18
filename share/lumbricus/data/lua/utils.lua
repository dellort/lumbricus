-- utils is like a static class or a package
-- maybe this should be done differently; I don't know
utils = {}

-- searches for "search" and returns text before and after it
--  utils.split2("abcd", "c") == "ab", "cd"
--  utils.split2("abcd", "x") == "abcd", ""
function utils.split2(s, search, exclude_search)
    local idx = s:find(search, 1, true)
    if not idx then
        return s, ""
    elseif exclude_search then
        return s:sub(1, idx - 1), s:sub(idx + #search)
    else
        return s:sub(1, idx - 1), s:sub(idx)
    end
end

do -- unittest
    assert(utils.split2("abcd", "c") == "ab", "cd")
    assert(utils.split2("abcd", "x") == "abcd", "")
    assert(utils.split2("abcde", "cd", true) == "ab", "e")
    assert(utils.split2("abcd", "x", true) == "abcd", "")
end

-- return if i is an integer
-- it is hoped that this does exactly the same as
--  http://www.lua.org/source/5.1/luaconf.h.html#lua_number2int
-- which is used to find out if a key to a hash entry is an int, or just a float
function utils.isInteger(i)
    -- apparently Lua really makes this bothersome, wtf?
    -- checks: type, fractional numbers + nan, inf
    return type(i) == "number" and math.floor(i) == i and i-1 ~= i
end

-- parse str as boolean
function utils.toBool(str)
    return type(str) == "string" and (string.lower(str) == "true"
        or string.lower(str) == "yes" or str == "1")
end

-- format anything (for convenience)
-- unlike string.format(), you can format anything, including table
-- it also uses Tango/C# style {} instead of %s
-- uses the __tostring function if available, else dumps table contents
-- allowed inside {}:
--      - ':q' if param is a string, quote it (other types aren't quoted)
--      - index, e.g. '{3}' gets the third parameter
-- returns the result as string
-- trailing unused arguments are not allowed (they show up as warning)
function utils.format(fmt, ...)
    return utils.format_r({}, fmt, ...)
end

-- recursive version of format (done is used for table2string())
-- everything else see utils.format
function utils.format_r(done, fmt, ...)
    assert(type(fmt) == "string", "format() expects a format string as first"
        .. " argument")
    local res = ""
    local function out(x)
        res = res .. x
    end
    local argc = select("#", ...)
    local argused = {}
    local next = 1
    local nidx = 0
    for a, b in string.gmatch(fmt, "(){.-}()") do
        out(string.sub(fmt, next, a - 1))
        local f = string.sub(fmt, a, b - 1)
        assert(string.sub(f, 1, 1) == "{")
        assert(string.sub(f, #f, #f) == "}")
        f = string.sub(f, 2, #f - 1)
        -- f = param_index[:additional_format_parameters]
        local sidx, mods = utils.split2(f, ":", true)
        local idx = nidx + 1
        if #sidx > 0 then
            local tmp = tonumber(sidx)
            if tmp == nil then
                out("{error: parameter number in format string?}")
            else
                idx = tmp
            end
        end
        if idx >= 1 and idx <= argc then
            argused[idx] = true
            local arg = select(idx, ...)
            out(utils._format_value(arg, mods, done))
        else
            out("{error: arg number " .. idx .. " not present}")
        end
        --
        nidx = idx
        next = b
    end
    out(string.sub(fmt, next, #fmt))
    -- warn about unused arguments
    -- Note: if this gets in the way because you actually want to ignore some
    --  arguments (like for game messages), add an invisible format parameter
    --  that serves as command to ignore unused args
    for i = 1, argc do
        if not argused[i] then
            out("{error: arg number " .. i .. " unused}")
        end
    end
    return res
end

-- backend for utils.format; turn a single value into a string
--  done: set of done tables (prevent recursion); passed to table2string
function utils._format_value(value, fmt, done)
    local quote_string = false
    fmt = fmt or ""
    if fmt == "q" then
        quote_string = true
    elseif fmt ~= "" then
        error("unknown format specifier: '"..fmt.."'")
    end

    local ptype = type(value)
    if ptype == "userdata" then
        -- these functions need to be regged by D code
        if d_isobject and d_isobject(value) and Object.toString then
            return Object.toString(value)
        end
    elseif ptype == "table" then
        return utils.table2string(value, done)
    elseif ptype == "string" then
        if quote_string then
            return string.format("%q", value)
        end
    end

    return tostring(value)
end

do -- unittest
    assert(utils.format("a {}", 5) == "a 5")
    assert(utils.format("a {} {}", 5, 6) == "a 5 6")
    assert(utils.format("a {3} {2} {1}", 5, 6, 7) == "a 7 6 5")
end

-- format a table for debug purposes
-- mainly for use with format()
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
    -- try to follow the convention of table constructors (see Lua manual)
    -- the tricky part is to produce useful results for both arrays and AAs
    -- (they can be mixed, too)
    local res = "{"
    local function item(keypart, v)
        if #res > 1 then
            res = res .. ", "
        end
        res = res .. utils.format_r(done_set, "{}{:q}", keypart, v)
    end
    -- array part (covers [1, index) )
    local index = 1
    while true do
        local v = t[index]
        if not v then
            break
        end
        item("", v)
        index = index + 1
    end
    -- AA part
    for k, v in pairs(t) do
        if utils.isInteger(k) and k >= 1 and k < index then
            -- skip, must already have been formatted above
        else
            local keypart
            if type(k) == "string" then
                -- xxx should only do this if string is a valid Lua ID
                --     if not, print it quoted, like in the else case
                keypart = k .. " = "
            else
                -- (:q means only quote strings)
                keypart = utils.format_r(done_set, "[{:q}] = ", k)
            end
            item(keypart, v)
        end
    end
    return res .. "}"
end

-- emulation of some features of utils.randval.RandomValue
-- return a table suitable to be demarshalled to RandomValue
--  max is optional and will be set to min if nil
function utils.range(min, max)
    -- whatever you do here, cross-check with utils.range_sample for consistency
    if type(min) == "string" then
        -- parse range from a string
        local strval = min
        -- try string with single number
        min = tonumber(strval)
        -- failed? so try 2 numbers
        if not min then
            -- try n1:n2
            min, max = string.match(strval, "(%-?%d+):(%-?%d+)")
            -- fail? try n1-n2 (no negative second number)
            if not min then
                min, max = string.match(strval, "(%-?%d+)%-(%d+)")
            end
            min = tonumber(min)
            max = tonumber(max)
            assert(min and max)
        end
    end
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
-- this function has three forms:
--  range_sample(some_range_table)
--  range_sample(a)     -- return a
--  range_sample(a, b)  -- behaves like range_sample(range(a, b))
-- returns a value x: a <= x <= b
-- to see which version is applied, utils.is_range() is used
-- further, since Lua doesn't distinguish ints and floats, there are different
--  versions for each of them

local function Random_rangei(...)
    return Random:rangei(...)
end
local function Random_rangef(...)
    return Random:rangef(...)
end

-- integers
function utils.range_sample_i(...)
    return utils.range_sample_g(Random_rangei, ...)
end
-- floats
function utils.range_sample_f(...)
    return utils.range_sample_g(Random_rangef, ...)
end

-- any type that supports __add, __sub and __mul
-- separate to not allocate a closure on each call
local function _range_any_random(a, b)
    return a + (b-a)*Random:rangef(0, 1)
end
function utils.range_sample(...)
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

-- global text output functions (for logging/debugging)

-- just print something, and don't be as inconvenient as print()
-- but trailing (useless) arguments are ignored, unlike with print()
-- also see the logging API in table log below
function printf(...)
    print(utils.format(...))
end

-- this table contains the logging functions as generated from log_priorities
-- e.g. there's "Warn" in log_priorities; for that, it generates:
--  log.Warn = "Warn" -- like the stringified enum member in LogPriority
--  function log.warn(...) -- like printf(), but pass the resulting string to
--                            D's d_logoutput() function
-- Be aware that they all do formatted printing, e.g. log.warn(s) will translate
--  '{}' sequences within s, if s is a string.
-- Note: unlike the D version, using log.trace() may be quite costly, even if
--  the log level prevents displaying trace log events
log = {}

function log.emit(priority, ...)
    local s = utils.format(...)
    if d_logoutput then
        d_logoutput(priority, s)
    else
        -- fallback if D host doesn't provide d_logoutput
        print(priority .. ":", s)
    end
end

-- these correspond to LogPriority in src/utils/log.d
local log_priorities = { "Trace", "Minor", "Notice", "Warn", "Error" }
for i, name in ipairs(log_priorities) do
    -- enum-style identifier for a log-level
    log[name] = name
    -- output function, basically a shortcut for log.emit()
    log[string.lower(name)] = function(...)
        log.emit(name, ...)
    end
end

-- global convenience functions (mainly when in interactive interpreter)
-- I consider them Lua language deficiencies *g*
-- to fix Lua, they just have to be global

local function dodir(t, match, level, done)
    if type(t) ~= "table" and type(t) ~= "userdata" then
        return
    end
    if done[t] then
        printf("[recursive metatable]")
        return
    end
    done[t] = true
    -- skip for userdata, but recurse into metatable later
    if type(t) ~= "userdata" then
        for k, v in pairs(t) do
            if not match or type(k) ~= "string" or string.match(k, match) then
                printf("{}{} {}", level, type(v), k)
            end
        end
    end
    local meta = getmetatable(t)
    if meta then
        meta = meta.__index
    end
    dodir(meta, match, level .. ":", done)
end
-- show list of members in current scope
-- if t is not nil, list members of t instead
-- recurses into metatables; members from metatables have ":" on their types
-- if t or x is a string, it pattern matches the items in table _G or t
--  the pattern can contain * as in shell globbing
function dir(t, x)
    if type(t) == "string" then
        x = t
        t = nil
    end
    if x then
        assert(type(x) == "string")
        -- turn every * into .* (glob pattern to Lua pseudo-regex pattern)
        -- also, match begin and end with ^ $
        x = "^" .. string.gsub(x, "%*", ".*") .. "$"
    end
    t = t or _G
    dodir(t, x, "", {})
end

-- there's also math.max, math.min
-- they accept more than 2 args, but numbers only
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

-- assert that a value is of a specific type
-- further value must not be nil
-- the function always returns value (similar to assert())
function T(a_type, value)
    -- xxx could be improved (e.g. better error messages)
    --     also maybe disable checks in release mode
    if type(a_type) == "table" then
        -- make sure it works for both D and Lua "classes"
        if type(value) == "table" then
            -- Lua "classes"
            assert(getmetatable(value) == a_type)
        elseif type(value) == "userdata" then
            -- wrapped D object
            -- T() is magically provided by lua.d and handles inheritance etc.
            a_type.T(value)
        else
            assert(false)
        end
    else
        -- whatever, maybe accept stuff like T("string", "blabla")
        assert(type(value) == a_type)
    end
    return value
end

-- like T(), but accept if value is nil
function Tn(a_type, value)
    if rawequal(value, nil) then
        return value
    end
    return T(a_type, value)
end

-- xxx the following functions really should be in their own table?

-- duplicate the table (but not its values)
function table_copy(table)
    local ntable = {}
    for k, v in pairs(table) do
        ntable[k] = v
    end
    -- preserve metatable
    setmetatable(ntable, getmetatable(table))
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
function table_empty(table)
    local key, value = next(table)
    return not key
end

-- return array of keys
function table_keys(table)
    local r = {}
    for k, v in pairs(table) do
        r[#r+1] = k
    end
    return r
end

-- return array of values
function table_values(table)
    local r = {}
    for k, v in pairs(table) do
        r[#r+1] = v
    end
    return r
end

-- remove table entry; return its old value or the default
function pick(t, key, def)
    local val = t[key]
    t[key] = nil
    return ifnil(val, def)
end

-- array functions
array = {}

-- a1 and a2 are expected to be arrays (basically means '#' should work)
-- items are compared with ==
function array.equal(a1, a2)
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

-- Randomly permutate the passed array
function array.randomize_inplace(arr)
    local len = #arr
    for i = 1, len do
        local ri = Random:rangei(i, len)
        arr[i], arr[ri] = arr[ri], arr[i]
    end
end

-- execute conv on each array item; return array with the returned values
function array.map(arr, conv)
    local narr = table_copy(arr)
    for i = 1, #narr do
        narr[i] = conv(narr[i])
    end
    return narr
end

-- execute the filter function on each array item
-- return a new array with all items for which fn returned a truth value
function array.filter(arr, fn)
    local narr = {}
    for i, v in ipairs(arr) do
        if fn(v) then
            narr[#narr + 1] = v
        end
    end
    return narr
end

-- (item == nil is a no-op)
function array.append(arr, item)
    arr[#arr + 1] = item
end

-- lua sure is a nice programming language
-- according to #lua, you have to concat arrays manually
-- table.concat and .. only work for strings or arrays of numbers (?!?!?!)
-- this function returns the concatenation of all passed arrays
-- passing non-arrays isn't possible (this isn't D's ~ operator)
function array.concat(...)
    local res = {}
    local n = 1
    for i = 1, select("#", ...) do
        local arr = select(i, ...)
        for k2, v2 in ipairs(arr) do
            res[n] = v2
            n = n + 1
        end
    end
    return res
end

-- join table entries as string
-- not in Lua stdlib??
function array.join(arr, separator)
    if not arr[1] then
        return ""
    end
    local res = "" .. arr[1]
    separator = separator or ", "
    for i = 2, #arr do
        res = res .. separator .. arr[i]
    end
    return res
end

-- return an array rotated left by the specified number of items - 1
-- the returned array will have arr[by] as first element
function array.rotated(arr, by)
    assert(by > 0, "not sure if negative shifting works")
    assert(by ~= 0)
    local narr = {}
    local len = #arr
    for i = 1, len do
        -- 1 based indices make it inconvenient
        narr[i] = arr[((by + i - 2) % len) + 1]
    end
    return narr
end

-- unittest lol
do
    local arr = {1,2,3}
    assert(array.equal(array.rotated(arr, 1), {1,2,3}))
    assert(array.equal(array.rotated(arr, 2), {2,3,1}))
    assert(array.equal(array.rotated(arr, 3), {3,1,2}))
    assert(array.equal(array.rotated(arr, 4), {1,2,3}))
end

-- return elements in reverse order
function array.reversed(arr)
    local len = #arr
    local narr = {}
    for i = 1, len do
        narr[i] = arr[len - (i - 1)]
    end
    return narr
end

-- unittest
assert(array.equal(array.reversed({1,2,3}), {3,2,1}))

-- use == to find an element; return nil if not found
function array.indexof(arr, item)
    for i, v in ipairs(arr) do
        if v == item then
            return i
        end
    end
    return nil
end

-- remove item at index, shift down all elements after this
-- returns parameter arr (modifies array by reference)
function array.remove(arr, index)
    local len = #arr
    assert(index >= 1 and index <= len)
    for i = index, len + 1 do
        arr[i] = arr[i + 1]
    end
    return arr
end

do -- unittest
    assert(array.equal(array.remove({1,2,3}, 1), {2,3}))
    assert(array.equal(array.remove({1,2,3}, 2), {1,3}))
    assert(array.equal(array.remove({1,2,3}, 3), {1,2}))
end

-- remove first array element that is equal (==) to value
-- don't do anything if not found
function array.remove_value(arr, value)
    local idx = array.indexof(arr, value)
    if idx then
        array.remove(arr, idx)
    end
end

array.copy = assert(table_copy)

-- find out if this is a valid array
-- an array is a table with #table integer keys in range 1, ..., #table
-- expensive because it checks each element
function array.is_array(table)
    if type(table) ~= "table" then
        return false
    end
    -- # returns an integer key i with table[i] ~= nil and table[i+1] == nil
    local len = #table
    local count = 0
    for k, v in pairs(table) do
        if not (utils.isInteger(k) and k >= 1 and k <= len) then
            return false
        end
        count = count + 1
    end
    return count == len
end

-- extend Lua standard "packages"

function string.startswith(s, prefix)
    return string.sub(s, 1, #prefix) == prefix
end

function string.endswith(s, suffix)
    return string.sub(s, #suffix) == suffix
end

-- the following functions apparently partially rely on the D wrapper
-- actually, those should be moved into a plugins.lua

-- returns the calling module's export table
-- equal to _G[ENV_NAME] (initialized to table if empty)
function export_table()
    -- use caller's environment
    setfenv(1, getfenv(2))
    assert(ENV_NAME)
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

-- copy all entries in table to _G
function export_from_table(table)
    for name, e in pairs(table) do
        _G[name] = e
    end
end

-- minor premature coroutine support

-- handle coroutine "scheduling" (or whatever)
local function mayrun(cor)
    -- not sure what should go in here...
    local status, cmd_or_err, p = coroutine.resume(cor)
    if not status == true then
        local msg = utils.format("{}", cmd_or_err)
        if debug and debug.traceback then
            -- xxx a bit whacky
            msg = debug.traceback(cor, msg)
        end
        error("when running coroutine: " .. msg)
    end
    if cmd_or_err == "sleep" then
        return
    elseif cmd_or_err == nil then
        return
    else
        error(utils.format("invalid coroutine return: {}", cmd_or_err))
    end
end

-- create and run a couroutine
function cospawn(fn)
    mayrun(coroutine.create(fn))
end

-- put a coroutine to sleep for some time (time values see time.lua)
function cosleep(t)
    local co = assert(coroutine.running())
    addTimer(t, function()
        mayrun(co)
    end)
    coroutine.yield("sleep")
end

-- some command line interpreter support
-- should probably be moved into its own module

ConsoleUtils = {}

-- execute a line of Lua code (either statement or expression)
-- print out result
-- msgSink: void delegate(string)
function ConsoleUtils.exec(line, msgSink)
    local errSink = log.error
    local noticeSink = log.notice
    if msgSink then
        errSink = function(...)
            msgSink(utils.format(...))
            msgSink("\n")
        end
        noticeSink = errSink
    end
    assert(type(line) == "string")
    -- first try to prepend return in order to get the value the code returns
    -- it also allows to execute expressions like "1+2"
    local real = "return " .. line
    local fn, err = loadstring(real)
    if not fn then
        real = line
        fn, err = loadstring(real)
    end
    -- somehow looks less confusing to include the command in the output
    -- xxx disabled for now, as it depends on console internals (print target,
    --     prompt string); now handled by LuaInterpreter directly (loses leading
    --     "return", but that was confusing anyway)
    -- printf("> {}", real)
    if not fn then
        errSink("Error: {}", err)
        return false
    end
    -- execute the function
    -- if errors happen, let the caller of script_exec handle it?
    -- it uses the global scope (see loadstring())
    local function capture(err, ...) -- catch nil return values
        return err, {n = select("#", ...), ...}
    end
    --[[ works, but it looks ugly: backtrace too big, maybe isn't useful either
    local function errhandler(err)
        -- if a "recoverable" D exception was thrown, err will be a D Exception,
        --  and its toString will return something useful - not a full
        --  backtrace, though
        -- thus, we do whatever we do
        if debug then
            err = utils.format("{}", err) .. "\n" .. debug.traceback()
        end
        return err
    end
    local ok, res = capture(xpcall(fn, errhandler))
    ]]
    local ok, res = capture(pcall(fn))
    if not ok then
        errSink("Lua error: {}", res[1])
        return false
    end
    -- print result (only if not nil)
    if res.n > 1 or res[1] ~= nil then
        local s = "result = "
        for i = 1, res.n do
            if i > 1 then
                s = s .. ", "
            end
            s = s .. utils.format("{:q}", res[i])
        end
        noticeSink("{}", s)
    end
    return true
end

-- return auto-completion possibilities for the given line
-- the line is a string, with c_start and c_end being indices into line
-- c_start is the current cursor position
-- c_end, if present, is the end of the selection
-- indices are 1 based
-- returns a table that in D is defined as:
--    struct CompletionResult {
--        //indices of the prefix into the current command line
--        //e.g. "abc.def<tab>" => match_start, match_end = 5, 8
--        int match_start, match_end;
--        //possible matches (only those which match the prefix)
--        string[] matches;
--        //more than the fixed maximum number of matches available
--        bool more;
--    }
function ConsoleUtils.autocomplete(line, c_start, c_end)
    -- right now, the completion is as simple as possible
    -- c_end is ignored for now
    -- it just looks at the whole string and follows identifiers and . and :
    --  operators
    -- feel free to add more capabilities as needed
    local cur = _G
    local pos = 1
    local last_from, last_to, last_id

    -- complete from cursor, ignore the rest
    line = line:sub(1, c_start - 1)
    -- xxx: should strip whitespace from beginning

    -- all the following functions have to follow the "index" metatable event
    -- (see http://www.lua.org/manual/5.1/manual.html#2.8 "index" event)
    local function listable(x)
        return type(x) == "table" or type(x) == "userdata"
    end
    local function getiter(x)
        if type(x) == "table" then
            return pairs(x)
        else
            return pairs({})
        end
    end
    local function nextlist(x)
        -- xxx not safe against cyclic metatables/metamethods
        local t = getmetatable(x)
        if t == nil then
            return nil
        end
        t = t.__index
        -- could be a function, we can't follow a function
        if type(t) ~= "table" then
            return nil
        else
            return t
        end
    end

    -- local fragments = {}

    while true do
        -- get identifier in the beginning
        local from, to, id = line:find("([%w_]+)", pos)
        if not from then
            break
        end
        -- follow table and advance search position
        -- the next find will skip any '.', ':' or unexpected code
        -- xxx can call user metamethods (which may misbehave)
        local n = cur[id]
        to = to + 1 -- find() is weird and returns inclusive-end range
        pos = to
        last_from, last_to, last_id = from, to, id
        if n then
            cur = n
        else
            break
        end
        if not listable(n) then
            break
        end
    end

    -- end of whatever doesn't fall on end of line => user probably has a '.'
    --  or ':' at the end => skip previous id, start new id as empty string
    if (not last_to) or (last_to ~= #line + 1) then
        last_to = #line + 1
        last_from = #line + 1
        last_id = ""
    end

    local matches = {}
    local MAX = 10
    local more = false
    local function addmatch(s)
        if #matches > MAX then
            more = true
            return false
        else
            matches[#matches+1] = s
            return true
        end
    end

    -- in the completion case, we will have some table cur, and a last_id which
    --  is a prefix that should be used for completion
    -- find all identifiers in that table, and filter what matches to last_id
    if listable(cur) then
        while cur and last_id do
            for name, val in getiter(cur) do
                if type(name) == "string" and name:startswith(last_id) then
                    if not addmatch(name) then
                        break
                    end
                end
            end
            cur = nextlist(cur)
        end
    elseif type(cur) == "function" then
        -- add '()', which is convenient most time
        last_to = #line + 1
        last_from = #line + 1
        last_id = ""
        addmatch("()")
    end

    local res = {
        -- also adjust to D slice indices
        match_start = (last_from and last_from) or 1,
        match_end = (last_to and last_to) or 1,
        matches = matches,
        more = more,
    }
    --printf(res)
    return res
end

