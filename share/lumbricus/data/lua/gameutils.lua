
-- global table to map GameObject => Lua context
_dgo_contexts = {}

-- d_game_object = a D GameObject
-- dont_init = if true, return nil if no context was set yet
--  (normally you would always call it like get_context(obj) )
-- returns a context table for a GameObject, where Lua code can store arbitrary
--  values; the context for a new GameObject is always {}
function get_context(d_game_object, dont_init)
    local res = _dgo_contexts[d_game_object]
    if not res and not dont_init then
        assert(d_game_object)
        assert(GameObject_objectAlive(d_game_object))
        res = {}
        _dgo_contexts[d_game_object] = res
    end
    return res
end

-- called by game.d as objects are removed
function game_kill_object(d_game_object)
    _dgo_contexts[d_game_object] = nil
end

-- random helper functions

function spawnSprite(name, pos, velocity)
    local s = Game_createSprite(name)
    local t = Game_ownedTeam()
    if (t) then
        GameObject_set_createdBy(s, Member_sprite(Team_current(t)))
    end
    if (velocity) then
        Phys_setInitialVelocity(Sprite_physics(s), velocity)
    end
    Sprite_activate(s, pos)
end

-- this is just a test

function createTestWeapon(name)
    local w = LuaWeaponClass_ctor(Gfx, name)
    local function createShooter(firing_sprite)
        printf("GOODBYE LOL")
        return null -- LuaShooter_ctor(...
    end
    LuaWeaponClass_set_onCreateShooter(w, createShooter)
    LuaWeaponClass_setParams(w, {
        category = "fly",
        animation = "bazooka",
        icon = Gfx_resource("icon_bazooka"),
    })
    Gfx_registerWeapon(w)
    return w
end

-- instead of this, the script should just be loaded at the right time
addGlobalEventHandler("game_init", function(sender)
    -- comment the following line to prevent weapon from being loaded
    createTestWeapon("bozaaka")
end)
