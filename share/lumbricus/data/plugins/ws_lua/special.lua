-- Dumping ground for weapons that don't fit anywhere else

do
    local name = "flamethrower"

    local fire, interrupt, readjust = getMultipleOnFire(50, timeMsecs(60), nil,
        function(shooter, fireinfo)
            -- from: spawnFromFireInfo, castFireRay, flamethrower.conf
            local spread = 7
            local a = Random_rangef(-spread/2, spread/2)
            dir = fireinfo.dir:rotated(a*math.pi/180)
            -- the problem in correctly placing is, that the napalm is centered
            --  in the middle of its position; plus we don't even know which
            --  graphic is going to be used (depends from napalm speed etc.)
            -- solutions:
            --  1. change napalm graphics; napalm position points to the
            --     beginning of the graphic, instead of the center
            --  2. guess (done here)
            local dist = (fireinfo.shootbyRadius + 5) * 1.5 + 9 + 8
            local s = spawnSprite(shooter, worms_shared.standard_napalm,
                fireinfo.pos + dir * dist, dir * 500)
        end
    )
    local w = createWeapon {
        name = name,
        onFire = fire,
        onInterrupt = interrupt,
        onReadjust = readjust,
        category = "misc2",
        value = 10,
        animation = "weapon_flamethrower",
        icon = "icon_flamer",
        fireMode = {
            direction = "any",
            --throwStrengthFrom = 500,
            --throwStrengthTo = 500,
        }
    }
end

do
    local name = "molotov"
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
        spawnCluster(worms_shared.sticky_napalm, sender, 40, 0, 0, 60)
        spriteExplode(sender, 20)
    end)

    local w = createWeapon {
        name = name,
        onFire = getStandardOnFire(sprite_class),
        value = 10,
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

do
    local name = "penguin"
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
        Sprite_kill(sender)
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
        value = 100,
        animation = "weapon_airstrike",
        icon = "icon_penguin",
        fireMode = {
            point = "instant"
        }
    }
end

do
    local name = "mbbomb"
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
        value = 10000,
        animation = "weapon_airstrike",
        icon = "icon_mbbomb",
        fireMode = {
            point = "instant"
        }
    }
end

do
    local name = "esel"
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
            Sprite_kill(sender)
        end
    })
    addSpriteClassEvent(sprite_class, "sprite_activate", function(sender)
        local trig = StuckTrigger_ctor(sender, time(0.25), 2, true);
        StuckTrigger_set_onTrigger(trig, function(sender, sprite)
            Sprite_kill(sender)
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
        value = 10000,
        animation = "weapon_airstrike",
        icon = "icon_esel",
        fireMode = {
            point = "instant"
        }
    }
    enableSpriteCrateBlowup(w, sprite_class)
end

do -- requires s_antimatter_nuke and s_blackhole_active (+graphics) defined in old set
    local name = "blackhole_bomb"
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
            Sprite_kill(sender)
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
        value = 10,
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

do
    local name = "armageddon"
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
            local timer1 = Timer.New()
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
                timer1:start(utils.range_sample(spawn_time))
            end)
            timer1:start(Time.Null)
            -- timer to terminate the armageddon
            addTimer(time("15s"), function()
                timer1:cancel()
            end)
        end,
        isAirstrike = true,
        category = "misc3",
        value = 10000,
        animation = "weapon_atomtest",
        icon = "icon_meteorstrike",
        cooldown = time("15s"),
    }
end

createWeapon {
    name = "atomtest",
    value = 10000,
    category = "misc3",
    cooldown = time("5s"),
    icon = "icon_indiannuke",
    animation = "weapon_atomtest",
    onFire = function(shooter, fireinfo)
        Shooter_reduceAmmo(shooter)
        Shooter_finished(shooter)
        Game_raiseWater(60)
        Game_addEarthQuake(500, time(4))
        Game_nukeSplatEffect()
    end,
    onBlowup = function(weapon)
        Game_addEarthQuake(150, time(4))
    end,
}

createWeapon {
    name = "earthquake",
    value = 10000,
    category = "misc3",
    cooldown = time("5s"),
    icon = "icon_earthquake",
    animation = "weapon_atomtest",
    onFire = function(shooter, fireinfo)
        Shooter_reduceAmmo(shooter)
        Shooter_finished(shooter)
        Game_addEarthQuake(500, time(5), true, true)
    end,
    onBlowup = function(weapon)
        Game_addEarthQuake(150, time(5))
    end,
}
