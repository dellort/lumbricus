-- Utility functions used by other modules; gets loaded first

-- xxx this function is very specific to prod and baseball, so I did not bother
--     moving it to gameutils
-- all worms in radius get an impulse of strength in fire direction, and
--   everything takes some damage
function getMeleeImpulseOnFire(strength, damage)
    return getMeleeOnFire(10, 15, function(shooter, info, self, obj)
        local spr = Phys_backlink(obj)
        if damage > 0 then
            Phys_applyDamage(obj, damage, 3, self)
        end
        -- hm, why only worms? could be funny to baseball away mines
        -- but that's how it was before
        if className(spr) == "WormSprite" then
            Phys_addImpulse(obj, info.dir * strength)
        end
    end)
end

-- specific to gun-type weapons: nrounds explosions in a direct line-of-sight
-- effect = optional function(from, to) to draw an impact effect
-- returns: onFire, onInterrupt, onReadjust (same as getMultipleOnFire)
function getGunOnFire(nrounds, interval, damage, effect)
    return getMultipleOnFire(nrounds, interval, false,
        function(shooter, fireinfo)
            local hitpoint = castFireRay(shooter, fireinfo)
            if hitpoint then
                if effect then
                    effect(fireinfo.pos, hitpoint)
                end
                -- hit something
                Game_explosionAt(hitpoint, damage, shooter)
            end
        end)
end

-- return a function(from, to) that draws a laser for the given time
-- t = time how long the laser should last
function getLaserEffect(t)
    local function color(r,g,b,a)
        return {r=r,g=g,b=b,a=a or 1}
    end

    local line_colors = { color(1,0,0), color(0,0,0), color(1,0,0) }
    local line_time = t or time("2s")

    return function(from, to)
        RenderLaser_ctor(Game, from, to, line_time, line_colors)
    end
end

