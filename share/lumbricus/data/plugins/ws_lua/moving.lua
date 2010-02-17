-- Weapons that spawn moving/jumping/controlled projectiles that collect crates

local function enableSheepJumping(sprite_class)
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
end

do
    local name = "sheep"
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

    enableSheepJumping(sprite_class)

    local function dorefire(shooter)
        Shooter_finished(shooter)
        local sprite = get_context_var(shooter, "sprite")
        if not spriteIsGone(sprite) then
            spriteExplode(sprite, 75)
        end
        return true
    end
    local function interrupt(shooter)
        -- don't keep control while sheep is still active, but worm isn't
        -- (actually, it may be unneeded, but weapon control code keeps showing
        --  a wrong animation as long as shooter is active *shrug*)
        Shooter_finished(shooter)
    end
    -- don't live longer than 8s
    enableSpriteTimer(sprite_class, {
        defTimer = time(8),
        showDisplay = true,
        callback = function(sender)
            dorefire(gameObjectFindShooter(sender))
        end
    })
    -- cleanup
    addSpriteClassEvent(sprite_class, "sprite_waterstate", function(sender)
        dorefire(gameObjectFindShooter(sender))
    end)

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
        onInterrupt = interrupt,
        value = 10,
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
        onInterrupt = interrupt,
        value = 10,
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
    local name = "granny"
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
        value = 10,
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
    local name = "sally_army"
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
        -- not under water
        if spriteIsGone(sprite) then
            return
        end
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
            dorefire(gameObjectFindShooter(sender))
        end
    })

    -- cleanup
    addSpriteClassEvent(main, "sprite_waterstate", function(sender)
        dorefire(gameObjectFindShooter(sender))
    end)

    local w = createWeapon {
        name = name,
        onFire = function(shooter, info)
            Shooter_reduceAmmo(shooter)
            local spr = spawnFromFireInfo(main, shooter, info)
            set_context_var(shooter, "sprite", spr)
        end,
        onRefire = dorefire,
        canRefire = true,
        value = 10,
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
    local name = "cow"
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
        value = 10,
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



local function createSuperSheep(name, is_aqua)
    -- apparently, these properties are almost always the same
    local phys = {
        collisionID = "projectile_controlled",
        radius = 6,
        explosionInfluence = 0.0,
        windInfluence = 0.0,
        elasticity = 0.0,
        glueForce = 500,
        walkingSpeed = 50
    }

    local jumping = createSpriteClass {
        name = name .. "_sprite_jumping",
        initPhysic = relay(table_merge(phys, {
            mass = 10,
            walkingSpeed = 50,
        })),
        sequenceType = "s_sheep",
        initParticle = "p_sheep",
    }
    enableSheepJumping(jumping)

    -- flying sheep

    phys = table_merge(phys, {
        mass = 1,
        zeroGrav = true,
        rotation = "selfforce",
        speedLimit = 300,
    })

    local flying = createSpriteClass {
        name = name .. "_sprite_flying",
        initPhysic = relay(phys),
        sequenceState = "s_sheep:super_" .. iif(is_aqua, "blue", "red"),
        initParticle = "p_supersheep",
        noDrown = true,
    }

    enableExplosionOnImpact(flying, 75)

    local state_air = createNormalSpriteState(flying)

    -- unused if not is_aqua
    local water_ani = "super_blue_underwater"
    local state_water = initSpriteState(flying, water_ani, table_merge(phys, {
        collisionID = "waterobj",
        stokesModifier = 0,
    }))

    -- unused if is_aqua
    -- note that it will be used on the "wrong" class ("flying" instead of
    --  "jumping"), but it works anyway, because all sprites are the same
    -- xxx duplicates what is generated for "jumping" anyway
    -- also, maybe the drown stuff could either...
    --  1. work together with sprite state stuff
    --  2. or exchange the SpriteClass, then we don't need this
    local dodrown = getDrownFunc(jumping)

    -- sender = shooter or sprite spawned by shooter
    local function cleanup(sender)
        local shooter = gameObjectFindShooter(sender)
        local ctx = get_context(shooter)
        -- remove control e.g. when it starts drowning
        if ctx.control then
            ControlRotate_kill(ctx.control)
            ctx.control = nil
        end
        Shooter_finished(shooter)
    end

    -- sender = shooter or sprite spawned by shooter
    local function dorefire(sender)
        local shooter = gameObjectFindShooter(sender)
        local ctx = get_context(shooter)
        if not spriteIsGone(ctx.sprite) then
            if ctx.phase1 then
                -- make it fly
                -- creating a new sprite is really the simplest; no reason to
                --  try to do anything more "sophisticated"
                Sprite_kill(ctx.sprite)
                ctx.sprite = spawnSprite(shooter, flying,
                    Phys_pos(Sprite_physics(ctx.sprite)), Vector2(0, -1))
                ctx.phase1 = false
                -- and this makes the sheep controllable; hardcoded in D
                ctx.control = ControlRotate_ctor(ctx.sprite, 5, 10000)
            else
                spriteExplode(ctx.sprite, 75)
            end
        end
        return true
    end

    enableSpriteTimer(flying, {
        defTimer = time("15s"),
        showDisplay = true,
        callback = dorefire,
    })

    addSpriteClassEvent(flying, "sprite_waterstate", function(sender)
        local inwater = Sprite_isUnderWater(sender)
        if not is_aqua then
            if inwater then
                cleanup(sender)
                dodrown(sender)
            end
            return
        end
        setSpriteState(sender, iif(inwater, state_water, state_air))
    end)

    addSpriteClassEvent(flying, "sprite_die", function(sender)
        cleanup(sender)
    end)

    addSpriteClassEvent(jumping, "sprite_waterstate", function(sender)
        if Sprite_isUnderWater(sender) then
            cleanup(sender)
        end
    end)

    enableSpriteTimer(jumping, {
        defTimer = time("10s"),
        showDisplay = true,
        callback = function(sender)
            spriteExplode(sender, 75)
            cleanup(sender)
        end
    })

    local w = createWeapon {
        name = name,
        onFire = function(shooter, info)
            Shooter_reduceAmmo(shooter)
            local s = spawnFromFireInfo(jumping, shooter, info)
            local ctx = get_context(shooter)
            ctx.phase1 = true
            ctx.sprite = s
        end,
        onRefire = dorefire,
        canRefire = true,
        -- strange that you need this
        -- e.g. when you hit yourself with your own supersheep
        onInterrupt = cleanup,
        value = 10,
        category = "moving",
        icon = iif(is_aqua, "icon_aquasheep", "icon_supersheep"),
        animation = "weapon_sheep",
        fireMode = {
            direction = "fixed",
            throwStrengthFrom = 40,
            throwStrengthTo = 40,
        }
    }
end

createSuperSheep("supersheep", false)
createSuperSheep("aquasheep", true)
