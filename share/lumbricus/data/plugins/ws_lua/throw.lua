-- Weapons like grenades (thrown, explode after timer / on spacebar)

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

