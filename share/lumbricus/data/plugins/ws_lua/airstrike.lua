-- Airstrike-type weapons (defined by using AirstrikeControl)

do
    local name = "iarstrake"
    local sprite_class = createSpriteClass {
        name = name .. "_sprite",
        initPhysic = relay {
            collisionID = "projectile",
            mass = 10,
            radius = 2,
            explosionInfluence = 0.0,
            windInfluence = 0.0,
        },
        sequenceType = "s_airstrike",
        initParticle = "p_rocket",
    }
    enableExplosionOnImpact(sprite_class, 35)

    local w = createWeapon {
        name = name,
        onFire = getAirstrikeOnFire(sprite_class),
        onCreateSelector = AirstrikeControl_ctor,
        value = 0,
        category = "air",
        isAirstrike = true,
        icon = "icon_airstrike",
        animation = "weapon_airstrike",
        fireMode = {
            point = "instant",
            throwStrengthFrom = 300,
            throwStrengthTo = 300,
        }
    }
    enableSpriteCrateBlowup(w, sprite_class, 4)
end

do
    local name = "manestrake"

    local w = createWeapon {
        name = name,
        onFire = getAirstrikeOnFire(mine_class, 10, 25),
        onCreateSelector = AirstrikeControl_ctor,
        value = 0,
        category = "air",
        isAirstrike = true,
        icon = "icon_minestrike",
        animation = "weapon_airstrike",
        fireMode = {
            point = "instant",
            throwStrengthFrom = 300,
            throwStrengthTo = 300,
        }
    }
    enableSpriteCrateBlowup(w, mine_class, 5)
end

do
    local name = "nalmpastrike"
    local sprite_class = createSpriteClass {
        name = name .. "_sprite",
        initPhysic = relay {
            collisionID = "projectile",
            mass = 10,
            radius = 2,
            explosionInfluence = 0.0,
            windInfluence = 0.0,
        },
        sequenceType = "s_airstrike",
        initParticle = "p_rocket",
    }
    enableExplosionOnImpact(sprite_class, 35)
    enableSpriteTimer(sprite_class, {
        defTimer = time("500 ms"),
        showDisplay = false,
        callback = function(sender)
            -- use the sender's velocity (direction and magnitude)
            local vel = Phys_velocity(Sprite_physics(sender))
            spawnCluster(worms_shared.standard_napalm, sender, 15, 1, 1, 60,
                vel)
        end,
    })

    local w = createWeapon {
        name = name,
        onFire = getAirstrikeOnFire(sprite_class, 8, 45),
        onCreateSelector = AirstrikeControl_ctor,
        value = 0,
        category = "air",
        isAirstrike = true,
        icon = "icon_napalmstrike",
        -- cooldown = time("5s")
        animation = "weapon_airstrike",
        fireMode = {
            point = "instant",
            throwStrengthFrom = 300,
            throwStrengthTo = 300,
        }
    }
    enableSpriteCrateBlowup(w, sprite_class, 2)
end

do
    local name = "cerpatstrake"
    local sprite_class = createSpriteClass {
        name = name .. "_sprite",
        initPhysic = relay {
            collisionID = "projectile",
            mass = 10,
            radius = 9,
            explosionInfluence = 0.0,
            windInfluence = 0.0,
            elasticity = 0.6,    -- by experiment
            rotation = "distance",
        },
        sequenceType = "s_carpetstrike",
    }
    enableBouncer(sprite_class, 3, function(sender)
        spriteExplode(sender, 40, false)
    end)

    local w = createWeapon {
        name = name,
        onFire = getAirstrikeOnFire(sprite_class, 6, 45),
        onCreateSelector = function(sprite)
            return AirstrikeControl_ctor(sprite)
        end,
        value = 0,
        category = "air",
        isAirstrike = true,
        icon = "icon_carpetstrike",
        animation = "weapon_airstrike",
        fireMode = {
            point = "instant",
            throwStrengthFrom = 300,
            throwStrengthTo = 300,
        }
    }
    enableSpriteCrateBlowup(w, sprite_class, 3)
end

do
    local name = "peeshstrake"
    local sprite_class = createSpriteClass {
        name = name .. "_sprite",
        initPhysic = relay {
            collisionID = "projectile",
            mass = 10,
            radius = 10,
            explosionInfluence = 0.0,
            windInfluence = 0.0,
            elasticity = 0.6,    -- by experiment
            rotation = "distance",
        },
        sequenceType = "s_sheepstrike",
    }
    enableBouncer(sprite_class, 1, function(sender)
        spawnCluster(worms_shared.standard_napalm, sender, 10, 0, 0, 60)
        spriteExplode(sender, 40, false)
    end)

    local w = createWeapon {
        name = name,
        onFire = getAirstrikeOnFire(sprite_class, 6, 45),
        onCreateSelector = function(sprite)
            return AirstrikeControl_ctor(sprite)
        end,
        value = 0,
        category = "air",
        isAirstrike = true,
        icon = "icon_sheepstrike",
        animation = "weapon_airstrike",
        fireMode = {
            point = "instant",
            throwStrengthFrom = 300,
            throwStrengthTo = 300,
        }
    }
    enableSpriteCrateBlowup(w, sprite_class, 3)
end

