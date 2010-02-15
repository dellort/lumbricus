-- Rocket weapons: thrown from worm, explode on impact

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
    local name = "martor"
    local cluster = createSpriteClass {
        name = name .. "_cluster",
        initPhysic = relay {
            collisionID = "projectile",
            mass = 10,
            radius = 2,
            explosionInfluence = 0,
            windInfluence = 0,
            elasticity = 0.4,
        },
        sequenceType = "s_clustershard",
    }
    enableExplosionOnImpact(cluster, 25)
    local main = createSpriteClass {
        name = name .. "_sprite",
        initPhysic = relay {
            collisionID = "projectile",
            mass = 10,
            radius = 2,
            explosionInfluence = 0,
            windInfluence = 0,
            elasticity = 0.4,
        },
        sequenceType = "s_mortar",
        initParticle = "p_rocket"
    }
    -- funfact: on each "impact", a table for the normal will be allocated, even
    --  if it's not in the parameter or
    addSpriteClassEvent(main, "sprite_impact", function(sender, normal)
        if spriteIsGone(sender) then
            return
        end
        spriteExplode(sender, 25)
        spawnCluster(cluster, sender, 5, 250, 300, 50, normal)
    end)

    local w = createWeapon {
        name = name,
        onFire = getStandardOnFire(main),
        category = "fly",
        value = 0,
        animation = "weapon_mortar",
        icon = "icon_mortar",
        fireMode = {
            direction = "any",
            throwStrengthFrom = 1200,
            throwStrengthTo = 1200,
        }
    }
    enableSpriteCrateBlowup(w, cluster, 5)
end


do -- xxx missing: deathzone_immune for active missile
    local name = "homo"
    local inactive_phys = {
        collisionID = "projectile",
        mass = "10",
        radius = "2",
        explosionInfluence = "0",
        windInfluence = "0.0",
        elasticity = "0.4",
    }
    local active_phys = table_modified(inactive_phys, {
        collisionID = "projectile_nobounce",
        zeroGrav = true,
        speedLimit = 700,
    })
    local active_water_phys = table_modified(active_phys, {
        collisionID = "waterobj",
        stokesModifier = 0,
    })

    local sprite_class = createSpriteClass {
        name = name .. "_sprite",
        initPhysic = relay(inactive_phys),
        sequenceType = "s_homing",
        noDrown = true,
    }

    -- States: inactive (rotating, no homing), active and active underwater
    local inactiveState = initSpriteState(sprite_class, "inactive",
        inactive_phys)
    local activeState = initSpriteState(sprite_class, "active", active_phys,
        "p_rocket")
    local activeWaterState = initSpriteState(sprite_class, "active_underwater",
        active_water_phys, "p_projectiledrown")

    -- called to drown the projectile (manually because it can fly underwater)
    local doDrown = getDrownFunc(sprite_class)

    enableExplosionOnImpact(sprite_class, 50)
    -- set initial animation
    addSpriteClassEvent(sprite_class, "sprite_activate", function(sender)
        setSpriteState(sender, inactiveState)
    end)
    -- go active after some time
    enableSpriteTimer(sprite_class, {
        defTimer = time(0.6),
        callback = function(sender)
            setSpriteState(sender, activeState)
            local ctx = get_context(sender)
            local sh = gameObjectFindShooter(sender)
            local fi = Shooter_fireinfo(sh)
            local homing = setSpriteHoming(sender, fi.pointto, 15000, 15000)
            ctx.active = true
            ctx.force = homing
        end
    })
    -- go inactive again after some more time
    enableSpriteTimer(sprite_class, {
        defTimer = time(5.6),
        timerId = "timer2",
        removeUnderwater = false,
        callback = function(sender)
            local ctx = get_context(sender)
            if Sprite_isUnderWater(sender) then
                doDrown(sender)
            else
                setSpriteState(sender, inactiveState)
            end
            ctx.active = false
            assert(ctx.force)
            Phys_kill(ctx.force)
            ctx.force = nil
        end
    })
    -- when going underwater:
    --   a) drown when inactive
    --   b) change physics/animation/particle when active
    addSpriteClassEvent(sprite_class, "sprite_waterstate", function(sender)
        local act = get_context_var(sender, "active", false)
        if act then
            if Sprite_isUnderWater(sender) then
                setSpriteState(sender, activeWaterState)
            else
                setSpriteState(sender, activeState)
            end
        else
            doDrown(sender)
        end
    end)
    -- make sure the force is removed on death
    addSpriteClassEvent(sprite_class, "sprite_die", function(sender)
        local ctx = get_context(sender)
        if ctx.force then
            Phys_kill(ctx.force)
            ctx.force = nil
        end
    end)

    local w = createWeapon {
        name = name,
        onFire = getStandardOnFire(sprite_class),
        category = "fly",
        value = 0,
        animation = "weapon_homing",
        icon = "icon_homing",
        fireMode = {
            point = "targetTracking",
            direction = "any",
            variableThrowStrength = true,
            throwStrengthFrom = 200,
            throwStrengthTo = 1200,
        }
    }

    -- crate sprite: explodes on impact
    local crate_class = createSpriteClass {
        name = name .. "crate_sprite",
        initPhysic = relay(inactive_phys),
        sequenceType = "s_homing",
    }
    enableExplosionOnImpact(crate_class, 50)
    -- set initial animation
    addSpriteClassEvent(crate_class, "sprite_activate", function(sender)
        setSpriteState(sender, inactiveState)
    end)

    enableSpriteCrateBlowup(w, crate_class)
end
