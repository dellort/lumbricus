-- "shortcut" functions for server exec (you could also say "cheats")

function giveWeapon(name, amount)
    Team_addWeapon(Game_ownedTeam(), Gfx_findWeaponClass(name), amount)
end

function spawnSprite(name, pos, velocity)
    local s = Game_createSprite(name)
    local t = Game_ownedTeam()
    if (t) then
        Obj_set_createdBy(s, Member_sprite(Team_current(t)))
    end
    if (velocity) then
        Phys_setInitialVelocity(Sprite_physics(s), velocity)
    end
    Sprite_activate(s, pos)
end

-- the caller wins
function allYourBaseAreBelongToUs()
    for k,t in ipairs(Control_teams()) do
        if (t ~= Game_ownedTeam()) then
            Team_surrenderTeam(t)
        end
    end
end

-- +500 hp for caller, 1 hp for others
function whosYourDaddy()
    for k,t in ipairs(Control_teams()) do
        for k,m in ipairs(Team_getMembers(t)) do
            if (t == Game_ownedTeam()) then
                Member_addHealth(m, 500)
            else
                p = Sprite_physics(Member_sprite(m))
                Phys_applyDamage(p, Phys_lifepower(p) - 1, 2)
            end
        end
    end
end

-- amount (or 10 if omitted) of all weapons
function greedIsGood(amount)
    for k,w in ipairs(Gfx_weaponList()) do
        Team_addWeapon(Game_ownedTeam(), w, amount or 10)
    end
end

function katastrophe()
    local lb = Level_landBounds()
    World_objectsAtPred(Level_worldCenter(), 2000, function(obj)
        local dest
        while (dest == nil) do
            dest = Vector2(Random_rangef(lb.p1.x, lb.p2.x), Random_rangef(lb.p1.y, lb.p2.y))
            dest = World_freePoint(dest, 6)
        end
        Worm_beamTo(Phys_backlink(obj), dest)
        return true
    end, function(obj)
        return className(Phys_backlink(obj)) == "WormSprite"
    end)
end

Lexel_free = 0
Lexel_soft = 1
Lexel_hard = 2

function snowflake(depth, interpolate)
    depth = depth or 1000
    interpolate = ifnil(interpolate, false)

    local function get_h(from, to)
        return from + (to-from)/2 + (to-from):orthogonal()*math.sqrt(3)/2
    end
    local function koch(from, to, l)
        l = ifnil(l, depth) - 1
        local dir = to-from
        if (dir:length() < 2) or (l <= 0) then
            return {from} -- {from, to}
        end
        local s1 = from + dir/3
        local s2 = to - dir/3
        local p_h = get_h(s1, s2)
        return concat(
            koch(from, s1, l), koch(s1, p_h, l),
            koch(p_h, s2, l), koch(s2, to, l))
    end

    local fill = Gfx_resource("border_segment") -- just some random bitmap for now
    local border = Gfx_resource("rope_segment")
    local ls = Game_landscapeBitmaps()[1]
    local s = LandscapeBitmap_size(ls)
    local len = min(s.x, s.y)/3
    local c = s/2
    -- I don't know where the center of a koch snowflake is *shrug*
    local p1 = c+Vector2(-len, len)
    local p3 = c+Vector2(len, len)
    local p2 = get_h(p1, p3)
    local arr = concat(koch(p1, p2), koch(p2, p3), koch(p3, p1))

    -- first clear the landscape before rendering the snowflake
    LandscapeBitmap_addPolygon(ls,
        {Vector2(0,0), Vector2(s.x,0), s, Vector2(0,s.y)}, Vector2(0,0), nil,
        Lexel_free)

    LandscapeBitmap_addPolygon(ls, arr, Vector2(0,0), fill, Lexel_soft,
        interpolate)
    LandscapeBitmap_drawBorder(ls, Lexel_soft, Lexel_free, border, border)
end


--------------------

-- global table to map GameObject => Lua context
_dgo_contexts = {}

-- d_game_object = a D GameObject
-- ctx = any Lua value
function set_context(d_game_object, ctx)
    -- xxx verify if d_game_object is really a GameObject
    _dgo_contexts[d_game_object] = ctx
end

-- return what was set with set_context() (or nil)
function get_context(d_game_object)
    return _dgo_contexts[d_game_object]
end

-- called by game.d as objects are removed
function game_kill_object(d_game_object)
    _dgo_contexts[d_game_object] = nil
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
