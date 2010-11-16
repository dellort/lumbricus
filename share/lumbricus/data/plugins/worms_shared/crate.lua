local M = export_table()

-- keep in sync with D
CrateType = {
    unknown = 0,
    weapon = 1,
    med = 2,
    tool = 3,
}

-- speed when the crate goes into state parachute
enter_parachute_speed = 300


local states = {}

states.normal = {
    animation = "normal",
    physics = {
        radius = 10,
        damageable = 1.0,
        glueForce = 50,
        mass = 10,
        elasticity = 0.4,
        collisionID = "crate",
    },
}

states.creation = {
    animation = "beam",
    particle = "p_beam",
    physics = table_merge(states.normal.physics, {
        fixate = Vector2(0, 0),
    }),
}

states.parachute = {
    animation = "fly",
    physics = table_merge(states.normal.physics, {
        mediumViscosity = 0.4, -- basically, fall slower
        glueForce = 1000,
    }),
}

states.drown = {
    animation = "drown",
}

local seq = {
    default = "s_crate_weapon",
    [CrateType.med] = "s_crate_med",
    [CrateType.tool] = "s_crate_tool",
}

local s_class = createSpriteClass {
    name = "x_crate",
    ctor = CrateSpriteClass.ctor,
    initNoActivityWhenGlued = true,
    initialHp = 2,
    -- radius in which stuff is collected
    collectRadius = 30,
}

-- generate states for each crate type
-- crate_states[CrateType value] = state_map
-- state_map[state_name] = state that can be used with setSpriteState()
local crate_states = {}
for crate_type, seq_name in pairs(seq) do
    local seq = lookupResource(seq_name)
    local state_map = {}
    for state_name, state in pairs(states) do
        local cur = {
            seqState = SequenceType.findState(seq, state.animation),
            posp = state.physics and createPOSP(state.physics),
            particle = state.particle and lookupResource(state.particle),
        }
        -- xxx some type checking to prevent surprises?
        state_map[state_name] = cur
    end
    crate_states[crate_type] = state_map
end

-- get the state_map for the current crate type
local function getStates(crate_sprite)
    local t = CrateSprite.crateType(crate_sprite)
    local s = crate_states[t]
    if s == nil then
        s = crate_states.default
    end
    assert(s)
    return s
end

local function setState(crate_sprite, state)
    setSpriteState(crate_sprite, getStates(crate_sprite)[state])
end

local function crate_unparachute(crate_sprite)
    if spriteIsGone(crate_sprite) then
        return
    end
    Sprite.set_exceedVelocity(crate_sprite, 1/0) -- infinity
    setState(crate_sprite, "normal")
end

addSpriteClassEvent(s_class, "sprite_activate", function(sprite)
    Sprite.set_notifyAnimationEnd(sprite, true)
    setState(sprite, "creation")
    Sprite.set_exceedVelocity(sprite, enter_parachute_speed)

    -- hack
    set_context_var(sprite, "crate_skip", crate_unparachute)
end)

addSpriteClassEvent(s_class, "sprite_animation_end", function(sprite)
    -- coming from beaming animation
    setState(sprite, "normal")
end)

addSpriteClassEvent(s_class, "sprite_glue_changed", function(sprite)
    if Phys.isGlued(Sprite.physics(sprite)) then
        -- normally is already in this state
        setState(sprite, "normal")
    elseif not Sprite.isUnderWater(sprite) then
        setState(sprite, "normal")
        Sprite.set_exceedVelocity(sprite, enter_parachute_speed)
    end
end)

addSpriteClassEvent(s_class, "sprite_exceed_velocity", function(sprite)
    setState(sprite, "parachute")
end)

addSpriteClassEvent(s_class, "sprite_zerohp", function(sprite)
    if spriteIsGone(sprite) then
        return
    end
    spriteExplode(sprite, 50)
    Sprite.kill(sprite)
    spawnCluster(M.standard_napalm, sprite, 40, 0, 0, 60)
    CrateSprite.blowStuffies(sprite)
end)

addSpriteClassEvent(s_class, "sprite_waterstate", function(sprite)
    if Sprite.isUnderWater(sprite) then
        -- sets only the graphic, rest is done by the standard drown code
        setState(sprite, "drown")
    end
end)

-- disgusting hack to "make it work"
-- could as well use a global variable for the last spawned crate (just as
--  before), but wanted to avoid that because of the stupid memory managment
--  issues
addGlobalEventHandler("game_crate_skip", function()
    local cur = Game:gameObjectFirst()
    while cur do
        local ctx = get_context(cur, true)
        if ctx and ctx.crate_skip then
            ctx.crate_skip(cur)
        end
        cur = Game:gameObjectNext(cur)
    end
end)
