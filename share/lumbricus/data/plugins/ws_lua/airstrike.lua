-- Airstrike-type weapons (defined by using AirstrikeControl)

do
    local name = "airstrike"
    local sprite_class = createSpriteClass {
        name = "x_" .. name,
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
        name = "w_" .. name,
        onFire = getAirstrikeOnFire(sprite_class),
        onCreateSelector = AirstrikeControl.ctor,
        value = 10000,
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
    local name = "minestrike"

    local w = createWeapon {
        name = "w_" .. name,
        onFire = getAirstrikeOnFire(mine_class, 10, 25),
        onCreateSelector = AirstrikeControl.ctor,
        value = 10000,
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
    local name = "napalmstrike"
    local sprite_class = createSpriteClass {
        name = "x_" .. name,
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
            local vel = sender:physics():velocity()
            spawnCluster(worms_shared.standard_napalm, sender, 15, 1, 1, 60,
                vel)
            spriteExplode(sender, 25)
        end,
    })

    local w = createWeapon {
        name = "w_" .. name,
        onFire = getAirstrikeOnFire(sprite_class, 8, 45),
        onCreateSelector = AirstrikeControl.ctor,
        value = 10000,
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
    local name = "carpetstrike"
    local sprite_class = createSpriteClass {
        name = "x_" .. name,
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
        name = "w_" .. name,
        onFire = getAirstrikeOnFire(sprite_class, 6, 45),
        onCreateSelector = AirstrikeControl.ctor,
        value = 10000,
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
    local name = "sheepstrike"
    local sprite_class = createSpriteClass {
        name = "x_" .. name,
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
        name = "w_" .. name,
        onFire = getAirstrikeOnFire(sprite_class, 6, 45),
        onCreateSelector = AirstrikeControl.ctor,
        value = 10000,
        category = "air",
        isAirstrike = true,
        cooldown = time("5s"),
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

do
    local name = "letterstrike"
    local sprite_class = createSpriteClass {
        name = "x_" .. name,
        initPhysic = relay {
            collisionID = "projectile",
            mass = 3,
            radius = 5,
            explosionInfluence = 0.5,
            -- xxx maybe randomize a little to make it look more dynamic
            airResistance = 0.2,
        },
        -- xxx same random selection as mingshard (not really worth it)
        sequenceType = "s_letterbomb2",
    }
    enableExplosionOnImpact(sprite_class, 35)

    local w = createWeapon {
        name = "w_" .. name,
        onFire = getAirstrikeOnFire(sprite_class),
        onCreateSelector = AirstrikeControl.ctor,
        value = 10000,
        category = "air",
        isAirstrike = true,
        icon = "icon_letterbomb",
        animation = "weapon_airstrike",
        fireMode = {
            point = "instant",
            throwStrengthFrom = 300,
            throwStrengthTo = 300,
        }
    }
    enableSpriteCrateBlowup(w, sprite_class, 4)
end
