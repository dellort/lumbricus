-- Melee weapons: somehow affect objects directly before the shooter

createWeapon {
    name = "w_baseball",
    onFire = getMeleeImpulseOnFire(7000, 30),
    category = "punch",
    value = 12,
    animation = "weapon_baseball",
    icon = "icon_baseball",
    fireMode = {
        direction = "any",
    }
}

createWeapon {
    name = "w_prod",
    onFire = getMeleeImpulseOnFire(1500, 0),
    category = "punch",
    value = 12,
    animation = "weapon_prod",
    icon = "icon_prod",
    fireMode = {
        direction = "fixed",
    }
}

createWeapon {
    name = "w_axe",
    onFire = getMeleeOnFire(10, 15, function(shooter, info, self, obj)
        local spr = Phys_backlink(obj)
        -- xxx see init.lua comments for a similar thing
        if className(spr) == "WormSprite" then
            -- half lifepower, but don't reduce to less than 1 hp
            local hp = Phys_lifepower(obj)
            local dmg = math.min(hp * 0.5, hp - 1)
            dmg = math.max(dmg, 0)
            Phys_applyDamage(obj, dmg, 3, self)
            Phys_addImpulse(obj, Vector2(0, 1))
        else
            -- destroy barrels
            Phys_applyDamage(obj, 50, 3, self)
        end
    end),
    category = "punch",
    value = 12,
    animation = "weapon_axe",
    icon = "icon_axe",
    fireMode = {
        direction = "fixed",
    }
}

