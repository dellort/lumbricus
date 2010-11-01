local M = export_table()

local function phys(glue, radius)
    return createPOSP {
        collisionID = "napalm",
        mass = 10,
        radius = radius,
        explosionInfluence = 0.8,
        windInfluence = 0.0,
        airResistance = 0.3,
        elasticity = 0.0,
        glueForce = iif(glue, 100.0, 0),
    }
end

local napalm_common = {
    ctor = "NapalmSpriteClass_ctor",
    damage = utils.range(6, 9),
    initialDelay = timeRange("0ms", "500ms"),
    repeatDelay = timeRange("400ms", "600ms"),
    lightupVelocity = 400,
    sequenceType = "s_napalm",
    initParticle = "p_napalmsmoke",
    -- hack until we get some generic event system, or whatever
    -- specific to this class
    -- xxx: hey, we have a generic event system... just need extend physic
    --  to get specific "this collides with that" events (right now, it
    --  would require you to register an event handler for all types of
    --  collisions, and do "manual" filtering, which might be S.L.O.W.)
    -- the holy grenade would need something similar
    emitOnWater = lookupResource("p_napalmsmoke_short"),
}

-- napalm which doesn't "stick"
M.standard_napalm = createSpriteClass(table_merge(napalm_common, {
    name = "x_standard_napalm",
    initPhysic = phys(false, 3),
    physMedium = phys(false, 2),
    physSmall = phys(false, 1),
    decayTime = timeRange("7s", "10s"),
}))

-- napalm which "sticks" a while and fades as the game rounds progress
M.sticky_napalm = createSpriteClass(table_merge(napalm_common, {
    name = "x_sticky_napalm",
    initPhysic = phys(true, 3),
    physMedium = phys(true, 2),
    physSmall = phys(true, 1),
    sticky = true,
    decaySteps = 4,
    decayTime = timeRange("3s", "6s"),
}))

-- this implements the logic that sticky napalm burns & decays on each turn
addGlobalEventHandler("game_prepare_turn", function()
    M.sticky_napalm:stepDecay()
end)
