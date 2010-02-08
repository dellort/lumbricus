-- this is just a test

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
    enableDrown(sprite_class)

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
    local name = "nabana"
    local sprite_class = createSpriteClass {
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
        sequenceType = Gfx_resource("s_banana")
    }
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

    local w = createWeapon {
        name = name,
        onFire = function (shooter, info)
            Shooter_reduceAmmo(shooter)
            Shooter_finished(shooter)
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
    }
    enableSpriteCrateBlowup(w, sprite_class, 2)
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
    enableDrown(sprite_class)
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
    enableDrown(sprite_class)
    -- xxx need a better way to "cleanup" stuff like timers
    addSpriteClassEvent(sprite_class, "sprite_waterstate", function(sender)
        local ctx = get_context(sender, true)
        if ctx and ctx.timer and
            (not Sprite_visible(sender) or Sprite_isUnderWater(sender))
        then
            ctx.timer:cancel()
        end
    end)
    -- this is done so that it works when spawned by a crate
    -- xxx probably it's rather stupid this way; need better way
    --  plus I don't even know what should happen if a grenade is spawned by
    --  blowing up a crate (right now it sets the timer to a default)
    addSpriteClassEvent(sprite_class, "sprite_activate", function(sender)
        local ctx = get_context(sender)
        local fi = ctx.fireinfo
        local t
        if fi then
            t = fi.timer
        else
            -- spawned from crate or so
            t = time(3)
        end
        ctx.timer = addTimer(t, function()
            spriteExplode(sender, 50)
        end)
        addCountdownDisplay(sender, ctx.timer, 5, 2)
    end)

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


createWeapon {
    name = "gerdir",
    onCreateSelector = function(sprite)
        return GirderControl_ctor(sprite)
    end,
    onFire = function(shooter, fireinfo)
        local sel = Shooter_selector(shooter)
        if not sel then return end
        if GirderControl_fireCheck(sel, fireinfo, true) then
            Shooter_reduceAmmo(shooter)
        end
        Shooter_finished(shooter)
    end,
    value = 0,
    category = "worker",
    icon = "icon_girder",
    animation = "weapon_helmet",
    crateAmount = 3,
    fireMode = {
        point = "instant",
    }
}

createWeapon {
    name = "baemer",
    value = 0,
    category = "tools",
    icon = "icon_beamer",
    dontEndRound = true,
    deselectAfterFire = true,
    fireMode = {
        point = "instantFree"
    },
    animation = "weapon_beamer",
    onFire = function(shooter, fireinfo)
        -- note there were some more checks in weaponactions.d/beam():
        --  - position nan check (?)
        --  - check if it's really a worm (but we need to change that anyway,
        --    the player shouldn't be required to be a WormSprite)
        -- also:
        --  - BeamHandler is missing (aborting the beaming on interruption)
        --  - pointto is a WeaponTarget, which has a currentPos() method
        --    we just use .pos here, which is wrong
        Shooter_reduceAmmo(shooter)
        Shooter_finished(shooter) -- probably called by BeamHandler on the end?
        Worm_beamTo(Shooter_owner(shooter), fireinfo.pointto.pos)
    end
}
