-- Utility functions used by other modules; gets loaded first

-- impulse+damage
-- victim = Phys object on which the impulse/damage is inflicted
-- sender = sprite for damage statistic tracking
-- strength = impulse
-- damage = ...
-- dir = direction of impulse (normalized)
function applyMeleeImpulse(victim, sender, strength, damage, dir)
    T(PhysicObject, victim)
    local spr = victim:backlink()
    if damage > 0 then
        -- serious wtf: the 3rd param is DamageCause, and the code here used to
        --  pass the value 3. but there's no enum member for DamageCause that
        --  maps to 3. replaced by "special", which is 2
        victim:applyDamage(damage, "special", sender)
    end
    -- hm, why only worms? could be funny to baseball away mines
    -- but that's how it was before
    -- xxx this allocates memory, isn't elegant, etc.
    --  better way: use physic collision type for filtering
    if className(spr) == "WormSprite" then
        victim:addImpulse(dir * strength)
    end
end

-- xxx this function is very specific to prod and baseball, so I did not bother
--     moving it to gameutils
-- all worms in radius get an impulse of strength in fire direction, and
--   everything takes some damage
function getMeleeImpulseOnFire(strength, damage)
    return getMeleeOnFire(10, 15, function(shooter, info, self, obj)
        applyMeleeImpulse(obj, self, strength, damage, info.dir)
    end)
end

-- specific to gun-type weapons: nrounds explosions in a direct line-of-sight
-- effect = optional function(from, to) to draw an impact effect
-- spread = nil or random spread angle
-- returns: onFire, onInterrupt, onReadjust (same as getMultipleOnFire)
function getGunOnFire(nrounds, interval, damage, effect, spread)
    return getMultipleOnFire(nrounds, interval, false,
        function(shooter, fireinfo)
            local hitpoint, normal = castFireRay(shooter:owner(),
                fireinfo.dir, spread)
            if effect then
                effect(fireinfo.pos, hitpoint)
            end
            if normal then
                -- hit something
                Game:explosionAt(hitpoint, damage, shooter)
            end
        end)
end

-- return a function(from, to) that draws a laser for the given time
-- t = time how long the laser should last
function getLaserEffect(t)
    local line_colors = {Color(1,0,0,0), Color(1,0,0), Color(1,0,0,0)}
    local line_time = t or time("2s")

    return function(from, to)
        RenderLaser.ctor(Game, from, to, line_time, line_colors)
    end
end

