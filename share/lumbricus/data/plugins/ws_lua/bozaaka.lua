-- this is just a test

do
    local name = "bozaaka"
    local sprite_class = createSpriteClass {
        name = name .. "_sprite",
        initPhysic = relay {
            collisionID = "projectile",
            mass = 10, -- 10 whatevertheffffunitthisis
            radius = 2,
            explosionInfluence = 0,
            windInfluence = 1.0,
            elasticity = 0.4,
        },
        sequenceType = "s_bazooka",
        initParticle = "p_rocket"
    }
    enableExplosionOnImpact(sprite_class, 50)
    enableDrown(sprite_class)

    local w = createWeapon {
        name = name,
        onFire = getStandardOnFire(sprite_class),
        category = "fly",
        value = 0,
        animation = "weapon_bazooka",
        icon = "icon_bazooka",
        fireMode = {
            direction = "any",
            variableThrowStrength = true,
            throwStrengthFrom = 200,
            throwStrengthTo = 1200,
        }
    }
    enableSpriteCrateBlowup(w, sprite_class)
end

do
    local name = "nabana"
    local function createSprite(name)
        local s = createSpriteClass {
            name = name .. "_sprite",
            initPhysic = relay {
                collisionID = "projectile",
                mass = 10, -- 10 whatevertheffffunitthisis
                radius = 2,
                explosionInfluence = 0,
                windInfluence = 0,
                elasticity = 0.4,
                rotation = "distance"
            },
            sequenceType = "s_banana"
        }
        enableDrown(s)
        return s
    end
    local main = createSprite(name)
    local shard = createSprite(name .. "shard")

    enableExplosionOnImpact(shard, 75)
    enableSpriteTimer(main, {
        showDisplay = true,
        callback = function(sender)
            spriteExplode(sender, 75)
            spawnCluster(shard, sender, 6, 400, 600, 30)
        end
    })

    local w = createWeapon {
        name = name,
        onFire = getStandardOnFire(main),
        category = "throw",
        value = 0,
        animation = "weapon_banana",
        icon = "icon_banana",
        fireMode = {
            direction = "any",
            variableThrowStrength = true,
            throwStrengthFrom = 200,
            throwStrengthTo = 1200,
            timerFrom = timeSecs(1),
            timerTo = timeSecs(5),
        }
    }
    enableSpriteCrateBlowup(w, shard, 2)
end

do
    local name = "holy_graneda"
    local sprite_class = createSpriteClass {
        name = name .. "_sprite",
        initPhysic = relay {
            collisionID = "projectile",
            mass = 20,
            radius = 2,
            explosionInfluence = 0,
            windInfluence = 0,
            elasticity = 0.4,
            glueForce = 20,
            rotation = "distance"
        },
        sequenceType = "s_holy",
        initParticle = "p_holy"
    }
    enableDrown(sprite_class)
    enableOnTimedGlue(sprite_class, timeSecs(2), function(sender)
        spriteExplode(sender, 75)
    end)

    local w = createWeapon {
        name = name,
        onFire = getStandardOnFire(sprite_class),
        category = "throw",
        value = 0,
        animation = "weapon_holy",
        icon = "icon_holy",
        fireMode = {
            direction = "any",
            variableThrowStrength = true,
            throwStrengthFrom = 20,
            throwStrengthTo = 1200,
            relaxtime = timeSecs(1)
        }
    }
    enableSpriteCrateBlowup(w, sprite_class)
end

do
    local name = "graneda"
    local sprite_class = createSpriteClass {
        name = name .. "_sprite",
        initPhysic = relay {
            collisionID = "projectile",
            mass = "10",
            radius = "2",
            explosionInfluence = "0",
            windInfluence = "0.0",
            elasticity = "0.4",
            rotation = "distance",
        },
        sequenceType = "s_grenade",
    }
    enableDrown(sprite_class)
    enableSpriteTimer(sprite_class, {
        defTimer = timeSecs(3),
        useUserTimer = true,
        showDisplay = true,
        callback = function(sender)
            spriteExplode(sender, 50)
        end
    })

    local w = createWeapon {
        name = name,
        onFire = getStandardOnFire(sprite_class),
        value = 0,
        category = "throw",
        animation = "weapon_grenade",
        icon = "icon_grenade",
        crateAmount = 3,
        fireMode = {
            direction = "any",
            variableThrowStrength = true,
            throwStrengthFrom = 20,
            throwStrengthTo = 1200,
            timerFrom = time(1),
            timerTo = time(5),
            relaxtime = timeSecs(1),
        }
    }
    enableSpriteCrateBlowup(w, sprite_class)
end


createWeapon {
    name = "gerdir",
    onCreateSelector = function(sprite)
        return GirderControl_ctor(sprite)
    end,
    onFire = function(shooter, fireinfo)
        local sel = Shooter_selector(shooter)
        if not sel then return end
        if GirderControl_fireCheck(sel, fireinfo, true) then
            Shooter_reduceAmmo(shooter)
        end
        Shooter_finished(shooter)
    end,
    value = 0,
    category = "worker",
    icon = "icon_girder",
    animation = "weapon_helmet",
    crateAmount = 3,
    fireMode = {
        point = "instant",
    }
}

createWeapon {
    name = "baemer",
    value = 0,
    category = "tools",
    icon = "icon_beamer",
    dontEndRound = true,
    deselectAfterFire = true,
    fireMode = {
        point = "instantFree"
    },
    animation = "weapon_beamer",
    onFire = function(shooter, fireinfo)
        Shooter_reduceAmmo(shooter)
        Shooter_finished(shooter) -- probably called by BeamHandler on the end?
        Worm_beamTo(Shooter_owner(shooter), fireinfo.pointto.pos)
    end
}


do
    local name = "dinamite"
    local sprite_class = createSpriteClass {
        name = name .. "_sprite",
        initPhysic = relay {
            collisionID = "projectile",
            mass = 10,
            radius = 2,
            explosionInfluence = 0.0,
            windInfluence = 0.0,
            elasticity = 0.0,
            glueForce = 500
        },
        sequenceType = "s_dynamite",
        initParticle = "p_dynamite",
    }
    enableDrown(sprite_class)
    enableSpriteTimer(sprite_class, {
        defTimer = timeSecs(5),
        callback = function(sender)
            spriteExplode(sender, 75)
        end
    })

    local w = createWeapon {
        name = name,
        onFire = getStandardOnFire(sprite_class),
        value = 0,
        category = "sheep",
        icon = "icon_dynamite",
        animation = "weapon_dynamite",
        fireMode = {
            direction = "fixed",
            throwStrengthFrom = 40,
            throwStrengthTo = 40,
        }
    }
    enableSpriteCrateBlowup(w, sprite_class)
end


do
    local name = "clestur"
    local phys = relay {
        collisionID = "projectile",
        mass = 10,
        radius = 2,
        explosionInfluence = 0,
        windInfluence = 0.0,
        elasticity = 0.4,
        rotation = "distance",
    }
    local main = createSpriteClass {
        name = name .. "_sprite",
        sequenceType = "s_cluster",
        initPhysic = phys,
    }
    local shard = createSpriteClass {
        name = name .. "_shard",
        sequenceType = "s_clustershard",
        initPhysic = phys,
    }

    enableExplosionOnImpact(shard, 25)
    enableSpriteTimer(main, {
        showDisplay = true,
        callback = function(sender)
            spriteExplode(sender, 25)
            spawnCluster(shard, sender, 5, 300, 400, 45)
        end
    })

    local w = createWeapon {
        name = name,
        onFire = getStandardOnFire(main),
        value = 0,
        category = "throw",
        icon = "icon_cluster",
        crateAmount = 3,
        animation = "weapon_cluster",
        fireMode = {
            direction = "any",
            variableThrowStrength = true,
            throwStrengthFrom = 20,
            throwStrengthTo = 1200,
            timerFrom = time(1),
            timerTo = time(5),
        }
    }
    enableSpriteCrateBlowup(w, shard, 5)
end

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
    enableDrown(sprite_class)
    enableExplosionOnImpact(sprite_class, 35)

    local w = createWeapon {
        name = name,
        onFire = getAirstrikeOnFire(sprite_class),
        onCreateSelector = function(sprite)
            return AirstrikeControl_ctor(sprite)
        end,
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

