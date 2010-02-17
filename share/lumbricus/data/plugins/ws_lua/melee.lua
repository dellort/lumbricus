-- Melee weapons: somehow affect objects directly before the shooter

do
    local name = "baseball"

    local w = createWeapon {
        name = name,
        onFire = getMeleeImpulseOnFire(7000, 30),
        category = "punch",
        value = 12,
        animation = "weapon_baseball",
        icon = "icon_baseball",
        fireMode = {
            direction = "any",
        }
    }
end

do
    local name = "prod"

    local w = createWeapon {
        name = name,
        onFire = getMeleeImpulseOnFire(1500, 0),
        category = "punch",
        value = 12,
        animation = "weapon_prod",
        icon = "icon_prod",
        fireMode = {
            direction = "fixed",
        }
    }
end

do
    local name = "axe"

    local w = createWeapon {
        name = name,
        onFire = getMeleeOnFire(10, 15, function(shooter, info, self, obj)
            local spr = Phys_backlink(obj)
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
end
