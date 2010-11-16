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
        local spr = Phys.backlink(obj)
        -- xxx see init.lua comments for a similar thing
        if className(spr) == "WormSprite" then
            -- half lifepower, but don't reduce to less than 1 hp
            local hp = Phys.lifepower(obj)
            local dmg = math.min(hp * 0.5, hp - 1)
            dmg = math.max(dmg, 0)
            Phys.applyDamage(obj, dmg, 3, self)
            Phys.addImpulse(obj, Vector2(0, 1))
        else
            -- destroy barrels
            Phys.applyDamage(obj, 50, 3, self)
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
            Sprite.kill(sender)
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

createWeapon {
    name = "w_kamikazebomber",
    onFire = function(shooter, info)
        Shooter.reduceAmmo(shooter)
        Shooter.finished(shooter)
        
        local worm = Shooter.owner(shooter)
        -- spawn 1 class with 50% probability (or always count, if specified)
        local function spawn(class, count)
            count = count or Random:rangei(0, 1)
            spawnCluster(class, worm, count, 250, 450, 60)
        end
        
        -- kill
        spriteExplode(worm, 50)

        -- random fun (when you think of it: what could possibly be inside a worm? hehe)
        spawn(bananashard_class)
        spawn(grenade_class)
        spawn(clusterbomb_class)
        spawn(holygrenade_class)
        spawn(bazooka_class)
        spawn(cratesheep_class)
        spawn(dynamite_class)
        spawn(mine_class)
        -- I couldn't stop myself xD
        spawn(esel_class, math.floor(Random:rangei(0, 9)/9))
    end,
    category = "punch",
    value = 12,
    animation = "weapon_kamikazebomber",
    icon = "icon_kamikazebomber",
    fireMode = {
        direction = "fixed",
    }
}
