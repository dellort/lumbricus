-- Gun weapons: direct effect at the first collision of a straight line

local function createGun(params)
    local fire, interrupt, readjust = getGunOnFire(pick(params, "nrounds"),
        pick(params, "interval"), pick(params, "damage"),
        pick(params, "effect"), pick(params, "spread", nil))
    createWeapon {
        name = pick(params, "name"),
        onFire = fire,
        onInterrupt = interrupt,
        onReadjust = readjust,
        category = "shoot",
        value = pick(params, "value", 0),
        animation = pick(params, "animation"),
        icon = pick(params, "icon"),
        prepareParticle = pick(params, "prepareParticle"),
        fireParticle = pick(params, "fireParticle"),
        fireMode = {
            direction = "any",
        },
    }
    assert(table_empty(params), utils.format("unused values: {}", params))
end

createGun {
    name = "w_minigun",
    value = 10,
    animation = "weapon_minigun",
    icon = "icon_minigun",
    fireParticle = "p_minigun_fire",
    nrounds = 50,
    interval = time(0.05),
    damage = 5,
    spread = 15,
}

createGun {
    name = "w_pistol",
    value = 10,
    animation = "weapon_pistol",
    icon = "icon_pistol",
    nrounds = 5,
    interval = time(0.4),
    damage = 7,
    spread = 5,
    effect = function(pos, hit)
        emitParticle("p_pistol_fire", pos)
    end,
}

createGun {
    name = "w_uzi",
    value = 10,
    animation = "weapon_uzi",
    icon = "icon_uzi",
    fireParticle = "p_uzi_fire",
    nrounds = 15,
    interval = time(0.15),
    damage = 5,
    spread = 8,
}

createGun {
    name = "w_laser",
    value = 12,
    animation = "weapon_sheeplauncher",
    icon = "icon_shotgun",
    nrounds = 4,
    interval = time(0.1),
    damage = 10,
    effect = getLaserEffect(time("200ms")),
}

-- shotgun is special because it has refire-handling
do
    local name = "w_shotgun"

    local function doshot(shooter)
        emitShooterParticle("p_shotgun_fire", shooter)
        local ctx = get_context(shooter)
        ctx.shots = ctx.shots - 1
        -- (gives readjusted fireinfo after 1st shot)
        local fireinfo = Shooter_fireinfo(shooter)
        -- copy & pasted from elsewhere
        local hitpoint, normal = castFireRay(Shooter_owner(shooter),
            fireinfo.dir)
        if normal then
            Game_explosionAt(hitpoint, 25, shooter)
        end
        if ctx.shots <= 0 then
            Shooter_finished(shooter)
        end
    end

    local w = createWeapon {
        name = name,
        onFire = function(shooter, fireinfo)
            LuaShooter_setFixed(shooter, true, false)
            Shooter_reduceAmmo(shooter)
            set_context_var(shooter, "shots", 2)
            doshot(shooter)
        end,
        onRefire = function(shooter)
            doshot(shooter)
            return true -- apparently I needed this
        end,
        onInterrupt = function(shooter)
            Shooter_finished(shooter)
        end,
        category = "shoot",
        value = 10,
        animation = "weapon_shotgun",
        icon = "icon_shotgun",
        prepareParticle = "p_shotgun_reload",
        fireMode = {
            direction = "any",
        }
    }
end
