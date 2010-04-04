-- "shortcut" functions for debugging and cheating

local E = {} -- whatever

function ownedTeam()
    assert(getCurrentInputTeam)
    return getCurrentInputTeam()
end

function E.giveWeapon(name, amount)
    Team_addWeapon(ownedTeam(), lookupResource(name), amount or 1)
end

function weaponList()
    local cls = d_find_class("WeaponClass")
    assert(cls)
    return ResourceSet_findAllDynamic(Game_resources(), cls)
end

-- drop a crate with a weapon in it; p is a string for the weapon
function E.dropCrate(p, spy)
    local stuff = {
        doubledamage = CollectableToolDoubleDamage_ctor,
        doubletime = CollectableToolDoubleTime_ctor,
        bomb = CollectableBomb_ctor,
        spy = CollectableToolCrateSpy_ctor,
        medkit = CollectableMedkit_ctor,
    }
    if type(p) ~= "string" then
        printf("pass as parameter any tool of {}, or any weapon name of {}",
            table_keys(stuff), array.map(weaponList(),
                function(w) return WeaponClass_name(w) end))
        printf("pass 'defaultcrate' or '' to drop controller-chosen contents")
        printf("will always enable crate spy unless second param is false")
        return
    end
    local fill
    if stuff[p] then
        fill = {stuff[p]()}
    elseif p == "defaultcrate" or p == "" then
        fill = {}
    else
        local w = lookupResource(p, true)
        if w then
            fill = {CollectableWeapon_ctor(w, WeaponClass_crateAmount(w))}
        end
    end
    if not fill then
        printf("don't know what '{}' is", p)
        return
    end
    Control_dropCrate(true, fill)
    if ifnil(spy, true) then
        E.crateSpy()
    end
end

-- give all teams a crate spy
function E.crateSpy()
    for k,t in ipairs(Control_teams()) do
        Team_set_crateSpy(t, 1)
    end
end

-- the caller wins
function E.allYourBaseAreBelongToUs()
    for k,t in ipairs(Control_teams()) do
        if (t ~= ownedTeam()) then
            Team_surrenderTeam(t)
        end
    end
end

-- +500 hp for caller, 1 hp for others
function E.whosYourDaddy()
    for k,t in ipairs(Control_teams()) do
        for k,m in ipairs(Team_getMembers(t)) do
            if (t == ownedTeam()) then
                Member_addHealth(m, 500)
            else
                p = Sprite_physics(Member_sprite(m))
                -- xxx last optional argument doesn't work??
                Phys_applyDamage(p, Phys_lifepower(p) - 1, 2, nil)
            end
        end
    end
end

-- amount (or 10 if omitted) of all weapons
function E.greedIsGood(amount)
    for k,w in ipairs(weaponList()) do
        Team_addWeapon(ownedTeam(), w, amount or 10)
    end
end

function E.katastrophe()
    local lb = Level_landBounds()
    World_objectsAt(Level_worldCenter(), 2000, function(obj)
        if className(Phys_backlink(obj)) ~= "WormSprite" then
            return true
        end
        local dest
        while (dest == nil) do
            dest = Vector2(Random_rangef(lb.p1.x, lb.p2.x),
                Random_rangef(lb.p1.y, lb.p2.y))
            dest = World_freePoint(dest, 6)
        end
        Worm_beamTo(Phys_backlink(obj), dest)
        return true
    end)
end

function E.snowflake(depth, interpolate)
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
        return array.concat(
            koch(from, s1, l), koch(s1, p_h, l),
            koch(p_h, s2, l), koch(s2, to, l))
    end

    local fill = lookupResource("border_segment") -- just some random bitmap for now
    local border = lookupResource("rope_segment")
    local gls = Game_gameLandscapes()[1]
    local ls = GameLandscape_landscape(gls)
    local s = LandscapeBitmap_size(ls)
    local len = min(s.x, s.y)/3
    local c = s/2
    -- I don't know where the center of a koch snowflake is *shrug*
    local p1 = c+Vector2(-len, len)
    local p3 = c+Vector2(len, len)
    local p2 = get_h(p1, p3)
    local arr = array.concat(koch(p1, p2), koch(p2, p3), koch(p3, p1))

    -- first clear the landscape before rendering the snowflake
    LandscapeBitmap_addPolygon(ls,
        {Vector2(0,0), Vector2(s.x,0), s, Vector2(0,s.y)}, Vector2(0,0), nil,
        Lexel_free)

    LandscapeBitmap_addPolygon(ls, arr, Vector2(0,0), fill, Lexel_soft,
        interpolate)
    LandscapeBitmap_drawBorder(ls, Lexel_soft, Lexel_free, border, border)
end

function E.horror()
    if not bouncy_class then
        bouncy_class = createSpriteClass {
            name = "x_bouncy",
            initPhysic = relay {
                collisionID = "always",
                radius = 5,
                mass = 1,
                elasticity = 0.5,
                --bounceAbsorb = 0.1,
                --friction = 0.9,
            },
            sequenceType = "s_bazooka",
        }
    end

    if true then
        local o1 = SpriteClass_createSprite(bouncy_class)
        Sprite_activate(o1, Vector2(3000-100, 1000))
        local o2 = SpriteClass_createSprite(bouncy_class)
        Sprite_activate(o2, Vector2(3000+100, 1000))
        local c1 = PhysicObjectsRod_ctor(Sprite_physics(o1),
            Sprite_physics(o2))
        World_add(c1)
        local o3 = SpriteClass_createSprite(bouncy_class)
        Sprite_activate(o3, Vector2(3000, 1000+200))
        local c2 = PhysicObjectsRod_ctor(Sprite_physics(o1),
            Sprite_physics(o3))
        World_add(c2)
        local c3 = PhysicObjectsRod_ctor(Sprite_physics(o2),
            Sprite_physics(o3))
        World_add(c3)
    else
        -- grid
        local X = {}
        local S = Vector2(2500, 1000)
        local D = 50
        local H = 5
        for y = 1, H do
            X[y] = {}
            for x = 1, H do
                local o = SpriteClass_createSprite(bouncy_class)
                Sprite_activate(o, S + Vector2(x-1, y-1)*D)
                X[y][x] = o
            end
        end
        -- connect each object with the bottom and right neighbour
        for y = 1, H do
            for x = 1, H do
                local o = Sprite_physics(X[y][x])
                if x < H then
                    local r = Sprite_physics(X[y][x+1])
                    local c1 = PhysicObjectsRod_ctor(o, r)
                    World_add(c1)
                end
                if y < H then
                    local b = Sprite_physics(X[y+1][x])
                    local c2 = PhysicObjectsRod_ctor(o, b)
                    World_add(c2)
                end
                --[[
                if x < H and y < H then
                    local n = Sprite_physics(X[y+1][x+1])
                    local c3 = PhysicObjectsRod_ctor(o, n)
                    World_add(c3)
                end
                --]]
            end
        end
    end
end

-- some test
function E.guitest()
    -- adding something to game scene
    local s = Game_scene()
    local f = SceneDrawBox_ctor()
    SceneDrawBox_set_rc(f, Rect2(2000,1000,2500,1500))
    SceneDrawBox_set_zorder(f, 10)
    Scene_add(s, f)
    -- adding an actual GUI element to the hud
    local w = Gui_ctor()
    setProperties(w, {
        OnHandleKeyInput = function(info)
            printf("key input: {}", info)
            return true
        end,
        OnHandleMouseInput = function(info)
            printf("mouse input: {}", info)
            return true
        end,
        OnMouseLeave = function()
            printf("mouse leave")
        end,
        OnSetFocus = function(s)
            printf("focus: {}", s)
        end,
        OnMap = function(rc)
            printf("map: {}", rc)
        end,
        OnUnmap = function()
            printf("unmap")
        end,
    })
    Gui_set_sizeRequest(w, Vector2(100))
    local x = SceneDrawBox_ctor()
    SceneDrawBox_set_rc(x, Rect2(0,0,100,100))
    Gui_set_render(w, x)
    GameFrame_addHudWidget(w)
    -- keybinds
    local binds = KeyBindings_ctor()
    KeyBindings_addBinding(binds, "huh2", "x mod_ctrl")
    KeyBindings_addBinding(binds, "huh1", "x")
    local function h(s)
        printf("keybind: '{}'", s)
    end
    GameFrame_addKeybinds(binds, h)
end

-- best used with newgame_bench.conf
function E.benchNapalm()
    local napalm = worms_shared.standard_napalm
    assert(napalm)
    -- this thing is just so we can use spawnCluster()
    if not spawner_class then
        spawner_class = createSpriteClass {
            name = "x_some_napalm_spawner",
            initPhysic = relay {
                fixate = Vector2(0, 0),
            },
        }
    end
    local spawner = SpriteClass_createSprite(spawner_class)
    Sprite_activate(spawner, Vector2(3000, 1700))
    local maxtime = currentTime() + time("5s")
    local up = Vector2(0, -1)
    Game_benchStart(time("20s"))
    addPeriodicTimer(time("100ms"), function(timer)
        if currentTime() >= maxtime then
            Sprite_kill(spawner)
            timer:cancel()
            return
        end
        spawnCluster(napalm, spawner, 50, 50, 100, 20, up)
    end)
end

export_from_table(E)
