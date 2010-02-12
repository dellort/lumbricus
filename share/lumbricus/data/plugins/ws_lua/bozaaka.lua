-- this is just a test

-- xxx old stuff
local napalm = Gfx_findSpriteClass("molotov_napalm")
local mine = Gfx_findSpriteClass("mine")

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
    local name = "flemathrower"

    local w = createWeapon {
        name = name,
        onFire = function(shooter, fireinfo)
            local worm = Shooter_owner(shooter)
            Shooter_reduceAmmo(shooter)
            local remains = 50
            local timer = Timer.new()
            set_context_val(shooter, "timer", timer)
            timer:setCallback(function()
                -- only one sprite per timer tick...
                -- xxx this function is bad:
                --  1. sets a context per napalm sprite (for fireinfo)
                --  2. doesn't spawn like the .conf flamethrower
                spawnFromFireInfo(napalm, fireinfo)
                remains = remains - 1
                if remains <= 0 then
                    timer:cancel()
                    Shooter_finished(shooter)
                end
            end)
            timer:start(timeMsecs(60), true)
        end,
        onInterrupt = function(shooter, outOfAmmo)
            -- xxx somehow this never gets called
            local timer = get_context_val(shooter, "timer")
            if timer then
                timer:cancel()
            end
        end,
        category = "misc2",
        value = 0,
        animation = "weapon_flamethrower",
        icon = "icon_flamer",
        fireMode = {
            direction = "any",
            throwStrengthFrom = 500,
            throwStrengthTo = 500,
        }
    }
end

do
    local name = "nabana"
    local function createSprite(name)
        return createSpriteClass {
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
    local name = "mingvesa"
    local main = createSpriteClass {
        name = name .. "_sprite",
        sequenceType = "s_mingvase",
        initPhysic = relay {
            collisionID = "projectile",
            mass = 10,
            radius = 2,
            explosionInfluence = 0,
            windInfluence = 0.0,
            elasticity = 0.0,
            glueForce = "500",
        }
    }
    local shard = createSpriteClass {
        name = name .. "_shard",
        initPhysic = relay {
            collisionID = "projectile",
            mass = 10,
            radius = 2,
            explosionInfluence = 0,
            windInfluence = 0.0,
            elasticity = 0.4,
            rotation = "distance",
        }
    }

    enableExplosionOnImpact(shard, 60)
    enableSpriteTimer(main, {
        showDisplay = false,
        defTimer = time("5 s"),
        callback = function(sender)
            spriteExplode(sender, 50)
            spawnCluster(shard, sender, 5, 300, 400, 50)
        end
    })

    -- the following code is for selecting a random graphic on sprite spawn
    -- it's a bit hacky, and doesn't handle the case when a sprite goes back
    --  from water to non-water (but enableDrown doesn't either)
    -- also note: enableDrown won't set a graphic, because the class doesn't
    --  have an init graphic (SpriteClass.sequenceType is null)
    local seqs = {"s_mingshard1", "s_mingshard2", "s_mingshard3"}
    local seq_states = {}
    local seq_to_drown = {}
    for i, v in ipairs(seqs) do
        local seq = Gfx_resource(v)
        local state = SequenceType_findState(seq, "normal")
        seq_states[i] = state
        seq_to_drown[state] = SequenceType_findState(seq, "drown")
    end
    addSpriteClassEvent(shard, "sprite_activate", function(sender, normal)
        Sequence_setState(Sprite_graphic(sender),
            seq_states[Random_rangei(1, #seq_states)])
    end)
    addSpriteClassEvent(shard, "sprite_waterstate", function(sender)
        local gr = Sprite_graphic(sender)
        if Sprite_isUnderWater(sender) and gr then
            local n = seq_to_drown[Sequence_currentState(gr)]
            if n then
                Sequence_setState(gr, n)
            end
        end
    end)

    local w = createWeapon {
        name = name,
        onFire = getStandardOnFire(main),
        value = 0,
        category = "sheep",
        icon = "icon_mingvase",
        animation = "weapon_mingvase",
        fireMode = {
            direction = "fixed",
            variableThrowStrength = true,
            throwStrengthFrom = 40,
            throwStrengthTo = 40,
        }
    }
    enableSpriteCrateBlowup(w, shard, 2)
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
        onFire = getAirstrikeOnFire(mine, 10, 25),
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
    enableSpriteCrateBlowup(w, sprite_class, 5)
end

do -- depends from napalm
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
            spawnCluster(napalm, sender, 15, 1, 1, 60, vel)
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
    addSpriteClassEvent(sprite_class, "sprite_impact", function(sender)
        spriteExplode(sender, 40, false)
        -- change 3rd param for number of bounces
        local bounce = get_context_val(sender, "bounce", 3)
        if bounce <= 0 then
            Sprite_die(sender)
        end
        set_context_val(sender, "bounce", bounce - 1)
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
    local name = "pinguen"
    local sprite_class = createSpriteClass {
        name = name .. "_sprite",
        initPhysic = relay {
            collisionID = "projectile",
            mass = 200,
            radius = 70,
            explosionInfluence = 0,
            windInfluence = 0,
            elasticity = 0.8,
            fixate = Vector2(0, 1)
        },
        sequenceType = "s_penguin",
    }
    local bmp = Gfx_resource("penguin_bmp")
    addSpriteClassEvent(sprite_class, "sprite_impact", function(sender)
        Sprite_die(sender)
        local at = Phys_pos(Sprite_physics(sender))
        at = at - Surface_size(bmp) / 2
        Game_insertIntoLandscape(at, bmp, Lexel_soft)
        Game_addEarthQuake(500, time(1))
    end)

    local w = createWeapon {
        name = name,
        onFire = getAirstrikeOnFire(sprite_class, 1),
        isAirstrike = true,
        category = "misc1",
        value = 0,
        animation = "weapon_airstrike",
        icon = "icon_penguin",
        fireMode = {
            point = "instant"
        }
    }
end

do
    local name = "bmbomb"
    local sprite_class = createSpriteClass {
        name = name .. "_sprite",
        initPhysic = relay {
            collisionID = "projectile",
            mass = 2,
            radius = 25,
            explosionInfluence = 0,
            windInfluence = -0.3,
            airResistance = 0.03,
        },
        sequenceType = "s_mbbomb",
        initParticle = "p_mbbomb",
    }
    enableExplosionOnImpact(sprite_class, 75)

    local w = createWeapon {
        name = name,
        onFire = getAirstrikeOnFire(sprite_class, 1),
        isAirstrike = true,
        category = "misc3",
        value = 0,
        animation = "weapon_airstrike",
        icon = "icon_mbbomb",
        fireMode = {
            point = "instant"
        }
    }
end
