local sprite_class = WormSpriteClass.ctor(Game, "x_worm")

-- selects SequenceObject, which again is provided in wwp.conf
local sequence_object = lookupResource("s_worm")

setProperties(sprite_class, {
    suicideDamage = 30,
    -- keep in sync with JumpMode
    jumpStrengthScript = {
        Vector2(1500, -2100), -- normal
        Vector2(-200, -2100), -- smallBack
        Vector2(-300, -3000), -- backFlip
        Vector2(0, -3000),  -- straightUp
    },
    rollVelocity = 400,
    heavyVelocity = 600,
    hitParticle = lookupResource("p_hit_worm"),
    hitParticleDamage = 10,
    getupDelay = time("100ms"),
    sequenceType = sequence_object,
})

-- physical states, used by the "states" section
local std_phys = {
    -- these are only used it not overridden in the per-state physics
    radius = 7,
    mass = 10,
    elasticity = 0.5,
    damageable = 1.0,
}
local physics = {
    worm = {
        -- collision class the worm physical object is set to
        collisionID = "worm_air",
        glueForce = 20,
        bounceAbsorb = 400,
        slideAbsorb = 150,
        friction = 1.8,
        sustainableImpulse = 5000,
        fallDamageFactor = 0.004,
        fallDamageIgnoreX = true,
        speedLimit = 2500,
    },
    worm_stand = {
        -- sitting worm
        collisionID = "worm_noself",
        -- hack
        walkingCollisionID = "worm_walk",
        gluedForceLook = true,
    },
    worm_getup = {
        -- recovering worm (does not collide with other worms)
        collisionID = "worm_now",
        gluedForceLook = true,
    },
    worm_walk = {
        -- walking worm
        collisionID = "worm_walk",
        walkingSpeed = 50,
        gluedForceLook = true,
    },
    worm_jump = {
        collisionID = "worm_air",
        glueForce = 20,
        bounceAbsorb = 400,
        -- no friction when jumping off (would influence jumping angle)
        slideAbsorb = 0,
        friction = 0,
    },
    beaming = {
        collisionID = "worm_n",
        -- don't move
        fixate = Vector2(0, 0),
        damageUnfixate = true,
        gluedForceLook = true,
        -- not invulnerable while beaming, use damage from std_phys
    },
    frozen = {
        -- freezing weapon active
        collisionID = "worm_noself",
        glueForce = 20,
        fixate = Vector2(0, 1),
        damageable = 0,
    },
    jetworm = {
        collisionID = "worm_freemove",
        glueForce = 0,
        velocityConstraint = Vector2(200, 250),
        sustainableImpulse = 5000,
        fallDamageFactor = 0.0,
        rotation = "selfforce",
    },
    rope = {
        collisionID = "worm_fm_rope",
        glueForce = 0,
        elasticity = 0.85,
        fallDamageFactor = 0.0,
        -- extend_normalcheck = true,
    },
    parachute = {
        collisionID = "worm_freemove",
        glueForce = 0,
        airResistance = 0.3,
        mediumViscosity = 0.4,
        sustainableImpulse = 5000,
        fallDamageFactor = 0.0,
    },
    drill = {
        collisionID = "worm_drill",
        glueForce = 0,
        elasticity = 0,
        fallDamageFactor = 0.0,
    },
    grave = { -- duplicated in grave.conf
        collisionID = "grave",
        fixate = Vector2(0, 1),
        elasticity = 0.3,
        glueForce = 50,
    },
    water = {
        collisionID = "waterobj",
        radius = 1,
        damageable = 0.0,
        explosionInfluence = 0.0,
        glueForce = 0,
        directionConstraint = Vector2(0, 1),
    },
    win = {
        damageable = 0.0,
        fixate = Vector2(0, 0),
        gluedForceLook = true,
    },
}

-- all the object states
-- state selects collision class, physics and animations of an object
-- state transition for worms is mostly done by special code...
local states = {
    stand = {
        -- load these physic properties
        physic = "worm_stand",
        animation = "stand",
        isGrounded = true,
        canWalk = true,
        canJump = true,
        canFire = true,
    },
    weapon = {
        physic = "worm_stand",
        -- animation of weapon is "overlayed"
        animation = "stand",
        isGrounded = true,
        canWalk = true,
        canJump = true,
        canAim = true,
        canFire = true,
    },
    beaming = {
        physic = "beaming",
        animation = "beaming",
        noleave = true,
        onAnimationEnd = "reverse_beaming",
        activity = true,
    },
    reverse_beaming = {
        physic = "beaming",
        animation = "reverse_beaming",
        noleave = true,
        onAnimationEnd = "fly",
        activity = true,
    },
    frozen = {
        physic = "frozen",
        animation = "frozen",
        noleave = true,
    },
    unfreeze = {
        -- hack for leave animation
        physic = "frozen",
        animation = "unfreeze",
        onAnimationEnd = "stand",
        noleave = true,
    },
    fly = {
        physic = "worm",
        -- animation chosen by special code
        animation = "fly_fall",
    },
    getup = {
        physic = "worm_getup",
        animation = "bounce_minor",
        onAnimationEnd = "stand",
        isGrounded = true,
        activity = true,
    },
    pre_getup = {
        physic = "worm_getup",
        animation = "fly_slide",
        --onAnimationEnd = "getup",
        isGrounded = true,
        activity = true,
    },
    walk = {
        physic = "worm_walk",
        animation = "walk",
        isGrounded = true,
        canWalk = true,
        canJump = true,
    },
    blowtorch = {
        -- walk while the (blowtorch) weapon is active
        physic = "worm_walk",
        animation = "stand", -- will "overlay" the blowtorch fire animation
        isGrounded = true,
        canWalk = true,
        canJump = false,
        canAim = true,
        canFire = true,
    },
    jetpack = {
        physic = "jetworm",

        animation = "jetpack",
    },
    parachute = {
        animation = "parachute",
    },
    jump_start = {
        physic = "worm",
        animation = "jump_start",
        isGrounded = true,
        onAnimationEnd = "jump",
        activity = true,
    },
    jump = {
        physic = "worm_jump",
        -- custom animation
    },
    jump_to_fly = {
        physic = "worm",
        animation = "jump_to_fall",
        onAnimationEnd = "fly",
    },
    rope = {
        animation = "rope",
    },
    drill = {
        animation = "drill",
    },
    drowning = {
        physic = "water",

        animation = "drown",
        particle = "p_projectiledrown",

        isUnderWater = true,
    },
    drowning_frozen = {
        physic = "water",

        animation = "frozen_drowning",
        particle = "p_projectiledrown",

        isUnderWater = true,
    },
    win = {
        physic = "win",
        animation = "win",
        noleave = true,
        isGrounded = true,
    },
    die = {
        physic = "grave",

        -- byebye-animation
        onAnimationEnd = "dead",
        animation = "die",
        noleave = true,
        isGrounded = true,
        activity = true,
    },
    dead = {
        physic = "grave",
        -- not allowed to leave state
        noleave = true,
    },
}

-- post-process physics
for name, posp in pairs(physics) do
    posp = table_merge(std_phys, posp)
    physics[name] = createPOSP(posp)
end

-- upload the states into the sprite_class
-- all states are instantiated in D code, and we just look them up here
-- (this also makes forward refs for onAnimationEnd simpler)
for name, state in pairs(states) do
    local dstate = sprite_class:findState(name)
    state.physic = physics[state.physic]
    if not state.physic then
        state.physic = physics[name]
    end
    assert(state.physic)
    if state.animation then
        state.animation = sequence_object:findState(state.animation)
    end
    if state.particle then
        state.particle = lookupResource(state.particle)
    end
    if state.onAnimationEnd then
        state.onAnimationEnd = sprite_class:findState(state.onAnimationEnd)
    end
    setProperties(dstate, state)
end

WormSpriteClass.finishLoading(sprite_class)
registerResource(sprite_class, sprite_class:name())

-- play bleep on misfire (xxx not sure if this is the right place to put this)
addGlobalEventHandler("weapon_misfire", function(weapon, wcontrol, reason)
    T(WormControl, wcontrol)
    local s = wcontrol:sprite()
    emitSpriteParticle("p_warning", s)
end)
