-- Weapons that spawn moving/jumping/controlled projectiles that collect crates

do
    local name = "peesh"
    local function createSprite(name)
        return createSpriteClass {
            name = name .. "_sprite",
            initPhysic = relay {
                collisionID = "projectile_controlled",
                mass = 10,
                radius = 6,
                explosionInfluence = 0.0,
                windInfluence = 0.0,
                elasticity = 0.0,
                glueForce = 500,
                walkingSpeed = 50
            },
            sequenceType = "s_sheep",
            initParticle = "p_sheep",
        }
    end

    local sprite_class = createSprite(name)
    local seqNormal = findSpriteSeqType(sprite_class, "normal")
    local seqHelmet = findSpriteSeqType(sprite_class, "helmet")

    -- take off helmet on impact
    addSpriteClassEvent(sprite_class, "sprite_impact", function(sender)
        Sequence_setState(Sprite_graphic(sender), seqNormal)
    end)
    -- start walking on spawn
    enableWalking(sprite_class)
    -- jump in random intervals
    enableSpriteTimer(sprite_class, {
        defTimer = time(0.2),
        periodic = true,
        timerId = "jump",
        callback = function(sender)
            local phys = Sprite_physics(sender)
            if not Phys_isGlued(phys) then
                return
            end
            if Random_rangei(1, 5) == 1 then
                local look = lookSide(phys)
                Phys_addImpulse(phys, Vector2(look * 2500, -2500))
            end
        end
    })

    local function dorefire(shooter)
        Shooter_finished(shooter)
        local sprite = get_context_var(shooter, "sprite")
        spriteExplode(sprite, 75)
        return true
    end
    -- don't live longer than 8s
    enableSpriteTimer(sprite_class, {
        defTimer = time(8),
        showDisplay = true,
        callback = function(sender)
            dorefire(get_context_var(sender, "shooter"))
        end
    })

    -- used by other weapons (I think)
    cratesheep_class = createSprite("crate" .. name)
    enableExplosionOnImpact(cratesheep_class, 75)

    local w = createWeapon {
        name = name,
        onFire = function(shooter, info)
            Shooter_reduceAmmo(shooter)
            local s = spawnFromFireInfo(sprite_class, shooter, info)
            set_context_var(shooter, "sprite", s)
        end,
        onRefire = dorefire,
        canRefire = true,
        value = 0,
        category = "moving",
        icon = "icon_sheep",
        animation = "weapon_sheep",
        fireMode = {
            direction = "fixed",
            throwStrengthFrom = 40,
            throwStrengthTo = 40,
        }
    }
    enableSpriteCrateBlowup(w, cratesheep_class)

    -- sheeplauncher is almost exactly the same, but the sheep spawns with
    --   the "helmet" animation
    local name = name .. "launcher"
    local w = createWeapon {
        name = name,
        onFire = function(shooter, info)
            Shooter_reduceAmmo(shooter)
            local s = spawnFromFireInfo(sprite_class, shooter, info)
            Sequence_setState(Sprite_graphic(s), seqHelmet)
            set_context_var(shooter, "sprite", s)
        end,
        onRefire = dorefire,
        canRefire = true,
        value = 0,
        category = "fly",
        icon = "icon_sheeplauncher",
        animation = "weapon_sheeplauncher",
        fireMode = {
            direction = "any",
            throwStrengthFrom = 600,
            throwStrengthTo = 600,
        }
    }
    enableSpriteCrateBlowup(w, cratesheep_class)
end

do
    local name = "gramma"
    local sprite_class = createSpriteClass {
        name = name .. "_sprite",
        initPhysic = relay {
            collisionID = "projectile_controlled",
            mass = 10,
            radius = 6,
            explosionInfluence = 0.0,
            windInfluence = 0.0,
            elasticity = 0.0,
            glueForce = 500,
            walkingSpeed = 25,
        },
        sequenceType = "s_granny",
        initParticle = "p_granny",
    }
    enableWalking(sprite_class)
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
        category = "moving",
        icon = "icon_granny",
        animation = "weapon_granny",
        fireMode = {
            direction = "fixed",
            throwStrengthFrom = 40,
            throwStrengthTo = 40,
        }
    }
    enableSpriteCrateBlowup(w, sprite_class)
end

do
    local name = "salvo"
    local main = createSpriteClass {
        name = name .. "_sprite",
        initPhysic = relay {
            collisionID = "projectile_controlled",
            mass = 10,
            radius = 9,
            explosionInfluence = 0.0,
            windInfluence = 0.0,
            elasticity = 0.0,
            glueForce = 500,
            walkingSpeed = 25,
        },
        sequenceType = "s_sally_army",
        initParticle = "p_sallyarmy",
    }
    local shard = createSpriteClass {
        name = name .. "shard_sprite",
        initPhysic = relay {
            collisionID = "projectile",
            mass = 10,
            radius = 2,
            explosionInfluence = 0.0,
            windInfluence = 0.0,
            elasticity = 0.4,
            rotation = "distance"
        },
        sequenceType = "s_sallyshard",
    }

    local function dorefire(shooter)
        Shooter_finished(shooter)
        local sprite = get_context_var(shooter, "sprite")
        spriteExplode(sprite, 50)
        spawnCluster(shard, sprite, 5, 350, 450, 50)
        return true
    end

    enableExplosionOnImpact(shard, 60)
    enableWalking(main)
    enableSpriteTimer(main, {
        defTimer = time(8),
        showDisplay = true,
        callback = function(sender)
            dorefire(get_context_var(sender, "shooter"))
        end
    })

    local w = createWeapon {
        name = name,
        onFire = function(shooter, info)
            Shooter_reduceAmmo(shooter)
            local spr = spawnFromFireInfo(main, shooter, info)
            set_context_var(shooter, "sprite", spr)
        end,
        onRefire = dorefire,
        canRefire = true,
        value = 0,
        category = "moving",
        icon = "icon_salvationarmy",
        animation = "weapon_sally_army",
        fireMode = {
            direction = "fixed",
            throwStrengthFrom = 40,
            throwStrengthTo = 40,
        }
    }
    enableSpriteCrateBlowup(w, shard, 4)
end

do
    local name = "ox"
    local sprite_class = createSpriteClass {
        name = name .. "_sprite",
        initPhysic = relay {
            collisionID = "projectile_controlled",
            mass = 10,
            radius = 5,
            explosionInfluence = 0.0,
            windInfluence = 0.0,
            elasticity = 0.0,
            glueForce = 500,
            walkingSpeed = 50,
        },
        sequenceType = "s_cow",
        initParticle = "p_cow",
    }
    enableWalking(sprite_class, function(sprite)
        spriteExplode(sprite, 75)
    end)
    enableSpriteTimer(sprite_class, {
        defTimer = timeSecs(10),
        showDisplay = true,
        callback = function(sender)
            spriteExplode(sender, 75)
        end
    })

    local fire, interrupt = getMultispawnOnFire(sprite_class, 3, time(0.6), true)
    local w = createWeapon {
        name = name,
        onFire = fire,
        onInterrupt = interrupt,
        value = 0,
        category = "moving",
        icon = "icon_cow",
        animation = "weapon_cow",
        crateAmount = 3,
        fireMode = {
            direction = "fixed",
            throwStrengthFrom = 40,
            throwStrengthTo = 40,
        }
    }
    enableSpriteCrateBlowup(w, sprite_class)
end

