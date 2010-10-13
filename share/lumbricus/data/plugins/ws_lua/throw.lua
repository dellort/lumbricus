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

    -- explode the main sprite
    local function blowmain(sender)
        spriteExplode(sender, 75)
        spawnCluster(shard, sender, 5, 300, 400, 40)
    end
    local function blowshard(sender)
        spriteExplode(sender, 75)
    end

    -- some safeguards to keep the game flowing (8s main, 4s shards)
    enableSpriteTimer(main, {
        showDisplay = true,
        useUserTimer = false,
        defTimer = time(8),
        callback = blowmain
    })
    enableSpriteTimer(shard, {
        showDisplay = false,
        useUserTimer = false,
        defTimer = time(4),
        callback = blowshard
    })

    local function dorefire(shooter)
        local ctx = get_context(shooter)
        assert(ctx)
        if table_empty(ctx.sprites) then
            blowmain(ctx.main)
        else
            assert(ctx.sprites)
            for s, _ in pairs(ctx.sprites) do
                -- spriteExplode will trigger die event, which will remove the
                --  sprite from the array... that's allowed
                if not spriteIsGone(s) then
                    blowshard(s)
                end
            end
        end
        -- signal success???
        return true
    end

    addSpriteClassEvent(main, "sprite_waterstate", function(sender)
        if Sprite_isUnderWater(sender) then
            local shooter = gameObjectFindShooter(sender)
            -- no need for a finished call then
            if not GameObject_objectAlive(shooter) then
                return
            end
            Shooter_finished(shooter)
        end
    end)

    local function subsprite_status(sprite, status)
        local shooter = gameObjectFindShooter(sprite)
        assert(shooter)
        -- no need for a finished call then
        if not GameObject_objectAlive(shooter) then
            return
        end
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
        -- if unterwater, event below has been called before; don't call again
        -- (else there may be weird corner cases where the calls from 2
        --  subsequent fires overlap and cause mayhem)
        if not Sprite_isUnderWater(sender) then
            subsprite_status(sender, nil)
        end
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
            ctx.main = spawnFromFireInfo(main, shooter, info)
            emitShooterParticle("p_throw_fire", shooter)
        end,
        onRefire = dorefire,
        category = "throw",
        value = 10,
        animation = "weapon_banana",
        icon = "icon_superbanana",
        fireMode = {
            direction = "any",
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
            throwStrengthFrom = 20,
            throwStrengthTo = 1200,
        }
    }
    enableSpriteCrateBlowup(w, sprite_class)
    holygrenade_class = sprite_class
end

do
    local name = "tunnelbomb"
    local sprite_class = createSpriteClass {
        name = "x_" .. name,
        initPhysic = relay {
            collisionID = "projectile",
            mass = "10",
            radius = "2",
            explosionInfluence = "0",
            windInfluence = "0.0",
            elasticity = "0.1",
            rotation = "distance",
        },
        -- xxx draw something
        sequenceType = "s_grenade",
    }

    local down_count = 8
    local side_count = 7
    local down_damage = 15
    local side_damage = 25
    local main_damage = 25

    enableSpriteTimer(sprite_class, {
        defTimer = timeSecs(3),
        useUserTimer = true,
        showDisplay = true,
        callback = function(sprite)
            local tmain = addPeriodicTimer(time(0.25), function(tmain)
                if Sprite_isUnderWater(sprite) then
                    tmain:cancel()
                    return
                end
                tmain.count = tmain.count - 1
                spriteExplode(sprite, 10, false)
                local spos = Phys_pos(Sprite_physics(sprite))
                if tmain.count > 0 then
                    -- downwards push
                    spos.y = spos.y + 10
                    Game_explosionAt(spos, down_damage, sprite)
                else
                    -- main explosion, then to the side
                    spriteExplode(sprite, main_damage)
                    local function tunnel(timer2)
                        -- add to x every call and explode
                        timer2.pos.x = timer2.pos.x + timer2.addx
                        Game_explosionAt(timer2.pos, side_damage, sprite)
                        timer2.count = timer2.count - 1
                        if timer2.count <= 0 then
                            timer2:cancel()
                        end
                    end
                    -- one explosion a frame (looks better)
                    local t1 = addPeriodicTimer(Time.Null, tunnel)
                    t1.count = side_count
                    -- right
                    t1.addx = side_damage + 5
                    t1.pos = table_copy(spos)
                    local t2 = addPeriodicTimer(Time.Null, tunnel)
                    t2.count = side_count
                    -- left
                    t2.addx = -side_damage - 5
                    t2.pos = table_copy(spos)
                    tmain:cancel()
                end
            end)
            -- xxx using timer to store state variables
            tmain.count = down_count
        end
    })

    local w = createWeapon {
        name = "w_" .. name,
        onFire = getStandardOnFire(sprite_class, "p_throw_fire"),
        value = 10,
        category = "misc1",
        animation = "weapon_grenade",
        icon = "icon_tunnelbomb",
        crateAmount = 3,
        fireMode = {
            direction = "any",
            throwStrengthFrom = 20,
            throwStrengthTo = 1200,
            paramFrom = 1,
            paramTo = 5,
        }
    }
    enableSpriteCrateBlowup(w, sprite_class)
    tunnelbomb_class = sprite_class
end

