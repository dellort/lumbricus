-- this is just a test

function createWeapon(name, props)
    local w = LuaWeaponClass_ctor(Gfx, name)
    setProperties(w, props)
    Gfx_registerWeapon(w)
    return w
end

do
    local name = "bozaaka"
    local sprite_class_name = name .. "_sprite"
    local sprite_class = SpriteClass_ctor(Gfx, sprite_class_name)
    setProperties(sprite_class, {
        initPhysic = relay {
            collisionID = "projectile",
            mass = 10, -- 10 whatevertheffffunitthisis
            radius = 2,
            explosionInfluence = 0,
            windInfluence = 1.0,
            elasticity = 0.4,
        },
        sequenceType = Gfx_resource("s_bazooka"),
        initParticle = Gfx_resource("p_rocket")
    })
    enableExplosionOnImpact(sprite_class, 50)
    enableDrown(sprite_class)

    Gfx_registerSpriteClass(sprite_class)
    local w = createWeapon(name, {
        onFire = getStandardOnFire(sprite_class),
        category = "fly",
        value = 0,
        animation = "weapon_bazooka",
        icon = Gfx_resource("icon_bazooka"),
        fireMode = {
            direction = "any",
            variableThrowStrength = true,
            throwStrengthFrom = 200,
            throwStrengthTo = 1200,
        }
    })
    enableSpriteCrateBlowup(w, sprite_class)
end

do
    local name = "nabana"
    local sprite_class_name = name .. "_sprite"
    local sprite_class = SpriteClass_ctor(Gfx, sprite_class_name)
    setProperties(sprite_class, {
        initPhysic = relay {
            collisionID = "projectile",
            mass = 10, -- 10 whatevertheffffunitthisis
            radius = 2,
            explosionInfluence = 0,
            windInfluence = 0,
            elasticity = 0.4,
            rotation = "distance"
        },
        sequenceType = Gfx_resource("s_banana")
    })
    addSpriteClassEvent(sprite_class, "sprite_impact", function(sender)
        local ctx = get_context(sender, true)
        if ctx and ctx.main then
            return
        end
        Sprite_die(sender)
        Game_explosionAt(Phys_pos(Sprite_physics(sender)), 75, sender)
    end)
    enableDrown(sprite_class)
    -- disable blow-up timer on drown (prevent blowup, remove time display)
    addSpriteClassEvent(sprite_class, "sprite_waterstate", function(sender)
        local ctx = get_context(sender, true)
        if ctx and ctx.timer and
            (not Sprite_visible(sender) or Sprite_isUnderWater(sender))
        then
            ctx.timer:cancel()
        end
    end)

    Gfx_registerSpriteClass(sprite_class)
    local w = createWeapon(name, {
        onFire = function (shooter, info)
            local s = spawnFromFireInfo(sprite_class, info)
            local ctx = get_context(s)
            ctx.main = true
            ctx.timer = addTimer(info.timer, function()
                local spos = Phys_pos(Sprite_physics(s))
                Game_explosionAt(spos, 75, s)
                for i = 1,6 do
                    local strength = Random_rangei(400, 600)
                    local theta = (Random_rangef(-0.5, 0.5)*30 - 90) * math.pi/180
                    local dir = Vector2.FromPolar(strength, theta)
                    spawnSprite(sprite_class, spos, dir)
                end
                Sprite_die(s)
            end)
            addCountdownDisplay(s, ctx.timer, 5, 2)
        end,
        category = "throw",
        value = 0,
        animation = "weapon_banana",
        icon = Gfx_resource("icon_banana"),
        fireMode = {
            direction = "any",
            variableThrowStrength = true,
            throwStrengthFrom = 200,
            throwStrengthTo = 1200,
            timerFrom = timeSecs(1),
            timerTo = timeSecs(5),
        }
    })
    enableSpriteCrateBlowup(w, sprite_class, 2)
end

do
    local name = "unholy_granade"
    local sprite_class_name = name .. "_sprite"
    local sprite_class = SpriteClass_ctor(Gfx, sprite_class_name)
    setProperties(sprite_class, {
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
        sequenceType = Gfx_resource("s_holy"),
        initParticle = Gfx_resource("p_holy")
    })
    enableDrown(sprite_class)
    enableOnTimedGlue(sprite_class, timeSecs(2), function(sender)
        spriteExplode(sender, 75)
    end)

    Gfx_registerSpriteClass(sprite_class)
    local w = createWeapon(name, {
        onFire = getStandardOnFire(sprite_class),
        category = "throw",
        value = 0,
        animation = "weapon_holy",
        icon = Gfx_resource("icon_holy"),
        fireMode = {
            direction = "any",
            variableThrowStrength = true,
            throwStrengthFrom = 20,
            throwStrengthTo = 1200,
            relaxtime = timeSecs(1)
        }
    })
    enableSpriteCrateBlowup(w, sprite_class)
end
