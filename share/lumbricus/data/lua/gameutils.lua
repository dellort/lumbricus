
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
        T(GameObject, d_game_object)
        assert(d_game_object:objectAlive())
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

-- resources

function lookupResource(name, canfail)
    canfail = ifnil(canfail, false)
    return Game:resources():getDynamic(name, canfail)
end

function registerResource(object, name)
    Game:resources():addResource(object, name)
end

-- random helper functions

-- create and return a function that does what most onFire functions will do
-- incidentally, this just calls spawnFromFireInfo()
function getStandardOnFire(sprite_class, particle_type)
    return function(shooter, info)
        shooter:reduceAmmo()
        shooter:finished()
        spawnFromFireInfo(sprite_class, shooter, info)
        if particle_type then
            emitShooterParticle(particle_type, shooter)
        end
    end
end

function getAirstrikeOnFire(sprite_class, count, distance)
    return function(shooter, info)
        shooter:reduceAmmo()
        shooter:finished()
        spawnAirstrike(sprite_class, count or 6, shooter, info, distance or 40)
    end
end

-- do something for all objects inside radius at info.pos + info.dir * distance
-- will not hit the shooter
function getMeleeOnFire(distance, radius, callback)
    return function(shooter, info)
        local hit = info.pos + info.dir * distance;
        local self = shooter:owner()
        -- find all objects at hit inside radius
        World:objectsAt(hit, radius, function(obj)
            local spr = obj:backlink()
            -- don't hit the shooter
            if spr ~= self then
                callback(shooter, info, self, obj)
            end
            return true
        end)
        shooter:reduceAmmo()
        shooter:finished()
    end
end

-- spawn multiple sprites with a single fire call; returns onFire, onInterrupt
-- and onReadjust function
--   nsprites = max number to spawn (may be interrupted before)
--      if nsprites is -1, get from fireinfo.param
--   interval = delay between spawns (first is spawned immediately)
--   per_shot_ammo = if true, every spawned projectile reduces ammo
function getMultipleOnFire(nsprites, interval, per_shot_ammo, callback)
    assert(callback)
    assert(nsprites > 0 or nsprites == -1)
    local function doFire(shooter, fireinfo)
        if not per_shot_ammo then
            -- this may call onInterrupt if the last piece of ammo is fired
            shooter:reduceAmmo()
        end
        shooter:set_fixed(true)
        shooter:set_delayed(true)
        local remains = nsprites
        if remains == -1 then
            remains = fireinfo.param
        end
        local timer = Timer.New()
        local ctx = get_context(shooter)
        local sprite_phys = T(PhysicObject, shooter:owner():physics())
        ctx.firetimer = timer
        ctx.fireinfo = fireinfo
        local function doSpawn()
            if per_shot_ammo then
                if not shooter:reduceAmmo() then
                    remains = 1
                end
            end
            ctx.fireinfo.pos = sprite_phys:pos()
            -- only one sprite per timer tick...
            callback(shooter, ctx.fireinfo, remains)
            remains = remains - 1
            if remains <= 0 then
                timer:cancel()
                shooter:finished()
            end
        end
        timer:setCallback(doSpawn)
        timer:start(interval, true)
        doSpawn()
    end
    local function doInterrupt(shooter)
        local timer = get_context_var(shooter, "firetimer")
        if timer then
            timer:cancel()
            shooter:finished()
        end
    end
    local function doReadjust(shooter, dir)
        local ctx = get_context(shooter)
        -- Shooter.fireinfo() could also be used, but that recreates the tables
        ctx.fireinfo.dir = dir
    end
    return doFire, doInterrupt, doReadjust
end

-- WAY to special and used only by mad cow so far
function getMultispawnOnFire(sprite_class, nsprites, interval, per_shot_ammo)
    assert(sprite_class)
    return getMultipleOnFire(nsprites, interval, per_shot_ammo,
        function(shooter, fireinfo)
            -- xxx this function is bad:
            --  2. doesn't spawn like the .conf flamethrower
            spawnFromFireInfo(sprite_class, shooter, fireinfo)
        end)
end

-- simple shortcut
function addSpriteClassEvent(sprite_class, event_name, handler)
    T(SpriteClass, sprite_class)
    addClassEventHandler(sprite_class:name(), event_name, handler)
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
    local seq = sprite_class:getInitSequenceType()
    if seq then
        drown_graphic = seq:findState("drown", true)
    end
    if not drown_graphic then
        log.minor("no drown graphic for sprite {}", sprite_class)
    end
    local particle = lookupResource("p_projectiledrown")
    if not drown_phys then
        -- this is just like projectile.d does it
        drown_phys = sprite_class:initPhysic():copy()
        drown_phys:set_radius(1)
        drown_phys:set_collisionID(CollisionMap:find("waterobj"))
        drown_phys:set_directionConstraint(Vector2(0, 1))
    end
    return function(sender)
        T(Sprite, sender)
        if not (sender:isUnderWater() and sender:visible()) then
            return
        end
        sender:physics():set_posp(drown_phys)
        sender:setParticle(particle)
        if drown_graphic then
            sender:graphic():setState(drown_graphic)
        end
    end
end
function enableDrown(sprite_class, ...)
    addSpriteClassEvent(sprite_class, "sprite_waterstate",
        getDrownFunc(sprite_class, ...))
end

-- when a create with the weapon is blown up, the sprite gets spawned somehow
function enableSpriteCrateBlowup(weapon_class, sprite_class, count)
    assert(sprite_class)
    count = count or 1
    function blowup(weapon, crate_sprite)
        spawnCluster(sprite_class, crate_sprite, count, 350, 550, 90)
    end
    T(EventTarget, weapon_class)
    addClassEventHandler(weapon_class:eventTargetType(),
        "weapon_crate_blowup", blowup)
end

-- call fn(sprite) everytime it has been glued for the given time
function enableOnTimedGlue(sprite_class, time, fn)
    addSpriteClassEvent(sprite_class, "sprite_glue_changed", function(sender)
        local state = sender:physics():isGlued()
        local ctx = get_context(sender)
        local timer = ctx.glue_timer
        if not timer then
            timer = Timer.New()
            ctx.glue_timer = timer
            timer:setCallback(function()
                if Sprite.visible(sender) then
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
            Sprite.kill(sender)
        end
        set_context_var(sender, "bounce", bounce - 1)
    end)
end

-- sprite will start walking on activation, and reverse when it gets stuck
--   (or call onStuck, if it's set)
function enableWalking(sprite_class, onStuck)
    addSpriteClassEvent(sprite_class, "sprite_activate", function(sender)
        walkForward(sender)
        local trig = StuckTrigger.ctor(sender, time(0.2), 2.5, true);
        trig:set_onTrigger(function(trigger, sprite)
            if onStuck then
                onStuck(sprite)
            else
                walkForward(sprite, true)
            end
        end)
    end)
end

local allocTimerId = 0

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
    local timerId = args.timerId
    if not timerId then
        timerId = "timer" .. allocTimerId
        allocTimerId = allocTimerId + 1
    end
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
        local t = defTimer
        if useUserTimer then
            -- actually, it should always find a shooter
            local sh = gameObjectFindShooter(sender)
            if sh then
                t = sh:fireinfo().param * timeSecs(1)
            end
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
    local trig = ZoneTrigger.ctor(zone)
    trig:set_collision(CollisionMap:find(collision))
    trig:set_onTrigger(onTrigger)
    World:add(trig)
    return trig
end

-- helper, creates PhysicZoneCircle attached to sprite and calls createZoneTrigger
function addCircleTrigger(sprite, radius, collision, onTrigger)
    local zone = PhysicZoneCircle.ctor(sprite:physics(), radius)
    return createZoneTrigger(zone, collision, onTrigger)
end

-- fstr = string of the form "SequenceType:SequenceState"
--  e.g. "s_sheep:normal"
-- this is just a helper
function findSequenceState(fstr)
    local pre, post = utils.split2(fstr, ":", true)
    local seq = T(SequenceType, lookupResource(pre))
    return seq:findState(post)
end

-- for setProperties()
-- maps property names to a table that maps type names to a conversion function
autoProperties = {
    icon = {
        string = lookupResource,
    },
    prepareParticle = {
        string = lookupResource,
    },
    fireParticle = {
        string = lookupResource,
    },
    sequenceType = {
        string = lookupResource,
    },
    sequenceState = {
        string = findSequenceState,
    },
    initParticle = {
        string = lookupResource,
    },
    collisionID = {
        string = function(x) return CollisionMap:find(x) end,
    },
    walkingCollisionID = {
        string = function(x) return CollisionMap:find(x) end,
    },
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
    local mt = getmetatable(d_object).__index
    assert(type(mt) == "table")
    local failed
    for name, value in pairs(data) do
        local read = mt[name] -- read method
        local write = mt["set_" .. name] -- write method
        local is_relay = getmetatable(value) == _RelayMetaTable
        if write and not is_relay then
            -- set that value; possibly convert according to autoProperties
            local autoprop = autoProperties[name]
            if autoprop then
                local converter = autoprop[type(value)]
                if converter then
                    value = converter(value)
                end
            end
            write(d_object, value)
        elseif read and is_relay then
            -- special case: redirect
            local relayed = read(d_object)
            setProperties(relayed, value)
        else
            if not failed then
                failed = {}
            end
            failed[name] = value
        end
    end
    -- error if a property in data wasn't in d_object
    if failed then
        error(utils.format("the following stuff couldn't be set: {}", failed),
            2)
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
    assert(sprite)
    T(Sprite, sprite)
    local unit = unit or Time.Second
    local txt = WormLabels.textCreate()
    local last_visible = false
    local function setVisible(visible)
        if visible == last_visible then
            return
        end
        local gr = sprite:graphic()
        -- gr can be null if the sprite died or so, no idea *shrug*
        if not gr then return end
        gr:set_attachText(iif(visible, txt, nil))
        last_visible = visible
    end
    -- the Timer updater is invoked every second to change the time display
    -- the "link" is used to make the timer run synchronously
    local updater = Timer.New()
    local function updateTime()
        local left
        if timer:isStarted() then
            left = timer:timeLeft() / unit
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
        FormattedText.setText(txt, true, prefix .. disp)
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
    T(Sprite, sprite)
    -- don't explode if not visible (this is almost always what you want)
    if not sprite:visible() then
        return
    end
    local spos = sprite:physics():pos()
    if ifnil(kill, true) then
        sprite:kill()
    end
    Game:explosionAt(spos, utils.range_sample_f(damage), sprite)
end


-- props will be used with setProperties(), except for:
--  name = string used as symbolic/translateable weapon name
--  ctor = if non-nil, a constuctor function for the weapon
--         (if it's a string, it's taken as global function name)
-- onBlowup = removed and registered as event handler
--         (onFire has to follow different rules because it returns something)
function createWeapon(props)
    local name = pick(props, "name")
    assert(string.startswith(name, "w_")) -- check convention
    local ctor = pick(props, "ctor", LuaWeaponClass.ctor)
    local onblowup = pick(props, "onBlowup")
    --
    local w = ctor(Game, name)
    setProperties(w, props)
    if onblowup then
        addClassEventHandler(w:eventTargetType(),
            "weapon_crate_blowup", onblowup)
    end
    registerResource(w, name)
    return w
end

-- special properties (similar to createWeapon):
--  name = symbolic name for the sprite (mostly used for even dispatch)
--  ctor = same as in createWeapon
--  noDrown = if true, don't automatically call enableDrown on the sprite class
function createSpriteClass(props)
    local name = pick(props, "name")
    assert(string.startswith(name, "x_")) -- check convention
    local ctor = pick(props, "ctor", SpriteClass.ctor)
    local nodrown = pick(props, "noDrown", false)
    --
    local s = ctor(Game, name)
    setProperties(s, props)
    if not nodrown then
        enableDrown(s)
    end
    registerResource(s, name)
    return s
end

-- return the currently active (team, member) from a D Shooter
function currentTeamFromShooter(shooter)
    local member = Control:memberFromGameObject(shooter:owner(), false)
    local team = nil
    if member then
        team = member:team()
    end
    return team, member
end

-- sprite died or is under water
-- xxx: you have to check the sprite state all the time; there should be some
--  automatic way to deal with this instead
function spriteIsGone(sprite)
    return not sprite:visible() or sprite:isUnderWater()
end

Lexel_free = 0
Lexel_soft = 1
Lexel_hard = 2

-- return PhysicObject looking vector
function lookVector(obj)
    T(PhysicObject, obj)
    return Vector2.FromPolar(1.0, obj:lookey())
end

-- -1 if looking left, 1 if looking right
function lookSide(obj)
    local look = lookVector(obj)
    return look.x < 0 and -1 or 1
end

-- make a sprite walk into looking direction (will walk forever)
function walkForward(sprite, inverse)
    T(Sprite, sprite)
    inverse = ifnil(inverse, false)
    local phys = sprite:physics()
    local look = lookVector(phys)
    local dir = 1
    if (look.x < 0) ~= inverse then
        dir = -1
    end
    phys:setWalking(Vector2(dir, 0))
end

function createPOSP(props)
    local ret = POSP.ctor()
    -- some default value that can't be set in D
    ret:set_collisionID(CollisionMap:find("none"))
    setProperties(ret, props)
    return ret
end

-- add HomingForce to sprite
--   targetStruct = WeaponTarget structure (from FireInfo)
--   forceA, forceT = acceleration / turn force
function setSpriteHoming(sprite, targetStruct, forceA, forceT)
    local homing = HomingForce.ctor(sprite:physics(), forceA or 15000,
        forceT or 15000)
    if targetStruct.sprite then
        homing:set_targetObj(targetStruct.sprite:physics())
    else
        homing:set_targetPos(targetStruct.pos)
    end
    World:add(homing)
    return homing
end

function findSpriteSeqType(sprite_class, animation)
    return sprite_class:sequenceType():findState(animation)
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
    T(SpriteClass, sprite_class)
    local seq = sprite_class:sequenceType()
    local ret = {}
    if animation then
        local seq = sprite_class:getInitSequenceType()
        ret.seqState = seq:findState(animation)
    end
    if physics then
        if type(physics) == "userdata" then
            ret.posp = physics
        else
            ret.posp = createPOSP(physics)
        end
    end
    if particle then
        ret.particle = lookupResource(particle)
    end
    return ret
end

-- get a sprite state (as in setSpriteState) that reflects the initial values
--  according to the sprite class
-- (allocates memory)
function createNormalSpriteState(sprite_class)
    return {
        seqState = sprite_class:getInitSequenceState(),
        posp = sprite_class:initPhysic(),
        particle = sprite_class:initParticle(),
    }
end

-- sets the sprite to a state created with initSpriteState
function setSpriteState(sprite, state)
    T(Sprite, sprite)
    -- xxx there's no way to tell whether a table entry is unset, or if an
    --  entry is a null object reference
    -- idea: use the value false if an entry is considered null?
    if state.posp then
        sprite:physics():set_posp(state.posp)
    end
    if state.seqState then
        sprite:graphic():setState(state.seqState)
    end
    if state.particle then
        sprite:setParticle(state.particle)
    end
end

-- shoot a ray from sprite's pos in dir
--   returns hitpoint, normal if something was hit, the point where hit testing
--   stopped otherwise (sprite.pos + dir * 1000); see PhysicWorld.shootRay
-- sprite = a D Sprite as start point (ray is offset to radius)
-- dir = Vector2 for direction (should be normalized)
-- spread = optional, angle in degrees for random spread
function castFireRay(sprite, dir, spread)
    T(Sprite, sprite)
    local owner = sprite:physics()
    local dist = owner:posp():radius() + 2
    if spread then
        local a = Random:rangef(-spread/2, spread/2)
        dir = dir:rotated(a*math.pi/180)
    end
    local pos = owner:pos() + dir * dist;
    return World:shootRay(pos, dir, 1000)
end

-- "emit and forget" particle functions
-- Make sure to only use particles with a finite lifetime
-- Use Sprite.setParticle for attached particles with lifetime
function emitParticle(particle_type, position, velocity)
    ParticleWorld:emitParticle(position, velocity or Vector2(0), lookupResource(particle_type))
end

-- Emit at sprite location/speed (not attached)
function emitSpriteParticle(particle_type, parent)
    T(Sprite, parent)
    local phys = parent:physics()
    emitParticle(particle_type, phys:pos(), phys:velocity())
end

function emitShooterParticle(particle_type, shooter)
    emitSpriteParticle(particle_type, shooter:owner())
end

-- sender = object whose type is one of TeamTheme, Team, TeamMember
--          if nil, the message is neutral
-- id = translation id string
-- args = translation arguments (nil if none)
-- displayTime = time to show (nil for default)
-- xxx this is not the right place for that function
function gameMessage(sender, id, args, displayTime)
    -- xxx checks if MessagePlugin was addSingleton'ed, this is shaky
    if type(MessagePlugin) ~= "userdata" then
        -- plugin not loaded
        return
    end
    if d_is_class(sender, d_find_class("TeamMember")) then
        sender = sender:team()
    end
    if d_is_class(sender, d_find_class("Team")) then
        sender = sender:theme()
    end
    local msg = {
        lm = { id = id, args = args },
        color = sender,
        is_private = false,
        displayTime = displayTime,
    }
    MessagePlugin:add(msg)
end

-- calls cb(team, member) for each TeamMember in the game
function foreachMember(cb)
    for i, team in ipairs(Control:teams()) do
        for n, member in ipairs(team:members()) do
            cb(team, member)
        end
    end
end

-- calls cb(team, member, worm) for each worm in the game
-- "worm" is defined as in worm.d (WormSprite)
-- if we ever should allow members that are not WormSprite, revisit all code
--  that uses it (or if it's agnostic, use foreachMember and then member:sprite)
function foreachWorm(cb)
    local wormclass = d_find_class("WormSprite")
    foreachMember(function(team, member)
        local sprite = member:sprite()
        if sprite and d_is_class(sprite, wormclass) then
            cb(team, member, sprite)
        end
    end)
end
