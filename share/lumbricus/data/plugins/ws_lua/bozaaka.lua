-- this is just a test

function createTestWeapon(name)
    local sprite_class_name = name .. "_sprite"
    local w = LuaWeaponClass_ctor(Gfx, name)
    local function fire(shooter, info)
        -- copied from game.action.spawn (5 = sprite.physics.radius, 2 = spawndist)
        -- eh, and why not use those values directly?
        local dist = (info.shootbyRadius + 5) * 1.5 + 2
        spawnSprite(sprite_class_name, info.pos + info.dir * dist, info.dir * info.strength)
    end
    setProperties(w, {
        onFire = fire,
        category = "fly",
        value = 0,
        animation = "weapon_bazooka",
        icon = Gfx_resource("icon_bazooka"),
        fireMode = {
            direction = "any",
            variableThrowStrength = true,
            strengthMode = "variable",
            throwStrengthFrom = 200,
            throwStrengthTo = 1200,
        }
    })
    Gfx_registerWeapon(w)
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
    enableSpriteCrateBlowup(w, sprite_class)
    Gfx_registerSpriteClass(sprite_class)
    return w
end

-- instead of this, the script should just be loaded at the right time
addGlobalEventHandler("game_init", function(sender)
    -- comment the following line to prevent weapon from being loaded
    createTestWeapon("bozaaka")
end)
