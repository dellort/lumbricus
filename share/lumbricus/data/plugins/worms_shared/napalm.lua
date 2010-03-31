local M = export_table()

local function phys(radius)
    return createPOSP {
        collisionID = "napalm",
        mass = 10,
        radius = radius,
        explosionInfluence = 0.8,
        windInfluence = 0.0,
        airResistance = 0.3,
        elasticity = 0.0,
        glueForce = 0,
    }
end

-- napalm which doesn't "stick"
M.standard_napalm = createSpriteClass {
    name = "x_standard_napalm",
    ctor = "NapalmSpriteClass_ctor",
    initPhysic = phys(3),
    physMedium = phys(2),
    physSmall = phys(1),
    damage = utils.range(6, 9),
    initialDelay = timeRange("0ms", "500ms"),
    repeatDelay = timeRange("400ms", "600ms"),
    decayTime = timeRange("7s", "10s"),
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

-- napalm which "sticks" a while and fades as the game rounds progress
-- xxx implement
M.sticky_napalm = M.standard_napalm

