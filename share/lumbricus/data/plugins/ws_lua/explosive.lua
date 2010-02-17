-- Explosive weapons (dynamite etc.); lay it and run away

do
    local name = "dynamite"
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
        value = 10,
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
    local name = "mingvase"
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
        value = 10,
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
    local name = "mine"
    -- no "local", this is used in other weapons
    mine_class = createSpriteClass {
        -- newgame.conf/levelobjects references this name!
        name = "mine",
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
                    addSpriteTimer(sender, "explodeT", time(1), false,
                        function(sender)
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
        value = 10,
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
