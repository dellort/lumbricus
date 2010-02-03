
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
    -- the way createdBy is set doesn't really work?
    local s = Game_createSprite(name)
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

-- simple shortcut
function addSpriteClassEvent(sprite_class, event_name, handler)
    local sprite_class_name = SpriteClass_name(sprite_class)
    addClassEventHandler(sprite_class_name, event_name, handler)
end

-- if a sprite "impacts" (whatever this means), explode and die
function enableExplosionOnImpact(sprite_class, damage)
    addSpriteClassEvent(sprite_class, "sprite_impact", function(sender)
        Sprite_die(sender)
        Game_explosionAt(Phys_pos(Sprite_physics(sender)), damage, sender)
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
        local dir = Vector2.FromPolar(1, Random_rangef(-3*math.pi/4, -math.pi/4))
        spawnSprite(SpriteClass_name(sprite_class),
            Phys_pos(Sprite_physics(crate_sprite)) + dir*12, dir * Random_rangei(350, 550))
    end
    addClassEventHandler(EventTarget_eventTargetType(weapon_class),
        "weapon_crate_blowup", blowup)
end

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
-- unit = sets the "quantum" per displayed unit; if nil, defaults to Time.Second
-- time_visible = a number; unit at which time display is visible
--                or nil, then time is always displayed (if timer started)
-- time_red = a number; unit at which the time display becomes red
--            or nil, then it's never shown in red
function addCountdownDisplay(sprite, timer, unit, time_visible, time_red)
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
        -- special cased because time calculation allocates memory (LOL)
        if fraction > 0 then
            updater:start(unit*(1.0 - fraction))
        else
            updater:start(unit)
        end
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
