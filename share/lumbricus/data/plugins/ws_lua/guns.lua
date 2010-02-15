-- Gun weapons: direct effect at the first collision of a straight line

do
    local name = "maxigun"

    -- spread = "15"
    local fire, interrupt, readjust = getGunOnFire(50, time(0.05), 5)
    local w = createWeapon {
        name = name,
        onFire = fire,
        onInterrupt = interrupt,
        onReadjust = readjust,
        category = "shoot",
        value = 0,
        animation = "weapon_minigun",
        icon = "icon_minigun",
        fireMode = {
            direction = "any",
        }
    }
end

do
    local name = "revolver"

    -- spread = "5"
    local fire, interrupt, readjust = getGunOnFire(5, time(0.4), 7)
    local w = createWeapon {
        name = name,
        onFire = fire,
        onInterrupt = interrupt,
        onReadjust = readjust,
        category = "shoot",
        value = 0,
        animation = "weapon_pistol",
        icon = "icon_pistol",
        fireMode = {
            direction = "any",
        }
    }
end

do
    local name = "smg"

    -- spread = "8"
    local fire, interrupt, readjust = getGunOnFire(15, time(0.15), 5)
    local w = createWeapon {
        name = name,
        onFire = fire,
        onInterrupt = interrupt,
        onReadjust = readjust,
        category = "shoot",
        value = 0,
        animation = "weapon_uzi",
        icon = "icon_uzi",
        fireMode = {
            direction = "any",
        }
    }
end

do
    local name = "lesar"

    -- spread = "0"
    local fire, interrupt, readjust = getGunOnFire(4, time(0.1), 10,
        getLaserEffect(time("200ms")))
    local w = createWeapon {
        name = name,
        onFire = fire,
        onInterrupt = interrupt,
        onReadjust = readjust,
        category = "shoot",
        value = 0,
        animation = "weapon_sheeplauncher",
        icon = "icon_shotgun",
        fireMode = {
            direction = "any",
        }
    }
end

