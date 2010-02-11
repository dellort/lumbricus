
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

-- helpers for using get_context()
function get_context_val(d_game_object, value_name, def)
    local ctx = get_context(d_game_object, true)
    if ctx then
        local x = ctx[value_name]
        if x then
            return x
        end
    end
    return def
end
function set_context_val(d_game_object, value_name, value)
    get_context(d_game_object)[value_name] = value
end

-- called by game.d as objects are removed
function game_kill_object(d_game_object)
    _dgo_contexts[d_game_object] = nil
end

-- random helper functions

-- sprite_class_ref is...
--  - a string referencing a SpriteClass
--  - a SpriteClass instance
--  - a Lua function to instantiate a sprite
function createSpriteFromRef(sprite_class_ref)
    local t = type(sprite_class_ref)
    if t == "string" then
        return Game_createSprite(sprite_class_ref)
    elseif t == "function" then
        return sprite_class_ref()
    elseif t == "userdata" then
        return SpriteClass_createSprite(sprite_class_ref, Game)
    else
        assert(false)
    end
end

--[[
stuff that needs to be done:
- fix createdBy crap
- fix double damage (d0c needs to make up his mind)
- add different functions for spawning from airstrike/sprite
- for spawning from sprite, having something to specify the emit-position would
  probably be useful (instead of just using weapon-angle and radius); every
  decent shooter with more complex sprites has this
  (actually, FireInfo.pos fulfills this role right now)
- there's spawnFromFireInfo, but this concept sucks hard and should be replaced
]]
function spawnSprite(sprite_class_ref, pos, velocity)
    local s = createSpriteFromRef(sprite_class_ref)
    local t = Game_ownedTeam()
    if (t) then
        GameObject_set_createdBy(s, Member_sprite(Team_current(t)))
    end
    if (velocity) then
        Phys_setInitialVelocity(Sprite_physics(s), velocity)
    end
    Sprite_activate(s, pos)
    return s
end

-- this also ensures that you can do get_context(sprite).fireinfo in the
--  sprite_activate event
function spawnFromFireInfo(sprite_class_ref, fireinfo)
    -- xxx creating a closure (and the context table etc.) all the time is
    --  probably not so good if it gets called often (like with the
    --  flamethrower), but maybe it doesn't really matter
    local function create()
        local s = createSpriteFromRef(sprite_class_ref)
        get_context(s).fireinfo = fireinfo
        return s
    end
    -- copied from game.action.spawn (5 = sprite.physics.radius, 2 = spawndist)
    -- eh, and why not use those values directly?
    local dist = (fireinfo.shootbyRadius + 5) * 1.5 + 2
    local s = spawnSprite(create, fireinfo.pos + fireinfo.dir * dist,
        fireinfo.dir * fireinfo.strength)
    return s
end

function spawnCluster(sprite_class_ref, parentSprite, count, strengthMin, strengthMax, randomRange)
    local spos = Phys_pos(Sprite_physics(parentSprite))
    for i = 1,count do
        local strength = Random_rangei(strengthMin, strengthMax)
        local theta = (Random_rangef(-0.5, 0.5)*randomRange - 90) * math.pi/180
        local dir = Vector2.FromPolar(strength, theta)
        spawnSprite(sprite_class_ref, spos, dir)
    end
end

-- create and return a function that does what most onFire functions will do
-- incidentally, this just calls spawnFromFireInfo()
function getStandardOnFire(sprite_class_ref)
    return function(shooter, info)
        Shooter_reduceAmmo(shooter)
        Shooter_finished(shooter)
        spawnFromFireInfo(sprite_class_ref, info)
    end
end

function getAirstrikeOnFire(sprite_class_ref)
    return function(shooter, info)
        Shooter_reduceAmmo(shooter)
        Shooter_finished(shooter)
        spawnAirstrike(sprite_class_ref, 6, shooter, info, 40)
    end
end

-- simple shortcut
function addSpriteClassEvent(sprite_class, event_name, handler)
    local sprite_class_name = SpriteClass_name(sprite_class)
    addClassEventHandler(sprite_class_name, event_name, handler)
end

-- if a sprite "impacts" (whatever this means), explode and die
function enableExplosionOnImpact(sprite_class, damage)
    addSpriteClassEvent(sprite_class, "sprite_impact", function(sender)
        spriteExplode(sender, damage)
    end)
end

-- if a sprite goes under water
-- drown_phys = a POSP (can be nil, in this case, derive a default)
-- xxx maybe it should dynamically change the sprite class or so to "fix" the
--  behaviour of the sprite underwater; e.g. normal event handlers like timers
--  shouldn't be run underwater anymore (we had the same problem in D, we
--  "solved" it by using a different, non-leaveable state, and probably by
--  additional manual checks)
-- (changing the sprite class sounds way better than the retarded state stuff)
function enableDrown(sprite_class, drown_phys)
    local drown_graphic
    local seq = SpriteClass_sequenceType(sprite_class)
    if seq then
        drown_graphic = SequenceType_findState(seq, "drown", true)
    end
    local particle = Gfx_resource("p_projectiledrown")
    if not drown_phys then
        -- this is just like projectile.d does it
        drown_phys = POSP_copy(SpriteClass_initPhysic(sprite_class))
        POSP_set_radius(drown_phys, 1)
        POSP_set_collisionID(drown_phys, "waterobj")
    end
    addSpriteClassEvent(sprite_class, "sprite_waterstate", function(sender)
        if not Sprite_isUnderWater(sender) then
            return
        end
        Phys_set_posp(Sprite_physics(sender), drown_phys)
        Sprite_setParticle(sender, particle)
        if drown_graphic then
            Sequence_setState(Sprite_graphic(sender), drown_graphic)
        end
    end)
end

-- when a create with the weapon is blown up, the sprite gets spawned somehow
function enableSpriteCrateBlowup(weapon_class, sprite_class, count)
    count = count or 1
    function blowup(weapon, crate_sprite)
        spawnCluster(sprite_class, crate_sprite, count, 350, 550, 90)
    end
    addClassEventHandler(EventTarget_eventTargetType(weapon_class),
        "weapon_crate_blowup", blowup)
end

-- call fn(sprite) everytime it has been glued for the given time
function enableOnTimedGlue(sprite_class, time, fn)
    addSpriteClassEvent(sprite_class, "sprite_gluechanged", function(sender)
        local state = Phys_isGlued(Sprite_physics(sender))
        local ctx = get_context(sender)
        local timer = ctx.glue_timer
        if not timer then
            timer = Timer.new()
            ctx.glue_timer = timer
            timer:setCallback(function()
                if Sprite_visible(sender) then
                    fn(sender)
                end
            end)
        end
        if not state then
            timer:cancel()
        elseif not timer:isActive() then
            timer:start(time)
        end
    end)
end

function enableSpriteTimer(sprite_class, args)
    local useUserTimer = args.useUserTimer
    if not args.defTimer then
        useUserTimer = true
    end
    local showDisplay = args.showDisplay
    local defTimer = args.defTimer or timeSecs(3)
    local callback = assert(args.callback)
    -- xxx need a better way to "cleanup" stuff like timers
    addSpriteClassEvent(sprite_class, "sprite_waterstate", function(sender)
        local ctx = get_context(sender, true)
        if ctx and ctx.timer and
            (not Sprite_visible(sender) or Sprite_isUnderWater(sender))
        then
            ctx.timer:cancel()
        end
    end)
    -- this is done so that it works when spawned by a crate
    -- xxx probably it's rather stupid this way; need better way
    --  plus I don't even know what should happen if a grenade is spawned by
    --  blowing up a crate (right now it sets the timer to a default)
    addSpriteClassEvent(sprite_class, "sprite_activate", function(sender)
        local ctx = get_context(sender)
        local fi = ctx.fireinfo
        local t
        if fi and useUserTimer then
            t = fi.timer
        else
            -- spawned from crate or so
            t = defTimer
        end
        ctx.timer = addTimer(t, function()
            callback(sender)
        end)
        if showDisplay then
            addCountdownDisplay(sender, ctx.timer, 5, 2)
        end
    end)
end

autoProperties = {
    WeaponClass_set_icon = {
        string = Gfx_resource
    },
    SpriteClass_set_sequenceType = {
        string = Gfx_resource
    },
    SpriteClass_set_initParticle = {
        string = Gfx_resource
    }
}

-- this is magic
-- d_object = a D object, that was bound with framework.lua
-- data = a Lua table of name-value pairs
-- for each name, it sets the corresponding property to the given value
--  (properties as registered with LuaRegistry.properties!(Class, ...) )
-- you can use relay() (see below) to recursively use setProperties()
-- the function is slow and inefficient, and should only be used for
--  initialization on game start
-- xxx this relies a lot on the D binding (framework.lua) and should be in its
--  own module, or something
-- xxx 2: setting references to null by using nil obviously isn't going to
--  work; we should add some placeholder value to allow this...
function setProperties(d_object, data)
    local list = d_get_obj_metadata(d_object)
    local data = table_copy(data)
    for i, v in ipairs(list) do
        local value = data[v.name]
        local is_relay = getmetatable(value) == _RelayMetaTable
        if is_relay and v.type == "Property_R" then
            data[v.name] = nil
            local relayed = _G[v.lua_g_name](d_object)
            setProperties(relayed, value)
        elseif (not is_relay) and value and v.type == "Property_W" then
            data[v.name] = nil -- delete for later check for completeness
            local autoprop = autoProperties[v.lua_g_name]
            if autoprop then
                local converter = autoprop[type(value)]
                if converter then
                    value = converter(value)
                end
            end
            _G[v.lua_g_name](d_object, value)
        end
    end
    -- error if a property in data wasn't in d_object
    if not table_empty(data) then
        error(utils.sformat("the following stuff couldn't be set: {}", data), 2)
    end
end

_RelayMetaTable = {}

-- for use with setProperties()
-- if you do setProperties(obj, { bla = relay table }), setProperties will
--  call setProperties(obj.bla, table). this assumes obj.bla is a non-null D-
--  object, and allows setProperties() to be called recursively.
function relay(table)
    -- just mark the table (the user agrees with changing the table)
    setmetatable(table, _RelayMetaTable)
    return table
end

-- this adds a timer to a sprite, that shows a countdown time
-- the countdown time is linked to the passed Timer, and is synchronous even if
--  the timer gets restarted or paused/resumed
-- sprite = Sprite D instance
-- timer = Timer instance from timer.lua
-- time_visible = a number; unit at which time display is visible
--                or nil, then time is always displayed (if timer started)
-- time_red = a number; unit at which the time display becomes red
--            or nil, then it's never shown in red
-- unit = sets the "quantum" per displayed unit; if nil, defaults to Time.Second
function addCountdownDisplay(sprite, timer, time_visible, time_red, unit)
    local unit = unit or Time.Second
    local txt = Gfx_textCreate()
    local last_visible = false
    local function setVisible(visible)
        if visible == last_visible then
            return
        end
        local gr = Sprite_graphic(sprite)
        -- gr can be null if the sprite died or so, no idea *shrug*
        if not gr then return end
        Sequence_set_attachText(gr, iif(visible, txt, nil))
        last_visible = visible
    end
    -- the Timer updater is invoked every second to change the time display
    -- the "link" is used to make the timer run synchronously
    local updater = Timer.new()
    local function updateTime()
        local left
        if timer:isStarted() then
            left = timer:timeLeft():unitsf(unit)
        end
        local visible = left and ((not time_visible) or (left <= time_visible))
        setVisible(visible)
        if not visible then
            updater:cancel()
            if timer:isActive() then
                -- call next when timer really needs to be displayed
                updater:start(timer:timeLeft() - unit*time_visible)
            end
            return
        end
        local disp = math.ceil(left)
        local fraction = disp - left
        local prefix = ""
        if time_red and (disp <= time_red) then
            prefix = "\\c(team_red)"
        end
        -- the ".." converts the number disp to a string (welcome to Lua)
        FormattedText_setText(txt, true, prefix .. disp)
        -- set timer for next change of displayed time
        -- the fraction thing is needed if the timer was activated in an
        --  "between" time (e.g. timeLeft is 4.5 secs => display "5", update in
        --  0.5 sec to show "4" on 4.0 secs)
        updater:start(unit*(1.0 - fraction))
    end
    updater:setCallback(updateTime)
    local link = {
        onPauseState = function()
            updater:setPaused(timer:paused())
        end,
        -- keep in mind that those callback functions are called with the
        --  arguments (link_table, linked_timer)
        onStart = updateTime,
        onTrigger = updateTime,
        onCancel = updateTime,
    }
    timer:setLink(link)
    -- initial stuff
    updateTime()
end

function spriteExplode(sprite, damage)
    -- don't explode if not visible (this is almost always what you want)
    if not Sprite_visible(sprite) then
        return
    end
    local spos = Phys_pos(Sprite_physics(sprite))
    Sprite_die(sprite)
    Game_explosionAt(spos, damage, sprite)
end

-- props will be used with setProperties(), except for:
--  name = string used as symbolic/translateable weapon name
--  ctor = if non-nil, a constuctor function for the weapon
--         (if it's a string, it's taken as global fucntion name)
-- onBlowup = removed and registered as event handler
--         (onFire has to follow different rules because it returns something)
function createWeapon(props)
    local ctor = props.ctor or LuaWeaponClass_ctor
    props.ctor = nil
    if type(ctor) == "string" then
        ctor = _G[ctor]
    end
    local name = props.name
    props.name = nil
    local onblowup = props.onBlowup
    props.onBlowup = nil
    --
    local w = ctor(Gfx, name)
    setProperties(w, props)
    if onblowup then
        addClassEventHandler(EventTarget_eventTargetType(w),
            "weapon_crate_blowup", onblowup)
    end
    Gfx_registerWeapon(w)
    return w
end

function createSpriteClass(props)
    local s = SpriteClass_ctor(Gfx, props.name)
    props.name = nil
    setProperties(s, props)
    Gfx_registerSpriteClass(s)
    return s
end

-- return the currently active (team, member) from a D Shooter
function currentTeamFromShooter(shooter)
    local member = Control_memberFromGameObject(Shooter_owner(shooter), false)
    local team = nil
    if member then
        team = Member_team(member)
    end
    return team, member
end
