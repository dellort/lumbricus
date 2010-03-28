local sprite_class = WormSpriteClass_ctor(Gfx, "x_worm")

-- selects SequenceObject, which again is provided in wwp.conf
local sequence_object = Gfx_resource("s_worm")

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
    ropeImpulse = 700,
    sequenceType = sequence_object,
})

-- physical states, used by the "states" section
local physics = {
    worm = {
        -- collision class the worm physical object is set to
        collisionID = "worm_air",
        radius = 5,
        mass = 10,
        glueForce = 20,
        elasticity = 0.5,
        bounceAbsorb = 400,
        slideAbsorb = 150,
        damageable = 1.0,
        friction = 0.9,
        extendNormalcheck = true,
        sustainableImpulse = 5000,
        fallDamageFactor = 0.004,
        fallDamageIgnoreX = true,
        speedLimit = 2500,
    },
    worm_stand = {
        -- sitting worm
        collisionID = "worm_noself",
        radius = 5,
        mass = 10,
        elasticity = 0.5,
        damageable = 1.0,
        gluedForceLook = true,
    },
    worm_getup = {
        -- recovering worm (does not collide with other worms)
        collisionID = "worm_now",
        radius = 5,
        mass = 10,
        elasticity = 0.5,
        damageable = 1.0,
        gluedForceLook = true,
    },
    worm_walk = {
        -- walking worm
        collisionID = "worm_now",
        radius = 5,
        mass = 10,
        walkingSpeed = 50,
        elasticity = 0.5,
        damageable = 1.0,
        gluedForceLook = true,
    },
    beaming = {
        collisionID = "worm_n",
        radius = 5,
        mass = 10,
        -- don't move
        fixate = Vector2(0, 0),
        damageUnfixate = true,
        -- not invulnerable while beaming
        damageable = 1.0,
        gluedForceLook = true,
    },
    jetworm = {
        collisionID = "worm_freemove",
        radius = 5,
        mass = 10,
        glueForce = 0,
        elasticity = 0.5,
        velocityConstraint = Vector2(200, 250),
        damageable = 1.0,
        sustainableImpulse = 5000,
        fallDamageFactor = 0.0,
        rotation = "selfforce",
    },
    rope = {
        collisionID = "worm_fm_rope",
        radius = 5,
        mass = 10,
        glueForce = 0,
        elasticity = 0.85,
        damageable = 1.0,
        fallDamageFactor = 0.0,
        -- extend_normalcheck = true,
    },
    parachute = {
        collisionID = "worm_freemove",
        radius = 5,
        mass = 10,
        glueForce = 0,
        elasticity = 0.5,
        airResistance = 0.3,
        mediumViscosity = 0.4,
        damageable = 1.0,
        sustainableImpulse = 5000,
        fallDamageFactor = 0.0,
    },
    drill = {
        collisionID = "worm_drill",
        radius = 5,
        mass = 10,
        glueForce = 0,
        elasticity = 0,
        damageable = 1.0,
        fallDamageFactor = 0.0,
    },
    grave = { -- duplicated in grave.conf
        collisionID = "grave",
        radius = 5,
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
        canFire = true,
    },
    weapon = {
        physic = "worm_stand",
        -- animation of weapon is "overlayed"
        animation = "stand",
        isGrounded = true,
        canWalk = true,
        canAim = true,
        canFire = true,
    },
    beaming = {
        physic = "beaming",
        animation = "beaming",
        noleave = true,
        onAnimationEnd = "reverse_beaming",
    },
    reverse_beaming = {
        physic = "beaming",
        animation = "reverse_beaming",
        noleave = true,
        onAnimationEnd = "fly",
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
    },
    walk = {
        physic = "worm_walk",
        animation = "walk",
        isGrounded = true,
        canWalk = true,
    },
    blowtorch = {
        physic = "worm_walk",
        animation = "walk_blowtorch",
        isGrounded = true,
        -- canWalk = true,
        canAim = true,
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
    },
    jump = {
        physic = "worm",
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
    },
    dead = {
        physic = "grave",
        -- not allowed to leave state
        noleave = true,
    },
}

-- post-process physics
for name, posp in pairs(physics) do
    physics[name] = createPOSP(posp)
end

-- upload the states into the sprite_class
-- all states are instantiated in D code, and we just look them up here
-- (this also makes forward refs for onAnimationEnd simpler)
for name, state in pairs(states) do
    local dstate = WormSpriteClass_findState(sprite_class, name)
    state.physic = physics[state.physic]
    if state.animation then
        state.animation = SequenceType_findState(sequence_object,
            state.animation)
    end
    if state.particle then
        state.particle = Gfx_resource(state.particle)
    end
    if state.onAnimationEnd then
        state.onAnimationEnd = WormSpriteClass_findState(sprite_class,
            state.onAnimationEnd)
    end
    setProperties(dstate, state)
end

WormSpriteClass_finishLoading(sprite_class)
Gfx_registerResource(SpriteClass_name(sprite_class), sprite_class)
