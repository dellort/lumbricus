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

-- not really a melee weapon as it fires a projectile; but in wwp it's in this category
do
    local name = "dragonball"
    local sprite_class = createSpriteClass {
        name = "x_" .. name,
        initPhysic = relay {
            collisionID = "projectile",
            mass = 10,
            radius = 4,
            explosionInfluence = 0,
            windInfluence = 0,
            zeroGrav = true,
        },
        sequenceType = "s_dragonball",
    }
    enableExplosionOnImpact(sprite_class, 30)
    -- remove after some time
    enableSpriteTimer(sprite_class, {
        defTimer = time(0.8),
        callback = function(sender)
            Sprite_kill(sender)
        end
    })

    createWeapon {
        name = "w_" .. name,
        onFire = getStandardOnFire(sprite_class),
        category = "punch",
        value = 12,
        animation = "weapon_dragonball",
        icon = "icon_dragonball",
        fireMode = {
            direction = "fixed",
            throwStrengthFrom = 300,
            throwStrengthTo = 300,
        }
    }
end
