-- only implemented here because it's too inconvenient to do in D without
--  resorting to circular dependencies and stuff (at least so I thought)

local function loadSpriteClass(ctor, file)
    local node = loadConfig(file, true)
    local name = ConfigNode_get(node, "name")
    local s = ctor(Gfx, name)
    SpriteClass_loadFromConfig(s, node)
    Gfx_registerSpriteClass(s)
end

loadSpriteClass(WormSpriteClass_ctor, "worm.conf")
