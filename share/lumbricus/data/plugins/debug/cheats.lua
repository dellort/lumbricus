-- "shortcut" functions for debugging and cheating

local E = {} -- whatever

function E.activeGameObjects()
    local cur = Game_gameObjectFirst()
    local list = {}
    while cur do
        if GameObject_activity(cur) then
            list[#list + 1] = cur
        end
        cur = Game_gameObjectNext(cur)
    end
    return list
end

function E.activityList()
    printf("-- Active game objects:");
    for i, g in ipairs(activeGameObjects()) do
        printf("  {}", g)
    end
    printf("-- end of list.")
end

function E.activityFix()
    -- xxx: sometimes kills of game.controller_plugins.ControllerMsgs
    --  in game, it also kills the active Team and TeamMember
    --  all of this above is a bit bogus
    for i, g in ipairs(activeGameObjects()) do
        printf("killing {}", g)
        GameObject_kill(g)
    end
end

-- get control over a random worm
-- will not work in network mode
function E.takeControl()
    for i, t in ipairs(Control_teams()) do
        Team_set_active(t, true)
        -- will be false if no worm available
        if Team_active(t) then
            break
        end
    end
end

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
function E.allYourBaseAreBelongToUs(slow)
    for k, t in ipairs(Control_teams()) do
        if (t ~= ownedTeam()) then
            if slow then
                for k2, m in ipairs(Team_members(t)) do
                    Member_addHealth(m, -9999)
                end
            else
                Team_surrenderTeam(t)
            end
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
                Phys_applyDamage(p, Phys_lifepower(p) - 1, 2)
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

function E.horror(gridToggle)
    if not bouncy_class then
        bouncy_class = createSpriteClass {
            name = "x_bouncy",
            initPhysic = relay {
                collisionID = "always",
                radius = 15,
                mass = 10,
                elasticity = 0.5,
                --bounceAbsorb = 0.1,
                --friction = 0.9,
                rotation = "distance",
            },
            sequenceType = "s_bazooka",
            --sequenceType = "s_antimatter_nuke",
        }
    end

    local function makeRod(obj1, obj2)
        local c = PhysicObjectsRod_ctor(obj1, obj2)
        PhysicObjectsRod_set_springConstant(c, 20000)
        PhysicObjectsRod_set_dampingCoeff(c, 10)
        World_add(c)
    end

    if not gridToggle then
        -- ring
        local N = 10
        local X = {}
        local R = 100
        local S = Vector2(3000, 1000)
        local center = SpriteClass_createSprite(bouncy_class)
        Sprite_activate(center, S)
        for n = 1, N do
            local o = SpriteClass_createSprite(bouncy_class)
            local dir = Vector2.FromPolar(1, math.pi*2/N * (n-1))
            Sprite_activate(o, S + dir * R)
            X[n] = o
        end
        for n = 1, N do
            local o1 = X[n]
            local o2 = X[(n % #X) + 1]
            makeRod(Sprite_physics(o1), Sprite_physics(o2))
            makeRod(Sprite_physics(o1), Sprite_physics(center))
        end
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
                    makeRod(o, r)
                end
                if y < H then
                    local b = Sprite_physics(X[y+1][x])
                    makeRod(o, b)
                end
                ----[[
                -- actually adds more stability...
                if x < H and y < H then
                    local n = Sprite_physics(X[y+1][x+1])
                    makeRod(o, n)
                end
                --]]
            end
        end
    end
end

function E.springTest(count)
    count = count or 1

    if not springobj_class then
        springobj_class = createSpriteClass {
            name = "x_springobj",
            initPhysic = relay {
                collisionID = "always",
                radius = 15,
                mass = 10,
                elasticity = 0.5,
                --bounceAbsorb = 0.1,
                --friction = 0.9,
            },
            sequenceType = "s_grenade",
        }
    end

    local function makeAt(pos)
        local o = SpriteClass_createSprite(springobj_class)
        Sprite_activate(o, pos + Vector2(0, 200))

        local c = PhysicObjectsRod_ctor2(Sprite_physics(o), pos)
        PhysicObjectsRod_set_springConstant(c, 100)
        PhysicObjectsRod_set_dampingCoeff(c, 5)
        PhysicObjectsRod_set_length(c, PhysicObjectsRod_length(c))
        World_add(c)
    end

    local cpos = Vector2(3000, 1000)
    for i = 1, count do
        makeAt(cpos)
        cpos = cpos + Vector2(30, 0)
    end
end

local function initWormHoleClass()
    wormhole_class = createSpriteClass {
        name = "x_wormhole",
        initPhysic = relay {
            collisionID = "wormhole_enter",
            radius = 15,
            mass = 1/0, --inf
        },
        sequenceType = "s_blackhole_active",
    }
    wormhole_exit_class = createSpriteClass {
        name = "x_wormhole_exit",
        initPhysic = relay {
            collisionID = "wormhole_exit",
            radius = 15,
            mass = 1/0, --inf
        },
        sequenceType = "s_antimatter_nuke",
    }

    addSpriteClassEvent(wormhole_class, "sprite_activate", function(sender)
        addCircleTrigger(sender, 90, "wormhole_enter", function(trig, obj)
            local companion = get_context_var(sender, "companion")
            if not companion then
                return -- incorrectly initialized?
            end
            obj = Phys_backlink(obj)
            assert(obj)
            -- maybe add a timer and some sort of blending effect?
            Sprite_setPos(obj, Phys_pos(Sprite_physics(companion)))
        end)
    end)
end

-- src and dst are Vector2 instances for entry and exit center points
function E.wormHole(src, dst)
    if not wormhole_class then
        initWormHoleClass()
    end

    local entry = SpriteClass_createSprite(wormhole_class)
    local exit = SpriteClass_createSprite(wormhole_exit_class)

    set_context_var(entry, "companion", exit)
    set_context_var(exit, "companion", entry)

    Sprite_activate(entry, src)
    Sprite_activate(exit, dst)
end

-- like wormHole(), but use the GUI to receive two mouse clicks (src and dst)
function E.placeWormHole()
    pickTwoPos(wormHole)
end

-- output contents of any object to console
-- useful for showing D objects
function E.dumpObject(obj, outf)
    outf = outf or printf
    if type(obj) == "userdata" then
        outf("D object:")
        local md = d_get_obj_metadata(obj)
        -- find classes and sort them by inheritance
        local classes = {}
        for i, v in ipairs(md) do
            classes[v.dclass] = true
        end
        local sclasses = table_keys(classes)
        table.sort(sclasses, function(a, b)
            return not d_is_class(d_find_class(a), d_find_class(b))
        end)
        -- find readable properties
        local props_r, props_w = {}, {}
        for i, v in ipairs(md) do
            if not v.inherited then
                if v.type == "Property_R" then
                    props_r[v.name] = v
                elseif v.type == "Property_W" then
                    props_w[v.name] = v
                end
            end
        end
        -- output properties and their values, sorted by class
        outf("classes: {}", array.join(sclasses))
        for i, cls in ipairs(sclasses) do
            for name, v in pairs(props_r) do
                if cls == v.dclass then
                    local value = _G[v.lua_g_name](obj)
                    local t = "ro"
                    if props_w[name] then
                        t = "rw"
                    end
                    outf("  {}.{} [{}] = {:q}", v.dclass, v.name, t, value)
                end
            end
        end
    end
    outf("value of type '{}': {:q}", type(obj), obj)
end

function E.pickObjectAt(pos)
    local cls = d_find_class("Sprite")
    local obj = Game_gameObjectFirst()
    local best, best_pos
    while obj do
        if d_is_class(obj, cls) and Sprite_visible(obj) then
            local opos = Phys_pos(Sprite_physics(obj))
            if (not best) or
                ((pos - opos):length() < (pos - best_pos):length())
            then
                best, best_pos = obj, opos
            end
        end
        obj = Game_gameObjectNext(obj)
    end
    return best
end

-- pick with mouse, dump to Lua console
-- dowhat = optional function to execute on result
function E.pickObject(dowhat)
    dowhat = dowhat or dumpObject
    local w = Gui_ctor()
    local obj
    setProperties(w, {
        OnHandleKeyInput = function(info)
            if info.isDown and info.code == keycode("mouse_left") then
                GameFrame_removeHudWidget(w)
                dowhat(obj)
            end
            return true
        end,
        OnHandleMouseInput = function(info)
            obj = pickObjectAt(info.pos)
            return true
        end,
        OnDraw = function(canvas)
            if obj then
                Canvas_drawCircle(canvas, Phys_pos(Sprite_physics(obj)), 10,
                    Color(1,0,0))
            end
        end,
    })
    GameFrame_addHudWidget(w, "gameview")
end

-- xxx code duplication, but it's crap code anyway *shrug*
function E.pickPosition(dowhat)
    assert(dowhat)
    local w = Gui_ctor()
    local pos
    setProperties(w, {
        OnHandleKeyInput = function(info)
            if pos and info.isDown and info.code == keycode("mouse_left") then
                GameFrame_removeHudWidget(w)
                dowhat(pos)
            end
            return true
        end,
        OnHandleMouseInput = function(info)
            pos = info.pos
            return true
        end,
        OnDraw = function(canvas)
            if pos then
                Canvas_drawCircle(canvas, pos, 10, Color(1,0,0))
            end
        end,
    })
    GameFrame_addHudWidget(w, "gameview")
end

function E.pickMakeActive()
    pickObject(function(obj)
        local member = Control_memberFromGameObject(obj)
        if not member then
            printf("nope.")
            return
        end
        local team = Member_team(member)
        Control_deactivateAll()
        Team_set_active(team, true)
        Team_set_current(team, member)
    end)
end

function E.pickShowCollide()
    pickObject(function(obj)
        printf(Phys_collision(Sprite_physics(obj)))
    end)
end

function E.pickObjectIntoVar(var)
    pickObject(function(obj)
        _G[var] = obj
    end)
end

function E.freePoint(dowhat, r)
    dowhat = dowhat or dumpObject
    local w = Gui_ctor()
    local pos
    setProperties(w, {
        OnHandleKeyInput = function(info)
            GameFrame_removeHudWidget(w)
            return true
        end,
        OnHandleMouseInput = function(info)
            pos = info.pos
            return true
        end,
        OnDraw = function(canvas)
            if pos then
                local r = r or 10
                p = World_freePoint(pos, r)
                if p then
                    Canvas_drawCircle(canvas, p, r, Color(1,0,0))
                end
            end
        end,
    })
    GameFrame_addHudWidget(w, "gameview")
end

-- show dumpObject() output in a window
-- if obj is nil, use pickObject to pick an object
function E.guiPickObject(obj)
    local function show()
        local w = Gui_ctor()
        local txtrender = SceneDrawText_ctor()
        local txt = SceneDrawText_text(txtrender)
        Gui_set_render(w, txtrender)
        local updater
        local function update()
            --[[if not Gui_isLinked(w) then
                updater:cancel()
                return
            end]]
            local t = ""
            local function appendf(...)
                t = t .. utils.format(...) .. "\n"
            end
            dumpObject(obj, appendf)
            FormattedText_setText(txt, false, t)
        end
        updater = addPeriodicTimer(time("1s"), update)
        --[[
        setProperties(w, {
            OnUnmap = function()
                updater:cancel()
            end,
        })
        ]]
        GameFrame_addHudWidget(w, "window")
        update()
    end

    if not obj then
        pickObject(function(x)
            obj = x
            show()
        end)
    else
        show()
    end
end

-- sillyness

function landscapeFromPos(pos)
    assert(pos)
    local lcl = d_find_class("GameLandscape")
    assert(lcl)
    local obj = Game_gameObjectFirst()
    while obj do
        if d_is_class(obj, lcl) then
            local rc = GameLandscape_rect(obj)
            if rc:isInside(pos) then
                return obj
            end
        end
        obj = Game_gameObjectNext(obj)
    end
end

-- waits for the user to click twice
-- calls fn(pos1, pos2)
function E.pickTwoPos(fn)
    pickPosition(function(p)
        local pos1 = p
        pickPosition(function(p)
            local pos2 = p
            fn(pos1, pos2)
        end)
    end)
end

function E.blurb()
    pickTwoPos(function(p1, p2)
        local gls = landscapeFromPos(p1)
        if not gls then
            return
        end
        local offset = GameLandscape_rect(gls).p1
        p1 = p1 - offset
        p2 = p2 - offset
        local ls = GameLandscape_landscape(gls)
        local whatever = lookupResource("rope_segment")
        LandscapeBitmap_drawSegment(ls, whatever, Lexel_soft, p1, p2, 20)
    end)
end

--[[
function E.makePlane()
    pickTwoPos(function(p1, p2)
        local x = PhysicZonePlane_ctor(p1, p2)
        local z = ZoneTrigger_ctor(x)
        Phys_set_collision(z, CollisionMap_find("wormsensor"))
        World_add(z)
    end)
end
--]]

function E.dragObject()
    dowhat = dowhat or dumpObject
    local w = Gui_ctor()
    local obj
    local link
    setProperties(w, {
        OnHandleKeyInput = function(info)
            if info.code == keycode("mouse_left") then
                if info.isDown and obj and not link then
                    -- create the constraint
                    local phys = Sprite_physics(obj)
                    link = PhysicObjectsRod_ctor2(phys, Phys_pos(phys))
                    PhysicObjectsRod_set_springConstant(link, 100)
                    --PhysicObjectsRod_set_dampingCoeff(link, 5)
                    PhysicObjectsRod_setDampingRatio(link, 0.2)
                    World_add(link)
                else
                    if link then
                        Phys_kill(link)
                    end
                    GameFrame_removeHudWidget(w)
                end
            end
            return true
        end,
        OnHandleMouseInput = function(info)
            if link then
                PhysicObjectsRod_set_anchor(link, info.pos)
            else
                obj = pickObjectAt(info.pos)
            end
            return true
        end,
        OnDraw = function(canvas)
            if obj and not link then
                -- quite some lua heap activity (creating Vector2 and Color)
                Canvas_drawCircle(canvas, Phys_pos(Sprite_physics(obj)), 10,
                    Color(1,0,0))
            end
        end,
    })
    GameFrame_addHudWidget(w, "gameview")
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

-- utterly pointless, just for debugging and playing around
do
    local name = "marble"
    -- no "local", this is used in other weapons
    local class = createSpriteClass {
        name = "x_" .. name,
        initNoActivityWhenGlued = true,
        initPhysic = relay {
            collisionID = "always",
            mass = 10,
            radius = 2,
            explosionInfluence = 1.0,
            windInfluence = 0.0,
            elasticity = 0.6,
            glueForce = 120,
            rotation = "distance",
        },
        sequenceType = "s_clustershard",
    }
    -- I name it "The Marbler (tm)"
    local fire, interrupt, readjust = getMultipleOnFire(50, timeMsecs(60), nil,
        function(shooter, fireinfo)
            local spread = 5
            local a = Random_rangef(-spread/2, spread/2)
            dir = fireinfo.dir:rotated(a*math.pi/180)
            local dist = (fireinfo.shootbyRadius + 5) * 1.5 + 9 + 8
            local s = spawnSprite(shooter, class,
                fireinfo.pos + dir * dist, dir * 500)
        end
    )
    local w = createWeapon {
        name = "w_" .. name,
        onFire = fire,
        onInterrupt = interrupt,
        onReadjust = readjust,
        value = 10,
        category = "explosive",
        --icon = "icon_mine",
        animation = "weapon_flamethrower",
        fireMode = {
            direction = "any",
            --throwStrengthFrom = 40,
            --throwStrengthTo = 40,
        }
    }
    enableSpriteCrateBlowup(w, class)
end
function E.marbles()
    for i,t in ipairs(Control_teams()) do
        Team_addWeapon(t, lookupResource("w_marble"), 100)
    end
end

-- best used with newgame_bench.conf
function E.benchNapalm()
    benchSprite(worms_shared.standard_napalm)
end
function E.benchMine()
    benchSprite(ws_lua.mine_class)
end

function benchSprite(sprite_class)
    assert(sprite_class)
    -- this thing is just so we can use spawnCluster()
    if not spawner_class then
        spawner_class = createSpriteClass {
            name = "x_some_spawner",
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
        spawnCluster(sprite_class, spawner, 50, 50, 100, 20, up)
    end)
end

-- quite specialized functions to clear the freelist created by luaL_unref
-- only for debugging; messes with lauxlib.c internals, requires debug lib
-- see http://www.lua.org/source/5.1/lauxlib.c.html#luaL_ref
function E.sweepRefs()
    local reg = debug.getregistry()
    local FREELIST_REF = 0
    while true do
        local next = reg[FREELIST_REF]
        if type(next) ~= "number" or next == 0 then
            break
        end
        reg[FREELIST_REF] = reg[next]
        reg[next] = nil
    end
end

export_from_table(E)
