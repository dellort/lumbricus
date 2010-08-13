-- Weapons like grenades (thrown, explode after timer / on spacebar)

do
    local name = "banana"
    local function createSprite(sname)
        return createSpriteClass {
            name = "x_" .. name .. "_" .. sname,
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
    local main = createSprite("main")
    local shard = createSprite("shard")

    enableExplosionOnImpact(shard, 75)
    enableSpriteTimer(main, {
        showDisplay = true,
        callback = function(sender)
            spriteExplode(sender, 75)
            spawnCluster(shard, sender, 6, 400, 600, 30)
        end
    })

    local w = createWeapon {
        name = "w_" .. name,
        onFire = getStandardOnFire(main, "p_throw_fire"),
        category = "throw",
        value = 10,
        animation = "weapon_banana",
        icon = "icon_banana",
        fireMode = {
            direction = "any",
            variableThrowStrength = true,
            throwStrengthFrom = 20,
            throwStrengthTo = 1200,
            paramFrom = 1,
            paramTo = 5,
        }
    }
    enableSpriteCrateBlowup(w, shard, 2)
    -- for superbanana
    bananashard_class = shard
end

do
    local name = "superbanana"
    local function createSprite(sname)
        return createSpriteClass {
            name = "x_" .. name .. "_" .. sname,
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
    local main = createSprite("main")
    local shard = createSprite("shard")

    local function dorefire(shooter)
        local ctx = get_context(shooter)
        assert(ctx)
        local timer = ctx.timer
        timer:cancel()
        if ctx.phase1 then
            -- explode the main sprite
            spriteExplode(ctx.main, 75)
            spawnCluster(shard, ctx.main, 5, 300, 400, 40)
            -- after that time, let shards explode in phase 1
            ctx.timer:start(time(4))
            ctx.phase1 = false
        else
            assert(ctx.sprites)
            for s, _ in pairs(ctx.sprites) do
                -- spriteExplode will trigger die event, which will remove the
                --  sprite from the array... that's allowed
                if not spriteIsGone(s) then
                    spriteExplode(s, 75)
                end
            end
        end
        -- signal success???
        return true
    end

    addSpriteClassEvent(main, "sprite_waterstate", function(sender)
        if Sprite_isUnderWater(sender) then
            local shooter = gameObjectFindShooter(sender)
            get_context(shooter).timer:cancel()
            Shooter_finished(shooter)
        end
    end)

    local function subsprite_status(sprite, status)
        local shooter = gameObjectFindShooter(sprite)
        assert(shooter)
        local sprites = get_context(shooter).sprites
        sprites[sprite] = status
        -- reconsider refire status; no sprites left => no refire
        if (not status) and table_empty(sprites) then
            Shooter_finished(shooter)
        end
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
        subsprite_status(sender, true)
    end)
    addSpriteClassEvent(shard, "sprite_die", function(sender)
        subsprite_status(sender, nil)
    end)
    addSpriteClassEvent(shard, "sprite_waterstate", function(sender)
        if Sprite_isUnderWater(sender) then
            subsprite_status(sender, nil)
        end
    end)

    local w = createWeapon {
        name = "w_" .. name,
        onFire = function(shooter, info)
            Shooter_reduceAmmo(shooter)
            --Shooter_finished(shooter)
            local ctx = get_context(shooter)
            ctx.sprites = {}
            ctx.phase1 = true
            ctx.timer = addTimer(time(8), function()
                dorefire(shooter)
            end)
            ctx.main = spawnFromFireInfo(main, shooter, info)
            addCountdownDisplay(ctx.main, ctx.timer, 5, 2)
            emitShooterParticle("p_throw_fire", shooter)
        end,
        onRefire = dorefire,
        canRefire = true,
        category = "throw",
        value = 10,
        animation = "weapon_banana",
        icon = "icon_superbanana",
        fireMode = {
            direction = "any",
            variableThrowStrength = true,
            throwStrengthFrom = 20,
            throwStrengthTo = 1200,
        }
    }
    enableSpriteCrateBlowup(w, bananashard_class, 2)
end

do
    local name = "grenade"
    local sprite_class = createSpriteClass {
        name = "x_" .. name,
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
        name = "w_" .. name,
        onFire = getStandardOnFire(sprite_class, "p_throw_fire"),
        value = 10,
        category = "throw",
        animation = "weapon_grenade",
        icon = "icon_grenade",
        crateAmount = 3,
        fireMode = {
            direction = "any",
            variableThrowStrength = true,
            throwStrengthFrom = 20,
            throwStrengthTo = 1200,
            paramFrom = 1,
            paramTo = 5,
        }
    }
    enableSpriteCrateBlowup(w, sprite_class)
    grenade_class = sprite_class
end

do
    local name = "clusterbomb"
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
        name = "x_" .. name .. "_cluster",
        sequenceType = "s_cluster",
        initPhysic = phys,
    }
    local shard = createSpriteClass {
        name = "x_" .. name .. "_shard",
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
        name = "w_" .. name,
        onFire = getStandardOnFire(main, "p_throw_fire"),
        value = 10,
        category = "throw",
        icon = "icon_cluster",
        crateAmount = 3,
        animation = "weapon_cluster",
        fireMode = {
            direction = "any",
            variableThrowStrength = true,
            throwStrengthFrom = 20,
            throwStrengthTo = 1200,
            paramFrom = 1,
            paramTo = 5,
        }
    }
    enableSpriteCrateBlowup(w, shard, 5)
    clusterbomb_class = main
end

do
    local name = "holy_grenade"
    local sprite_class = createSpriteClass {
        name = "x_" .. name,
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
        name = "w_" .. name,
        onFire = getStandardOnFire(sprite_class, "p_throw_fire"),
        category = "throw",
        value = 10,
        animation = "weapon_holy",
        icon = "icon_holy",
        fireMode = {
            direction = "any",
            variableThrowStrength = true,
            throwStrengthFrom = 20,
            throwStrengthTo = 1200,
        }
    }
    enableSpriteCrateBlowup(w, sprite_class)
    holygrenade_class = sprite_class
end

