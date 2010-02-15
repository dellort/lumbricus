
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
function get_context_var(d_game_object, value_name, def)
    local ctx = get_context(d_game_object, true)
    if ctx then
        local x = ctx[value_name]
        if x then
            return x
        end
    end
    return def
end
function set_context_var(d_game_object, value_name, value)
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
-- parent = any GameObject, from which this is spawned (shooter or sprite)
-- velocity = optional, if nil no velocity is set
function spawnSprite(parent, sprite_class_ref, pos, velocity)
    local s = createSpriteFromRef(sprite_class_ref)
    GameObject_set_createdBy(s, parent)
    if (velocity) then
        Phys_setInitialVelocity(Sprite_physics(s), velocity)
    end
    Sprite_activate(s, pos)
    return s
end

-- this also ensures that you can do get_context(sprite).fireinfo and .shooter
--  in the sprite_activate event
function spawnFromFireInfo(sprite_class_ref, shooter, fireinfo)
    -- xxx creating a closure (and the context table etc.) all the time is
    --  probably not so good if it gets called often (like with the
    --  flamethrower), but maybe it doesn't really matter
    local function create()
        local s = createSpriteFromRef(sprite_class_ref)
        local ctx = get_context(s)
        ctx.fireinfo = fireinfo
        ctx.shooter = shooter
        return s
    end
    -- copied from game.action.spawn (5 = sprite.physics.radius, 2 = spawndist)
    -- eh, and why not use those values directly?
    local dist = (fireinfo.shootbyRadius + 5) * 1.5 + 2
    local s = spawnSprite(shooter, create, fireinfo.pos + fireinfo.dir * dist,
        fireinfo.dir * fireinfo.strength)
    return s
end

-- init for gameObjectFindShooter
local _D_ShooterClass = d_find_class("Shooter")
assert(_D_ShooterClass)

-- find the D shooter from a D sprite; return nil on failure
-- the sprite must have been created by spawnFromFireInfo to make this work
function gameObjectFindShooter(obj)
    -- createdBy may return any other D object, not only sprites
    -- => check the type
    while obj do
        if d_is_class(obj, _D_ShooterClass) then
            return obj
        end
        obj = GameObject_createdBy(obj)
    end
    return nil
end

-- custom_dir is optional
function spawnCluster(sprite_class_ref, parentSprite, count, strengthMin,
    strengthMax, randomRange, custom_dir)
    local spos = Phys_pos(Sprite_physics(parentSprite))
    -- default up
    custom_dir = custom_dir or Vector2(0, -1)
    for i = 1,count do
        local strength = Random_rangei(strengthMin, strengthMax)
        local theta = (Random_rangef(-0.5, 0.5)*randomRange) * math.pi/180
        local dir = custom_dir:rotated(theta)
        -- dir * 15: add some distance from parent to clusters
        --           (see above, I'm too lazy to do this properly now)
        spawnSprite(parentSprite, sprite_class_ref, spos + dir * 15,
            dir * strength)
    end
end

-- create and return a function that does what most onFire functions will do
-- incidentally, this just calls spawnFromFireInfo()
function getStandardOnFire(sprite_class_ref)
    return function(shooter, info)
        Shooter_reduceAmmo(shooter)
        Shooter_finished(shooter)
        spawnFromFireInfo(sprite_class_ref, shooter, info)
    end
end

function getAirstrikeOnFire(sprite_class_ref, count, distance)
    return function(shooter, info)
        Shooter_reduceAmmo(shooter)
        Shooter_finished(shooter)
        spawnAirstrike(sprite_class_ref, count or 6, shooter, info,
            distance or 40)
    end
end

-- do something for all objects inside radius at info.pos + info.dir * distance
-- will not hit the shooter
function getMeleeOnFire(distance, radius, callback)
    return function(shooter, info)
        local hit = info.pos + info.dir * distance;
        local self = Shooter_owner(shooter)
        -- find all objects at hit inside radius
        World_objectsAt(hit, radius, function(obj)
            local spr = Phys_backlink(obj)
            -- don't hit the shooter
            if spr ~= self then
                callback(shooter, info, self, obj)
            end
            return true
        end)
        Shooter_reduceAmmo(shooter)
        Shooter_finished(shooter)
    end
end

-- spawn multiple sprites with a single fire call; returns onFire and
-- onInterrupt function
--   nsprites = max number to spawn (may be interrupted before)
--   interval = delay between spawns (first is spawned immediately)
--   per_shot_ammo = if true, every spawned projectile reduces ammo
function getMultispawnOnFire(sprite_class, nsprites, interval, per_shot_ammo)
    assert(sprite_class)
    assert(nsprites > 0)
    local function doFire(shooter, fireinfo)
        if not per_shot_ammo then
            Shooter_reduceAmmo(shooter)
        end
        LuaShooter_set_isFixed(shooter, true)
        local remains = nsprites
        local timer = Timer.new()
        set_context_var(shooter, "firetimer", timer)
        local function doSpawn()
            if per_shot_ammo then
                Shooter_reduceAmmo(shooter)
            end
            -- only one sprite per timer tick...
            -- xxx this function is bad:
            --  1. sets a context per napalm sprite (for fireinfo)
            --  2. doesn't spawn like the .conf flamethrower
            --  3. doesn't use readjust
            spawnFromFireInfo(sprite_class, shooter, fireinfo)
            remains = remains - 1
            if remains <= 0 then
                timer:cancel()
                Shooter_finished(shooter)
            end
        end
        timer:setCallback(doSpawn)
        timer:start(interval, true)
        doSpawn()
    end
    local function doInterrupt(shooter, outOfAmmo)
        local timer = get_context_var(shooter, "firetimer")
        if timer then
            timer:cancel()
            Shooter_finished(shooter)
        end
    end
    return doFire, doInterrupt
end

-- simple shortcut
function addSpriteClassEvent(sprite_class, event_name, handler)
    local sprite_class_name = SpriteClass_name(sprite_class)
    addClassEventHandler(sprite_class_name, event_name, handler)
end

-- if a sprite "impacts" (whatever this means), explode and die
-- damage is passed to spriteExplode() (see there)
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
function getDrownFunc(sprite_class, drown_phys)
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
    return function(sender)
        if not Sprite_isUnderWater(sender) then
            return
        end
        Phys_set_posp(Sprite_physics(sender), drown_phys)
        Sprite_setParticle(sender, particle)
        if drown_graphic then
            Sequence_setState(Sprite_graphic(sender), drown_graphic)
        end
    end
end
function enableDrown(sprite_class, drown_phys)
    addSpriteClassEvent(sprite_class, "sprite_waterstate",
        getDrownFunc(sprite_class, drown_phys))
end

-- when a create with the weapon is blown up, the sprite gets spawned somehow
function enableSpriteCrateBlowup(weapon_class, sprite_class, count)
    assert(sprite_class)
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

-- sprite will bounce back nbounces times and call onHit every impact, then die
function enableBouncer(sprite_class, nbounces, onHit)
    addSpriteClassEvent(sprite_class, "sprite_impact", function(sender)
        onHit(sender)
        local bounce = get_context_var(sender, "bounce", nbounces)
        if bounce <= 0 then
            Sprite_die(sender)
        end
        set_context_var(sender, "bounce", bounce - 1)
    end)
end

-- sprite will start walking on activation, and reverse when it gets stuck
--   (or call onStuck, if it's set)
function enableWalking(sprite_class, onStuck)
    addSpriteClassEvent(sprite_class, "sprite_activate", function(sender)
        walkForward(sender)
        local trig = StuckTrigger_ctor(sender, time(0.2), 2.5, true);
        StuckTrigger_set_onTrigger(trig, function(trigger, sprite)
            if onStuck then
                onStuck(sprite)
            else
                walkForward(sprite, true)
            end
        end)
    end)
end

-- create a timer as a sprite of that class is spawned
-- the timer is never called under water or after the sprite has died
-- args:
--  callback = function called when timer has ellapsed (with sprite as param)
--  useUserTimer = use the timer as set by the user
--  defTimer = timer value (or default if user timer not available)
--  showDisplay = if true, show the time as a label near the sprite
--  timerId = (default "timer") set if you want to use multiple timers
function enableSpriteTimer(sprite_class, args)
    local useUserTimer = args.useUserTimer
    if not args.defTimer then
        useUserTimer = true
    end
    local showDisplay = args.showDisplay
    local defTimer = args.defTimer or timeSecs(3)
    local callback = assert(args.callback)
    local periodic = args.periodic
    local timerId = args.timerId or "timer"
    local removeUnderwater = ifnil(args.removeUnderwater, true)
    -- xxx need a better way to "cleanup" stuff like timers
    local function cleanup(sender)
        local ctx = get_context(sender, true)
        if ctx and ctx[timerId] and spriteIsGone(sender) then
            ctx[timerId]:cancel()
        end
    end
    if removeUnderwater then
        addSpriteClassEvent(sprite_class, "sprite_waterstate", cleanup)
    end
    addSpriteClassEvent(sprite_class, "sprite_die", cleanup)
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
        ctx[timerId] = addTimer(t, function()
            callback(sender)
        end, periodic)
        if showDisplay then
            addCountdownDisplay(sender, ctx[timerId], 5, 2)
        end
    end)
end

-- adds a timer to an active sprite instance
-- xxx maybe join with enableSpriteTimer, but addInstanceEventHandler looks
--     very expensive
function addSpriteTimer(sprite, timerId, time, showDisplay, callback)
    assert(callback)
    -- xxx need a better way to "cleanup" stuff like timers
    addInstanceEventHandler(sprite, "sprite_waterstate", function(sender)
        local ctx = get_context(sender, true)
        if ctx and ctx[timerId] and spriteIsGone(sender) then
            ctx[timerId]:cancel()
        end
    end)

    local ctx = get_context(sprite)
    ctx[timerId] = addTimer(time, function()
        callback(sprite)
    end)
    if showDisplay then
        addCountdownDisplay(sprite, ctx[timerId], 5, 2)
    end
end

-- create ZoneTrigger and add it to the world
--   zone = PhysicZone instance
--   collision = string collision id
function createZoneTrigger(zone, collision, onTrigger)
    local trig = ZoneTrigger_ctor(zone)
    Phys_set_collision(trig, CollisionMap_findCollisionID(collision))
    PhysicTrigger_set_onTrigger(trig, onTrigger)
    World_add(trig)
    return trig
end

-- helper, creates PhysicZoneCircle attached to sprite and calls createZoneTrigger
function addCircleTrigger(sprite, radius, collision, onTrigger)
    local zone = PhysicZoneCircle_ctor(Sprite_physics(sprite), radius)
    return createZoneTrigger(zone, collision, onTrigger)
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

-- kill = if sprite should die; default is true
-- damage = number or range of damage value (Cf. utils.range())
function spriteExplode(sprite, damage, kill)
    -- don't explode if not visible (this is almost always what you want)
    if not Sprite_visible(sprite) then
        return
    end
    local spos = Phys_pos(Sprite_physics(sprite))
    if ifnil(kill, true) then
        Sprite_die(sprite)
    end
    Game_explosionAt(spos, utils.range_sample_f(damage), sprite)
end


-- props will be used with setProperties(), except for:
--  name = string used as symbolic/translateable weapon name
--  ctor = if non-nil, a constuctor function for the weapon
--         (if it's a string, it's taken as global function name)
-- onBlowup = removed and registered as event handler
--         (onFire has to follow different rules because it returns something)
function createWeapon(props)
    local name = pick(props, "name")
    local ctor = pick(props, "ctor", LuaWeaponClass_ctor)
    if type(ctor) == "string" then
        ctor = _G[ctor]
    end
    local onblowup = pick(props, "onBlowup")
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

-- special properties (similar to createWeapon):
--  name = symbolic name for the sprite (mostly used for even dispatch)
--  ctor = same as in createWeapon
--  noDrown = if true, don't automatically call enableDrown on the sprite class
function createSpriteClass(props)
    local name = pick(props, "name")
    local ctor = pick(props, "ctor", SpriteClass_ctor)
    if type(ctor) == "string" then
        ctor = _G[ctor]
    end
    local nodrown = pick(props, "noDrown", false)
    --
    local s = ctor(Gfx, name)
    setProperties(s, props)
    if not nodrown then
        enableDrown(s)
    end
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

-- sprite died or is under water
-- xxx: you have to check the sprite state all the time; there should be some
--  automatic way to deal with this instead
function spriteIsGone(sprite)
    return not Sprite_visible(sprite) or Sprite_isUnderWater(sprite)
end

Lexel_free = 0
Lexel_soft = 1
Lexel_hard = 2

-- return PhysicObject looking vector
function lookVector(obj)
    return Vector2.FromPolar(1.0, Phys_lookey(obj))
end

-- -1 if looking left, 1 if looking right
function lookSide(obj)
    local look = lookVector(obj)
    return look.x < 0 and -1 or 1
end

-- make a sprite walk into looking direction (will walk forever)
function walkForward(sprite, inverse)
    inverse = ifnil(inverse, false)
    local phys = Sprite_physics(sprite)
    local look = lookVector(phys)
    local dir = 1
    if (look.x < 0) ~= inverse then
        dir = -1
    end
    Phys_setWalking(phys, Vector2(dir, 0))
end

function createPOSP(props)
    local ret = POSP_ctor()
    setProperties(ret, props)
    return ret
end

-- add HomingForce to sprite
--   targetStruct = WeaponTarget structure (from FireInfo)
--   forceA, forceT = acceleration / turn force
function setSpriteHoming(sprite, targetStruct, forceA, forceT)
    local homing = HomingForce_ctor(Sprite_physics(sprite), forceA or 15000,
        forceT or 15000)
    if targetStruct.sprite then
        HomingForce_set_targetObj(homing, Sprite_physics(targetStruct.sprite))
    else
        HomingForce_set_targetPos(homing, targetStruct.pos)
    end
    World_add(homing)
    return homing
end

function findSpriteSeqType(sprite_class, animation)
    return SequenceType_findState(SpriteClass_sequenceType(sprite_class),
        animation)
end

-- the following state functions are mostly a hack for complex weapons
-- a state is the combination of (animation, physics, particle)
-- initSpriteState creates a table with preprocessed state values for a sprite
--    animation = string sequence state id
--    physics = POSP instance, or physics table (will use createPOSP)
--    particle = string resource id
-- if any param is nil, it will not be modified (except particle, which will be
--    cleared then)
function initSpriteState(sprite_class, animation, physics, particle)
    local seq = SpriteClass_sequenceType(sprite_class)
    local ret = {}
    if animation then
        ret.seqState = SequenceType_findState(seq, animation)
    end
    if physics then
        if type(physics) == "userdata" then
            ret.posp = physics
        else
            ret.posp = createPOSP(physics)
        end
    end
    if particle then
        ret.particle = Gfx_resource(particle)
    end
    return ret
end

-- sets the sprite to a state created with initSpriteState
function setSpriteState(sprite, state)
    if state.posp then
        Phys_set_posp(Sprite_physics(sprite), state.posp)
    end
    if state.seqState then
        Sequence_setState(Sprite_graphic(sprite), state.seqState)
    end
    Sprite_setParticle(sprite, state.particle)
end

