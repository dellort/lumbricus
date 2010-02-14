-- this is just a test

-- napalm which doesn't "stick"
local standard_napalm
do
    local function phys(radius)
        local p = POSP_ctor()
        setProperties(p, {
            collisionID = "napalm",
            mass = 10,
            radius = radius,
            explosionInfluence = 0.8,
            windInfluence = 0.0,
            airResistance = 0.3,
            elasticity = 0.0,
            glueForce = 0,
        })
        return p
    end
    standard_napalm = createSpriteClass {
        name = "standard_napalm",
        ctor = "NapalmSpriteClass_ctor",
        initPhysic = phys(3),
        physMedium = phys(2),
        physSmall = phys(1),
        damage = utils.range(6, 9),
        initialDelay = timeRange("0ms", "500ms"),
        repeatDelay = timeRange("400ms", "600ms"),
        decayTime = timeRange("7s", "10s"),
        lightupVelocity = 400,
        sequenceType = "s_napalm",
        initParticle = "p_napalmsmoke",
        -- hack until we get some generic event system, or whatever
        -- specific to this class
        -- xxx: hey, we have a generic event system... just need extend physic
        --  to get specific "this collides with that" events (right now, it
        --  would require you to register an event handler for all types of
        --  collisions, and do "manual" filtering, which might be S.L.O.W.)
        -- the holy grenade would need something similar
        emitOnWater = Gfx_resource("p_napalmsmoke_short"),
    }
end

-- napalm which "sticks" a while and fades as the game rounds progress
-- xxx implement
local sticky_napalm = standard_napalm

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
            LuaShooter_set_isFixed(shooter, true)
            local remains = 50
            local timer = Timer.new()
            set_context_var(shooter, "timer", timer)
            timer:setCallback(function()
                -- only one sprite per timer tick...
                -- xxx this function is bad:
                --  1. sets a context per napalm sprite (for fireinfo)
                --  2. doesn't spawn like the .conf flamethrower
                spawnFromFireInfo(standard_napalm, shooter, fireinfo)
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
            local timer = get_context_var(shooter, "timer")
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
    -- for superbanana
    bananashard_class = shard
end

do -- xxx missing refire handling; currently just explodes after 3s
    local name = "supernabana"
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

    local function dorefire(shooter)
        local ctx = get_context(shooter)
        assert(ctx)
        local timer = ctx.timer
        timer:cancel()
        if ctx.phase == 0 then
            -- explode the main sprite
            if not spriteIsGone(ctx.main) then
                spriteExplode(ctx.main, 75)
                spawnCluster(shard, ctx.main, 5, 300, 400, 40)
            end
            -- after that time, let shards explode in phase 1
            ctx.timer:start(time(4))
        elseif ctx.phase == 1 then
            Shooter_finished(shooter)
            assert(ctx.sprites)
            for i, s in ipairs(ctx.sprites) do
                if not spriteIsGone(s) then
                    spriteExplode(s, 75)
                end
            end
            ctx.sprites = nil
        end
        ctx.phase = ctx.phase + 1
        -- signal success???
        return true
    end

    addSpriteClassEvent(shard, "sprite_activate", function(sender, normal)
        -- add to "refire" list
        -- that could handled in spawnCluster() (and would be cheaper), but
        --  what if spawnCluster will be implemented in D?
        -- possible solution to avoid maintaining/building a list in Lua:
        --  introduce game object "groups", and all objects spawned by the same
        --  parent belong into the same "group"; you'd be able to iterate the
        --  group members (=> get sprites without creating an array in Lua;
        --  you'd iterate them by calling a Group_next(previous_sprite)
        --  function, so no D->Lua delegate is needed)
        -- this "group" stuff could also be used to simplify memory managment
        --  (e.g. find out when a context shared by spawned sprites can be
        --  free'd; important at least for the Shooter)
        local shooter = gameObjectFindShooter(sender)
        assert(shooter)
        local sprites = get_context(shooter).sprites
        sprites[#sprites + 1] = sender
    end)

    local w = createWeapon {
        name = name,
        onFire = function(shooter, info)
            Shooter_reduceAmmo(shooter)
            --Shooter_finished(shooter)
            local ctx = get_context(shooter)
            ctx.sprites = {}
            ctx.phase = 0
            ctx.timer = addTimer(time(8), function()
                dorefire(shooter)
            end)
            ctx.main = spawnFromFireInfo(main, shooter, info)
            addCountdownDisplay(ctx.main, ctx.timer, 5, 2)
        end,
        onRefire = dorefire,
        canRefire = true,
        category = "throw",
        value = 0,
        animation = "weapon_banana",
        icon = "icon_superbanana",
        fireMode = {
            direction = "any",
            variableThrowStrength = true,
            throwStrengthFrom = 200,
            throwStrengthTo = 1200,
        }
    }
    enableSpriteCrateBlowup(w, bananashard_class, 2)
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
    local name = "mane"
    -- no "local", this is used in other weapons
    mine_class = createSpriteClass {
        name = name .. "_sprite",
        initPhysic = relay {
            collisionID = "projectile",
            mass = 10,
            radius = 2,
            explosionInfluence = 1.0,
            windInfluence = 0.0,
            elasticity = 0.6,
            glueForce = 120,
            rotation = "distance",
        },
        sequenceType = "s_mine",
    }

    local seq = SpriteClass_sequenceType(mine_class)
    assert(seq)
    local flash_graphic = SequenceType_findState(seq, "flashing", true)
    -- timer for initial delay
    enableSpriteTimer(mine_class, {
        defTimer = timeSecs(3),
        callback = function(sender)
            -- mine becomes active
            addCircleTrigger(sender, 45, "wormsensor", function(trig, obj)
                -- worm stepped on
                if flash_graphic then
                    Sequence_setState(Sprite_graphic(sender), flash_graphic)
                    -- blow up after 1s
                    addSpriteTimer(sender, "explodeT", time(1), false, function(sender)
                        spriteExplode(sender, 50)
                    end)
                end
                Phys_kill(trig)
            end)
        end
    })

    local w = createWeapon {
        name = name,
        onFire = getStandardOnFire(mine_class),
        value = 0,
        category = "sheep",
        icon = "icon_mine",
        animation = "weapon_mine",
        fireMode = {
            direction = "fixed",
            throwStrengthFrom = 40,
            throwStrengthTo = 40,
        }
    }
    enableSpriteCrateBlowup(w, mine_class)
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
            spawnCluster(standard_napalm, sender, 15, 1, 1, 60, vel)
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
        spawnCluster(standard_napalm, sender, 10, 0, 0, 60)
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

do
    local name = "lotomov"
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
        sequenceType = "s_molotov",
    }
    addSpriteClassEvent(sprite_class, "sprite_impact", function(sender)
        if spriteIsGone(sender) then
            return
        end
        spawnCluster(sticky_napalm, sender, 40, 0, 0, 60)
        spriteExplode(sender, 20)
    end)

    local w = createWeapon {
        name = name,
        onFire = getStandardOnFire(sprite_class),
        value = 0,
        category = "misc2",
        animation = "weapon_molotov",
        icon = "icon_molotov",
        crateAmount = 2,
        fireMode = {
            direction = "any",
            variableThrowStrength = true,
            throwStrengthFrom = 20,
            throwStrengthTo = 1200,
        }
    }
    enableSpriteCrateBlowup(w, sprite_class)
end

do -- requires s_antimatter_nuke and s_blackhole_active (+graphics) defined in old set
    local name = "whitehole_bomb"
    local nuke = createSpriteClass {
        name = name .. "_sprite",
        initPhysic = relay {
            collisionID = "projectile",
            mass = 10,
            radius = 2,
            explosionInfluence = 0,
            windInfluence = 0,
            elasticity = 0.4,
            glueForce = 20,
            rotation = "distance"
        },
        sequenceType = "s_antimatter_nuke",
    }
    local blackhole = createSpriteClass {
        name = name .. "_sprite2",
        initPhysic = relay {
            collisionID = "projectile",
            mass = 10,
            fixate = Vector2(0, 0),
            radius = 2,
            explosionInfluence = 0,
            windInfluence = 0,
        },
        sequenceType = "s_blackhole_active",
    }

    enableSpriteTimer(nuke, {
        showDisplay = true,
        callback = function(sender)
            spawnSprite(sender, blackhole, Phys_pos(Sprite_physics(sender)),
                Vector2(0, 0))
            Sprite_die(sender)
        end
    })

    addSpriteClassEvent(blackhole, "sprite_activate", function(sender)
        local grav = GravityCenter_ctor(Sprite_physics(sender), 5000, 300)
        World_add(grav)
        set_context_var(sender, "gravcenter", grav)
    end)
    addSpriteClassEvent(blackhole, "sprite_die", function(sender)
        local grav = get_context_var(sender, "gravcenter")
        Phys_kill(grav)
    end)
    enableSpriteTimer(blackhole, {
        defTimer = timeSecs(1.3),
        callback = function(sender)
            spriteExplode(sender, 60)
        end
    })

    local w = createWeapon {
        name = name,
        onFire = getStandardOnFire(nuke),
        category = "misc1",
        value = 0,
        animation = "weapon_holy",
        icon = "icon_blackhole",
        fireMode = {
            direction = "any",
            variableThrowStrength = true,
            throwStrengthFrom = 20,
            throwStrengthTo = 1200,
            timerFrom = time(1),
            timerTo = time(5),
        }
    }
    enableSpriteCrateBlowup(w, blackhole)
end

-- xxx this function is very specific to prod and baseball, so I did not bother
--     moving it to gameutils
-- all worms in radius get an impulse of strength in fire direction, and
--   everything takes some damage
function getMeleeImpulseOnFire(strength, damage)
    return getMeleeOnFire(10, 15, function(shooter, info, self, obj)
        local spr = Phys_backlink(obj)
        if damage > 0 then
            Phys_applyDamage(obj, damage, 3, self)
        end
        -- hm, why only worms? could be funny to baseball away mines
        -- but that's how it was before
        if className(spr) == "WormSprite" then
            Phys_addImpulse(obj, info.dir * strength)
        end
    end)
end

do
    local name = "besabell"

    local w = createWeapon {
        name = name,
        onFire = getMeleeImpulseOnFire(7000, 30),
        category = "punch",
        value = 0,
        animation = "weapon_baseball",
        icon = "icon_baseball",
        fireMode = {
            direction = "any",
        }
    }
end

do
    local name = "drop"

    local w = createWeapon {
        name = name,
        onFire = getMeleeImpulseOnFire(1500, 0),
        category = "punch",
        value = 0,
        animation = "weapon_prod",
        icon = "icon_prod",
        fireMode = {
            direction = "fixed",
        }
    }
end

do
    local name = "hatchet"

    local w = createWeapon {
        name = name,
        onFire = getMeleeOnFire(10, 15, function(shooter, info, self, obj)
            local spr = Phys_backlink(obj)
            if className(spr) == "WormSprite" then
                -- half lifepower, but don't reduce to less than 1 hp
                local hp = Phys_lifepower(obj)
                local dmg = math.min(hp * 0.5, hp - 1)
                dmg = math.max(dmg, 0)
                Phys_applyDamage(obj, dmg, 3, self)
                Phys_addImpulse(obj, Vector2(0, 1))
            else
                -- destroy barrels
                Phys_applyDamage(obj, 50, 3, self)
            end
        end),
        category = "punch",
        value = 0,
        animation = "weapon_axe",
        icon = "icon_axe",
        fireMode = {
            direction = "fixed",
        }
    }
end

do -- xxx missing refire handling and inverse direction when stuck
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
    -- don't live longer than 8s
    enableSpriteTimer(sprite_class, {
        defTimer = time(8),
        showDisplay = true,
        callback = function(sender)
            spriteExplode(sender, 75)
        end
    })

    -- used by other weapons (I think)
    cratesheep_class = createSprite("crate" .. name)
    enableExplosionOnImpact(cratesheep_class, 75)

    local w = createWeapon {
        name = name,
        onFire = getStandardOnFire(sprite_class),
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
end

do
    local name = "armegaddon"
    local sprite_class = createSpriteClass {
        name = name .. "_sprite",
        initPhysic = relay {
            collisionID = "projectile",
            mass = 10,
            radius = 15,
            explosionInfluence = 0,
            windInfluence = 0,
            elasticity = 0.4,
        },
        sequenceType = "s_meteor",
        initParticle = "p_meteor",
    }
    enableExplosionOnImpact(sprite_class, utils.range(40, 75))

    local w = createWeapon {
        name = name,
        onFire = function(shooter, fireinfo)
            Shooter_reduceAmmo(shooter)
            -- xxx can the shooter continue running (for activity) stuff, or
            --  would that somehow block the worm?
            Shooter_finished(shooter)
            -- timer to spawn meteors
            local spawn_time = timeRange("100ms", "200ms")
            -- xxx original params from amrageddon.conf; somehow looks very off
            --local spawn_strength = utils.range(800, 1000)
            local spawn_strength = utils.range(200, 400)
            local timer1 = Timer.new()
            timer1:setCallback(function()
                -- emulate spawnsprite's InitVelocity.randomAir
                -- maybe this should go into D code (memory thrashing)
                local damage = utils.range_sample_f(spawn_strength)
                local bounds = Level_landBounds()
                local pos = Vector2()
                pos.x = Random_rangef(bounds.p1.x, bounds.p2.x)
                pos.y = 0 -- really, 0?
                -- strange calculation, but I'd rather not change this code
                --  could be shortened to use fromPolar(angle, strength)
                local vel = Vector2(Random_rangef(-1, 1)*0.7, 1):normal()
                local strength = utils.range_sample_f(spawn_strength)
                spawnSprite(shooter, sprite_class, pos, vel*strength)
                -- for next meteor
                timer1:start(utils.range_sample_any(spawn_time))
            end)
            timer1:start(Time.Null)
            -- timer to terminate the armageddon
            addTimer(time("15s"), function()
                timer1:cancel()
            end)
        end,
        isAirstrike = true,
        category = "misc3",
        value = 0,
        animation = "weapon_atomtest",
        icon = "icon_meteorstrike",
        cooldown = time("15s"),
    }
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
            local homing = setSpriteHoming(sender, ctx.fireinfo.pointto, 15000,
                15000)
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
    local name = "lese"
    local sprite_class = createSpriteClass {
        name = name .. "_sprite",
        initPhysic = relay {
            collisionID = "weapon",
            mass = 200,
            radius = 70,
            explosionInfluence = 0.0,
            windInfluence = 0.0,
            elasticity = 0.8,
            fixate = Vector2(0, 1),
        },
        sequenceType = "s_esel",
        initParticle = "p_donkey",
    }
    enableSpriteTimer(sprite_class, {
        defTimer = timeSecs(20),
        callback = function(sender)
            Sprite_die(sender)
        end
    })
    addSpriteClassEvent(sprite_class, "sprite_activate", function(sender)
        local trig = StuckTrigger_ctor(sender, time(0.25), 2, true);
        StuckTrigger_set_onTrigger(trig, function(sender, sprite)
            Sprite_die(sender)
        end)
    end)
    addSpriteClassEvent(sprite_class, "sprite_impact", function(sender)
        spriteExplode(sender, 100, false)
    end)

    local w = createWeapon {
        name = name,
        onFire = getAirstrikeOnFire(sprite_class, 1),
        isAirstrike = true,
        category = "misc3",
        value = 0,
        animation = "weapon_airstrike",
        icon = "icon_esel",
        fireMode = {
            point = "instant"
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
            set_context_var(spr, "shooter", shooter)
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
