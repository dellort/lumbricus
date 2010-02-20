local _cache = {}

-- takes a userdata and converts it to a Lua table with a proper metatable
-- the wrapper isn't fully complete; e.g. functions don't take or return wrapped
--  objects (the proper place to implement this would be lua.d)
-- note that although the metatables are cached, the instances are not
-- also note: doesn't work with singletons
function wrap(x)
    if not d_islightuserdata(x) then
        return x -- ???
    end
    local meta = wrap_metatable(d_get_class(x))
    return setmetatable({ native = x }, meta)
end

-- class = D ClassInfo or a string refering to the class prefix
function wrap_metatable(class)
    if type(class) == "string" then
        class = d_find_class(class)
    end
    if not class then
        return nil
    end
    local meta = _cache[class]
    if meta then
        return meta
    end
    -- create & fill the metatable
    meta = {}
    meta.__index = meta
    local infos = d_get_class_metadata(class)
    for i, entry in ipairs(infos) do
        local t = entry.type
        local name = entry.name
        local fn = _G[entry.lua_g_name]
        assert(fn and type(fn) == "function")
        -- apparently you could use a function for __index and __newindex to
        --  simulate setters and getters for properties, but it doesn't seem to
        --  be worth the trouble -> properties are always methods
        if t == "Method" or t == "Property_R" or t == "Property_W" then
            if t == "Property_W" then
                name = "set_" .. name
            end
            -- sadly, have to create a closure for each method/property
            meta[name] = function(inst, ...)
                return fn(inst.native, ...)
            end
        elseif t == "Ctor" or t == "StaticMethod" then
            meta[name] = fn
        end
    end
    _cache[class] = meta
    return meta
end
