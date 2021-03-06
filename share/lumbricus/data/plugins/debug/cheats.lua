-- "shortcut" functions for debugging and cheating

local E = {} -- whatever

function E.activeGameObjects()
    local cur = Game:gameObjectFirst()
    local list = {}
    while cur do
        if cur:activity() then
            list[#list + 1] = cur
        end
        cur = Game:gameObjectNext(cur)
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
        g:kill()
    end
end

-- get control over a random worm
-- will not work in network mode
function E.takeControl()
    for i, t in ipairs(Control:teams()) do
        t:set_active(true)
        -- will be false if no worm available
        if t:active() then
            break
        end
    end
end

-- this thing requires us to do extra crap in controller.d (look for inpExec)
-- it's only available while stuff is executed via the exec server command
function E.ownedTeam()
    return assert(_G._currentInputTeam)
end

function E.giveWeapon(name, amount)
    ownedTeam():addWeapon(lookupResource(name), amount or 1)
end

function weaponList()
    local cls = d_find_class("WeaponClass")
    assert(cls)
    return Game:resources():findAllDynamic(cls)
end

-- drop a crate with a weapon in it; p is a string for the weapon
function E.dropCrate(p, spy)
    if type(CratePlugin) ~= "userdata" then
        printf("Crate plugin not loaded")
        return
    end
    function ctool(id)
        return function()
            return CollectableTool.ctor(id)
        end
    end
    local stuff = {
        doubledamage = ctool("doubledamage"),
        doubletime = ctool("doubletime"),
        bomb = CollectableBomb.ctor,
        spy = ctool("cratespy"),
        medkit = CollectableMedkit.ctor,
    }
    if type(p) ~= "string" then
        printf("pass as parameter any tool of {}, or any weapon name of {}",
            table_keys(stuff), array.map(weaponList(),
                function(w) return WeaponClass.name(w) end))
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
            fill = {CollectableWeapon.ctor(w, w:crateAmount())}
        end
    end
    if not fill then
        printf("don't know what '{}' is", p)
        return
    end
    CratePlugin:dropCrate(true, fill)
    if ifnil(spy, true) then
        E.crateSpy()
    end
end

-- give all teams a crate spy
function E.crateSpy()
    for k,t in ipairs(Control:teams()) do
        t:set_crateSpy(1)
    end
end

-- the caller wins
function E.allYourBaseAreBelongToUs(slow)
    for k, t in ipairs(Control:teams()) do
        if (t ~= ownedTeam()) then
            if slow then
                for k2, m in ipairs(t:members()) do
                    m:addHealth(-9999)
                end
            else
                t:surrenderTeam()
            end
        end
    end
end

-- +500 hp for caller, 1 hp for others
function E.whosYourDaddy()
    for k,t in ipairs(Control:teams()) do
        for k,m in ipairs(t:members()) do
            if (t == ownedTeam()) then
                m:addHealth(500)
            else
                -- xxx team labels update only at end of round
                p = m:sprite():physics()
                p:applyDamage(p:lifepower() - 1, 2)
            end
        end
    end
end

-- amount (or 10 if omitted) of all weapons
function E.greedIsGood(amount)
    for k,w in ipairs(weaponList()) do
        ownedTeam():addWeapon(w, amount or 10)
    end
end

function E.katastrophe()
    local lb = Level:landBounds()
    World:objectsAt(Level:worldCenter(), 2000, function(obj)
        if className(obj:backlink()) ~= "WormSprite" then
            return true
        end
        local dest
        while (dest == nil) do
            dest = Vector2(Random:rangef(lb.p1.x, lb.p2.x),
                Random:rangef(lb.p1.y, lb.p2.y))
            dest = World:freePoint(dest, 6)
        end
        obj:backlink():beamTo(dest)
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
    local gls = Game:gameLandscapes()[1]
    local ls = gls:landscape()
    local s = ls:size()
    local len = min(s.x, s.y)/3
    local c = s/2
    -- I don't know where the center of a koch snowflake is *shrug*
    local p1 = c+Vector2(-len, len)
    local p3 = c+Vector2(len, len)
    local p2 = get_h(p1, p3)
    local arr = array.concat(koch(p1, p2), koch(p2, p3), koch(p3, p1))

    -- first clear the landscape before rendering the snowflake
    ls:addPolygon({Vector2(0,0), Vector2(s.x,0), s, Vector2(0,s.y)},
        Vector2(0,0), nil, Lexel_free)

    ls:addPolygon(arr, Vector2(0,0), fill, Lexel_soft, interpolate)
    ls:drawBorder(Lexel_soft, Lexel_free, border, border)
end

function E.maze()
    local gls = Game:gameLandscapes()[1]
    local ls = gls:landscape()
    local s = ls:size()
    local CH = 50 -- w/h of a cell
    local WH = 30 -- w/h of a wall
    local H = CH + WH

    -- geneerate maze
    -- see http://en.wikipedia.org/wiki/Maze_generation#Recursive_backtracker
    local cx = math.floor((s.x - CH) / H + 1)
    local cy = math.floor((s.y - CH) / H + 1)
    local cells = {}
    for y = 1, cy do
        cells[y] = {}
        for x = 1, cx do
            local p = Vector2(x - 1, y - 1) * H + Vector2(WH)
            local c = {
                x = x, y = y,
                p1 = p,
                p2 = p + Vector2(CH),
                visited = false,
                -- will contain connected cells (no walls)
                ways = {},
            }
            cells[y][x] = c
        end
    end
    -- return list of unvisited adjacent cells
    local function getunvisited(cell)
        local adj = {}
        local function add(c)
            if not c.visited then
                adj[#adj+1] = c
            end
        end
        local x = cell.x
        local y = cell.y
        if x > 1 then add(cells[y][x-1]) end
        if x < cx then add(cells[y][x+1]) end
        if y > 1 then add(cells[y-1][x]) end
        if y < cy then add(cells[y+1][x]) end
        return adj
    end
    local function visit(cell)
        if cell.visited then
            return
        end
        cell.visited = true
        while true do
            local u = getunvisited(cell)
            if #u < 1 then
                return
            end
            local n = utils.range_sample_i(1, #u)
            local nextcell = u[n]
            array.remove(u, n)
            cell.ways[#cell.ways + 1] = nextcell
            visit(nextcell)
        end
    end
    visit(cells[1][1])

    -- draw maze
    local fill = lookupResource("border_segment")
    local border = lookupResource("rope_segment")

    ls:addPolygon({Vector2(0,0), Vector2(s.x,0), s, Vector2(0,s.y)},
        Vector2(0,0), fill, Lexel_soft)

    for y = 1, cy do
        for x = 1, cx do
            local cell = cells[y][x]
            -- all cells are clear
            ls:drawRect(nil, Lexel_free, {cell.p1, cell.p2})
            -- clear the walls
            for i, other in ipairs(cell.ways) do
                -- rect that covers the wall = rect between the cells
                local x1, y1, x2, y2
                if cell.x == other.x then
                    x1, x2 = cell.p1.x, cell.p2.x
                    if cell.y > other.y then
                        y1, y2 = other.p2.y, cell.p1.y
                    else
                        y1, y2 = cell.p2.y, other.p1.y
                    end
                else
                    y1, y2 = cell.p1.y, cell.p2.y
                    if cell.x > other.x then
                        x1, x2 = other.p2.x, cell.p1.x
                    else
                        x1, x2 = cell.p2.x, other.p1.x
                    end
                end
                ls:drawRect(nil, Lexel_free, {{x1, y1}, {x2, y2}})
            end
        end
    end

    ls:drawBorder(Lexel_soft, Lexel_free, border, border)
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
        local c = PhysicObjectsRod.ctor(obj1, obj2)
        c:set_springConstant(20000)
        c:set_dampingCoeff(10)
        World:add(c)
    end

    if not gridToggle then
        -- ring
        local N = 10
        local X = {}
        local R = 100
        local S = Vector2(3000, 1000)
        local center = bouncy_class:createSprite()
        Sprite.activate(center, S)
        for n = 1, N do
            local o = bouncy_class:createSprite()
            local dir = Vector2.FromPolar(1, math.pi*2/N * (n-1))
            o:activate(S + dir * R)
            X[n] = o
        end
        for n = 1, N do
            local o1 = X[n]
            local o2 = X[(n % #X) + 1]
            makeRod(o1:physics(), o2:physics())
            makeRod(o1:physics(), center:physics())
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
                local o = bouncy_class:createSprite()
                o:activate(S + Vector2(x-1, y-1)*D)
                X[y][x] = o
            end
        end
        -- connect each object with the bottom and right neighbour
        for y = 1, H do
            for x = 1, H do
                local o = (X[y][x]):physics()
                if x < H then
                    local r = (X[y][x+1]):physics()
                    makeRod(o, r)
                end
                if y < H then
                    local b = (X[y+1][x]):physics()
                    makeRod(o, b)
                end
                ----[[
                -- actually adds more stability...
                if x < H and y < H then
                    local n = (X[y+1][x+1]):physics()
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
        local o springobj_class:createSprite()
        o:activate(pos + Vector2(0, 200))

        local c = PhysicObjectsRod.ctor2(o:physics(), pos)
        c:set_springConstant(100)
        c:set_dampingCoeff(5)
        c:set_length(c:length()) --?
        World:add(c)
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
            obj = assert(obj:backlink())
            -- maybe add a timer and some sort of blending effect?
            obj:setPos(companion:physics():pos())
        end)
    end)
end

-- src and dst are Vector2 instances for entry and exit center points
function E.wormHole(src, dst)
    if not wormhole_class then
        initWormHoleClass()
    end

    local entry = wormhole_class:createSprite()
    local exit = wormhole_exit_class:createSprite()

    set_context_var(entry, "companion", exit)
    set_context_var(exit, "companion", entry)

    entry:activate(src)
    exit:activate(dst)
end

-- like wormHole(), but use the GUI to receive two mouse clicks (src and dst)
function E.placeWormHole()
    pickTwoPos(wormHole)
end

-- output contents of any object to console
-- useful for showing D objects
function E.dumpObject(obj, outf)
    outf = outf or printf
    if d_isobject(obj) then
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
            if v.type == "Property_R" then
                props_r[v.name] = v
            elseif v.type == "Property_W" then
                props_w[v.name] = v
            end
        end
        -- output properties and their values, sorted by class
        outf("classes: {}", array.join(sclasses))
        for i, cls in ipairs(sclasses) do
            for name, v in pairs(props_r) do
                if cls == v.dclass then
                    local value = obj[v.xname](obj)
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
    local obj = Game:gameObjectFirst()
    local best, best_pos
    while obj do
        if d_is_class(obj, cls) and obj:visible() then
            local opos = obj:physics():pos()
            if (not best) or
                ((pos - opos):length() < (pos - best_pos):length())
            then
                best, best_pos = obj, opos
            end
        end
        obj = Game:gameObjectNext(obj)
    end
    return best
end

-- pick with mouse, dump to Lua console
-- dowhat = optional function to execute on result
function E.pickObject(dowhat)
    dowhat = dowhat or dumpObject
    local w = Gui.ctor()
    local obj
    setProperties(w, {
        OnHandleKeyInput = function(info)
            if info.isDown and info.code == keycode("mouse_left") then
                GameFrame:removeHudWidget(w)
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
                Canvas.drawCircle(canvas, obj:physics():pos(), 10, Color(1,0,0))
            end
        end,
    })
    GameFrame:addHudWidget(w, "gameview")
end

-- xxx code duplication, but it's crap code anyway *shrug*
function E.pickPosition(dowhat)
    assert(dowhat)
    local w = Gui.ctor()
    local pos
    setProperties(w, {
        OnHandleKeyInput = function(info)
            if pos and info.isDown and info.code == keycode("mouse_left") then
                GameFrame:removeHudWidget(w)
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
                Canvas.drawCircle(canvas, pos, 10, Color(1,0,0))
            end
        end,
    })
    GameFrame:addHudWidget(w, "gameview")
end

function E.pickMakeActive()
    pickObject(function(obj)
        local member = Control:memberFromGameObject(obj)
        if not member then
            printf("nope.")
            return
        end
        local team = member:team()
        Control:deactivateAll()
        team:set_active(true)
        team:set_current(member)
    end)
end

function E.pickKill()
    pickObject(function(obj)
        printf("Killing: {}", obj)
        obj:kill()
    end)
end

function E.pickShowCollide()
    pickObject(function(obj)
        printf(obj:physics():collision())
    end)
end

function E.pickObjectIntoVar(var)
    pickObject(function(obj)
        _G[var] = obj
    end)
end

function E.freePoint(dowhat, r)
    dowhat = dowhat or dumpObject
    local w = Gui.ctor()
    local pos
    setProperties(w, {
        OnHandleKeyInput = function(info)
            GameFrame:removeHudWidget(w)
            return true
        end,
        OnHandleMouseInput = function(info)
            pos = info.pos
            return true
        end,
        OnDraw = function(canvas)
            if pos then
                local r = r or 10
                p = World:freePoint(pos, r)
                if p then
                    canvas:drawCircle(p, r, Color(1,0,0))
                end
            end
        end,
    })
    GameFrame:addHudWidget(w, "gameview")
end

-- show dumpObject() output in a window
-- if obj is nil, use pickObject to pick an object
function E.guiPickObject(obj)
    local function show()
        local w = Gui.ctor()
        local txtrender = SceneDrawText.ctor()
        local txt = txtrender:text()
        Gui.set_render(w, txtrender)
        local updater
        local function update()
            --[[if not Gui.isLinked(w) then
                updater:cancel()
                return
            end]]
            local t = ""
            local function appendf(...)
                t = t .. utils.format(...) .. "\n"
            end
            dumpObject(obj, appendf)
            txt:setText(false, t)
        end
        updater = addPeriodicTimer(time("1s"), update)
        --[[
        setProperties(w, {
            OnUnmap = function()
                updater:cancel()
            end,
        })
        ]]
        GameFrame:addHudWidget(w, "window")
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

function E.pickSpawn(spriteclass)
    local sc = lookupResource(spriteclass, true)
    if not sc then
        printf("what?")
        return
    end
    pickPosition(function(pos)
        spawnSprite(nil, sc, pos)
    end)
end

-- sillyness

function landscapeFromPos(pos)
    assert(pos)
    local lcl = d_find_class("GameLandscape")
    assert(lcl)
    local obj = Game:gameObjectFirst()
    while obj do
        if d_is_class(obj, lcl) then
            local rc = GameLandscape.rect(obj)
            if rc:isInside(pos) then
                return obj
            end
        end
        obj = Game:gameObjectNext(obj)
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
        local offset = gls:rect().p1
        p1 = p1 - offset
        p2 = p2 - offset
        local ls = gls:landscape()
        local whatever = lookupResource("rope_segment")
        ls:drawSegment(whatever, Lexel_soft, p1, p2, 20)
    end)
end

--[[
function E.makePlane()
    pickTwoPos(function(p1, p2)
        local x = PhysicZonePlane.ctor(p1, p2)
        local z = ZoneTrigger.ctor(x)
        z:set_collision(CollisionMap:find("wormsensor"))
        World:add(z)
    end)
end
--]]

function E.dragObject()
    dowhat = dowhat or dumpObject
    local w = Gui.ctor()
    local obj
    local link
    setProperties(w, {
        OnHandleKeyInput = function(info)
            if info.code == keycode("mouse_left") then
                if info.isDown and obj and not link then
                    -- create the constraint
                    local phys = Sprite.physics(obj)
                    link = PhysicObjectsRod.ctor2(phys, phys:pos())
                    link:set_springConstant(100)
                    --link:set_dampingCoeff(5)
                    link:setDampingRatio(0.2)
                    World:add(link)
                else
                    if link then
                        link:kill()
                    end
                    GameFrame:removeHudWidget(w)
                end
            end
            return true
        end,
        OnHandleMouseInput = function(info)
            if link then
                link:set_anchor(info.pos)
            else
                obj = pickObjectAt(info.pos)
            end
            return true
        end,
        OnDraw = function(canvas)
            if obj and not link then
                -- quite some lua heap activity (creating Vector2 and Color)
                canvas:drawCircle(obj:physics():pos(), 10, Color(1,0,0))
            end
        end,
    })
    GameFrame:addHudWidget(w, "gameview")
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
            local a = Random:rangef(-spread/2, spread/2)
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
    for i,t in ipairs(Control:teams()) do
        t:addWeapon(lookupResource("w_marble"), 100)
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
    local spawner = spawner_class:createSprite()
    spawner:activate(Vector2(3000, 1700))
    local maxtime = currentTime() + time("5s")
    local up = Vector2(0, -1)
    Game:benchStart(time("20s"))
    addPeriodicTimer(time("100ms"), function(timer)
        if currentTime() >= maxtime then
            spawner:kill()
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
