-- Weapons that spawn moving/jumping/controlled projectiles that collect crates

local function enableSheepJumping(sprite_class)
    -- start walking on spawn
    enableWalking(sprite_class)
    -- jump in random intervals
    enableSpriteTimer(sprite_class, {
        defTimer = time(0.2),
        periodic = true,
        --timerId = "jump",
        callback = function(sender)
            local phys = Sprite_physics(sender)
            if not Phys_isGlued(phys) then
                return
            end
            if Random_rangei(1, 5) == 1 then
                local look = lookSide(phys)
                Phys_addImpulse(phys, Vector2(look * 2500, -2500))
                emitSpriteParticle("p_sheep", sender)
            end
        end
    })
end

-- Enable a basic refire for sprite_class; returns doFire, doRefire
-- Will blow after failsafeTime or when spacebar is pressed and 
--   execute blowFunc
-- Remember to set canRefire = true
-- xxx is this generic enough to move to gameutils.lua?
local function enableBasicRefire(sprite_class, failsafeTime, blowFunc)
    failsafeTime = failsafeTime or time(8)
    assert(blowFunc)

    -- call Shooter_finished when the main sprite dies (if applicable)
    local function cleanup(sprite)
        local shooter = gameObjectFindShooter(sprite)
        if not GameObject_objectAlive(shooter) then
            return
        end
        Shooter_finished(shooter)
    end

    -- die after failsafeTime (the games must go on)
    enableSpriteTimer(sprite_class, {
        defTimer = failsafeTime,
        showDisplay = true,
        callback = blowFunc
    })

    -- cleanup
    addSpriteClassEvent(sprite_class, "sprite_die", function(sender)
        -- don't cleanup twice
        if not Sprite_isUnderWater(sender) then
            cleanup(sender)
        end
    end)
    addSpriteClassEvent(sprite_class, "sprite_waterstate", function(sender)
        cleanup(sender)
    end)

    local function doFire(shooter, fireinfo)
        Shooter_reduceAmmo(shooter)
        local spr = spawnFromFireInfo(sprite_class, shooter, fireinfo)
        set_context_var(shooter, "sprite", spr)
    end
    local function doRefire(shooter)
        local sprite = get_context_var(shooter, "sprite")
        blowFunc(sprite)
        return true
    end
    
    return doFire, doRefire
end

do
    local name = "sheep"
    local function createSprite(name)
        return createSpriteClass {
            name = "x_" .. name,
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
    
    local doFire, doRefire = enableBasicRefire(sprite_class, time(8), function(sprite)
        spriteExplode(sprite, 75)
    end)

    local w = createWeapon {
        name = "w_" .. name,
        onFire = doFire,
        onRefire = doRefire,
        canRefire = true,
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

    -- used by other weapons (I think)
    cratesheep_class = createSprite("crate" .. name)
    enableExplosionOnImpact(cratesheep_class, 75)

    enableSpriteCrateBlowup(w, cratesheep_class)

    -- sheeplauncher is almost exactly the same, but the sheep spawns with
    --   the "helmet" animation
    local name = "sheeplauncher"
    local w = createWeapon {
        name = "w_" .. name,
        onFire = function(shooter, info)
            doFire(shooter, info)
            Sequence_setState(Sprite_graphic(get_context_var(shooter, "sprite")), seqHelmet)
            emitShooterParticle("p_rocket_fire", shooter)
        end,
        onRefire = doRefire,
        canRefire = true,
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
        name = "x_" .. name,
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
        showDisplay = true,
        callback = function(sender)
            spriteExplode(sender, 75)
        end
    })

    local w = createWeapon {
        name = "w_" .. name,
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
        name = "x_" .. name,
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
        name = "x_" .. name .. "_shard",
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
    
    local doFire, doRefire = enableBasicRefire(main, time(8), function(sprite)
        spriteExplode(sprite, 50)
        spawnCluster(shard, sprite, 5, 350, 450, 50)
    end)

    enableExplosionOnImpact(shard, 60)
    enableWalking(main)

    local w = createWeapon {
        name = "w_" .. name,
        onFire = doFire,
        onRefire = doRefire,
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
        name = "x_" .. name,
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

    local fire, interrupt = getMultispawnOnFire(sprite_class, -1, time(0.6),
        true)
    local w = createWeapon {
        name = "w_" .. name,
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
            paramFrom = 1,
            paramTo = 5,
        }
    }
    enableSpriteCrateBlowup(w, sprite_class)
end



local function createSuperSheep(name, is_aqua)
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
        name = "x_" .. name .. "_jumping",
        initPhysic = relay(table_merge(phys, {
            mass = 10,
            walkingSpeed = 50,
        })),
        sequenceType = "s_sheep",
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
        name = "x_" .. name .. "_flying",
        initPhysic = relay(phys),
        sequenceState = "s_sheep:super_" .. iif(is_aqua, "blue", "red"),
        initParticle = "p_supersheep",
        noDrown = true,
    }

    local explode_power = 75

    -- explode the jumping or flying sheep
    local function explode(ctx)
        local sprite = ctx.sprite
        ctx.sprite = nil
        if sprite and not spriteIsGone(sprite) then
            spriteExplode(sprite, explode_power)
        end
    end

    -- not using enableExplosionOnImpact to make sure ctx.sprite is set nil
    addSpriteClassEvent(flying, "sprite_impact", function(sender)
        local shooter = gameObjectFindShooter(sender)
        local ctx = get_context(shooter, true)
        if ctx then
            explode(ctx)
        else
            spriteExplode(sender, explode_power)
        end
    end)

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

    local cleanup_time = timeRange("1s", "5s")

    -- sender = shooter or sprite spawned by shooter
    local function cleanup(sender)
        local shooter = gameObjectFindShooter(sender)
        local ctx = get_context(shooter, true)
        if not ctx then
            -- Shooter is already dead, no cleanup required
            return
        end
        -- remove control e.g. when it starts drowning
        if ctx.control then
            ControlRotate_kill(ctx.control)
            ctx.control = nil
        end
        Shooter_finished(shooter)
        -- if control was taken, wait some time and then blow it up
        if ctx.sprite then
            addTimer(utils.range_sample(cleanup_time), function()
                explode(ctx)
            end)
        end
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
                emitSpriteParticle("p_supersheep_launch", ctx.sprite)
            else
                explode(ctx)
            end
        end
        return true
    end

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

    enableSpriteTimer(flying, {
        defTimer = time("15s"),
        showDisplay = true,
        callback = dorefire,
    })

    addSpriteClassEvent(jumping, "sprite_waterstate", function(sender)
        if Sprite_isUnderWater(sender) then
            cleanup(sender)
        end
    end)

    enableSpriteTimer(jumping, {
        defTimer = time("10s"),
        showDisplay = true,
        callback = function(sender)
            local shooter = gameObjectFindShooter(sender)
            local ctx = get_context(shooter)
            explode(ctx)
            cleanup(sender)
        end
    })

    local w = createWeapon {
        name = "w_" .. name,
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
