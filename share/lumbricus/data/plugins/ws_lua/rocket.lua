-- Rocket weapons: thrown from worm, explode on impact

do
    local name = "bazooka"
    local sprite_class = createSpriteClass {
        name = "x_" .. name,
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
        name = "w_" .. name,
        onFire = getStandardOnFire(sprite_class, "p_rocket_fire"),
        category = "fly",
        value = 10,
        animation = "weapon_bazooka",
        icon = "icon_bazooka",
        fireMode = {
            direction = "any",
            throwStrengthFrom = 200,
            throwStrengthTo = 1200,
        }
    }
    enableSpriteCrateBlowup(w, sprite_class)
    bazooka_class = sprite_class
end

do
    local name = "mortar"
    local cluster = createSpriteClass {
        name = "x_" .. name .. "_cluster",
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
        name = "x_" .. name,
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
    addSpriteClassEvent(main, "sprite_impact", function(sender, other, normal)
        if spriteIsGone(sender) then
            return
        end
        spriteExplode(sender, 25)
        spawnCluster(cluster, sender, 5, 250, 300, 50, normal)
    end)

    local w = createWeapon {
        name = "w_" .. name,
        onFire = getStandardOnFire(main, "p_rocket_fire"),
        category = "fly",
        value = 10,
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
    local name = "homing"
    local inactive_phys = {
        collisionID = "projectile",
        mass = "10",
        radius = "2",
        explosionInfluence = "0",
        windInfluence = "0.0",
        elasticity = "0.4",
    }
    local active_phys = table_merge(inactive_phys, {
        collisionID = "projectile_nobounce",
        zeroGrav = true,
        speedLimit = 700,
    })
    local active_water_phys = table_merge(active_phys, {
        collisionID = "waterobj",
        stokesModifier = 0,
    })

    local sprite_class = createSpriteClass {
        name = "x_" .. name,
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
            local fi = Shooter.fireinfo(sh)
            local homing = setSpriteHoming(sender, fi.pointto, 15000, 15000)
            -- xxx slightly wrong because the sound is not attached to the sprite
            emitSpriteParticle("p_homing_activate", sender)
            ctx.active = true
            ctx.force = homing
        end
    })
    -- go inactive again after some more time
    enableSpriteTimer(sprite_class, {
        defTimer = time(5.6),
        removeUnderwater = false,
        callback = function(sender)
            local ctx = get_context(sender)
            if Sprite.isUnderWater(sender) then
                doDrown(sender)
            else
                setSpriteState(sender, inactiveState)
            end
            ctx.active = false
            assert(ctx.force)
            Phys.kill(ctx.force)
            ctx.force = nil
        end
    })
    -- when going underwater:
    --   a) drown when inactive
    --   b) change physics/animation/particle when active
    addSpriteClassEvent(sprite_class, "sprite_waterstate", function(sender)
        local act = get_context_var(sender, "active", false)
        if act then
            if Sprite.isUnderWater(sender) then
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
            Phys.kill(ctx.force)
            ctx.force = nil
        end
    end)

    local w = createWeapon {
        name = "w_" .. name,
        onFire = getStandardOnFire(sprite_class, "p_rocket_fire"),
        category = "fly",
        value = 10,
        animation = "weapon_homing",
        icon = "icon_homing",
        fireMode = {
            point = "targetTracking",
            direction = "any",
            throwStrengthFrom = 200,
            throwStrengthTo = 1200,
        }
    }

    -- crate sprite: explodes on impact
    local crate_class = createSpriteClass {
        name = "x_" .. name .. "crate_sprite",
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

-- the bow is not really a rocket, but behaves like one
-- actually, it is something in between a gun (fast projectile) and a rocket
-- (Box2D has "bullet" type objects, which do CCD => can be arbitrarily fast)
-- xxx I think arrows have 2 shots, and you can still move around between them?
do
    local name = "w_bow"

    local sc = createSpriteClass {
        name = "x_" .. name,
        initPhysic = relay {
            collisionID = "projectile",
            mass = 9,
            radius = 1,
            explosionInfluence = 0.5,
            windInfluence = 0.1,
            elasticity = 0.4,
        },
        sequenceType = "s_arrow",
    }

    -- must be defined as extra resource, because extracting the actual frame
    --  from the animation is too complicated (would require hacks over hacks)
    local arrow_bmp = lookupResource("arrow_bitmap")

    -- funfact: on each "impact", a table for the normal will be allocated, even
    --  if it's not in the parameter or
    addSpriteClassEvent(sc, "sprite_impact", function(sender, other, normal)
        if spriteIsGone(sender) then
            return
        end
        -- no idea why other is null sometimes (actually, when colliding with
        --  worms), must be the hit_noimpulse stuff?
        if other and Phys.isStatic(other) then
            -- put it as bitmap!
            local ph = Sprite.physics(sender)
            local rot = Phys.lookey(ph) + math.pi/2
            local at = Phys.pos(ph)
            -- creates a new surface on each impact; could cache it
            local bmp = Surface.rotated(arrow_bmp, rot, true)
            at = at - Surface.size(bmp) / 2
            Game:insertIntoLandscape(at, bmp, Lexel_soft)
        elseif other then
            -- xxx I tested using real physics to pass the impulse, but it was
            --     way to random (sometimes no move, sometimes the whole screen)
            local ph = Sprite.physics(sender)
            local vel = Phys.velocity(ph)
            applyMeleeImpulse(other, sender, 2, 30, vel)
        else
            -- can happen when it hits via "hit_noimpulse"
            log.warn("arrow impacted on unknown object")
            spriteExplode(sender, 10)
        end
        Sprite.kill(sender)
    end)

    local w = createWeapon {
        name = name,
        onFire = getStandardOnFire(sc),
        category = "fly",
        value = 10,
        animation = "weapon_bow",
        icon = "icon_bow",
        fireMode = {
            direction = "any",
            throwStrengthFrom = 1200,
            throwStrengthTo = 1200,
        }
    }
end
