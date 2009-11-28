-- utils is like a static class or a package
-- maybe this should be done differently; I don't know
utils = {}

-- format anything (for convenience)
-- unlike string.format(), you can format anything, including table
-- it also uses Tango/C# style {} instead of %s
-- uses the __tostring function if available, else dumps table contents
-- allowed inside {}:
--      - ':q' if param is a string, quote it (other types aren't quoted)
--      - no param indizes yet (should be easy to add if needed)
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
        local quote_string = false
        if f == ":q" then
            quote_string = true
        else
            if #f > 0 then
                assert(false, "unknown format specifier: '"..f.."'")
            end
        end
        -- format the parameter
        local param = args[idx]
        local ptype = type(param)
        if ptype == "userdata" then
            -- this function needs to be regged by D code
            out(ObjectToString(param))
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

-- show list of members of current scope
-- if t is not nil, list members of t instead
function dir(t)
    -- xxx should this recurse somehow into metatables or something?
    for k, v in pairs(t or _G) do
        utils.formatln("{} {}", type(v), k)
    end
    print("done.")
end
