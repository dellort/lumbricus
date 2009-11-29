-- "shortcut" functions for server exec (you could also say "cheats")

function giveWeapon(name, amount)
    Team_addWeapon(Game_ownedTeam(), Gfx_findWeaponClass(name), amount)
end

function spawnSprite(name, pos, velocity)
    local s = Game_createSprite(name)
    local t = Game_ownedTeam()
    if (t) then
        Obj_set_createdBy(s, Member_sprite(Team_current(t)))
    end
    if (velocity) then
        Phys_setInitialVelocity(Sprite_physics(s), velocity)
    end
    Sprite_activate(s, pos)
end

-- the caller wins
function allYourBaseAreBelongToUs()
    for k,t in ipairs(Control_teams()) do
        if (t ~= Game_ownedTeam()) then
            Team_surrenderTeam(t)
        end
    end
end

-- +500 hp for caller, 1 hp for others
function whosYourDaddy()
    for k,t in ipairs(Control_teams()) do
        for k,m in ipairs(Team_getMembers(t)) do
            if (t == Game_ownedTeam()) then
                Member_addHealth(m, 500)
            else
                p = Sprite_physics(Member_sprite(m))
                Phys_applyDamage(p, Phys_lifepower(p) - 1, 2)
            end
        end
    end
end

-- amount (or 10 if omitted) of all weapons
function greedIsGood(amount)
    for k,w in ipairs(Gfx_weaponList()) do
        Team_addWeapon(Game_ownedTeam(), w, amount or 10)
    end
end

function katastrophe()
    local lb = Level_landBounds()
    World_objectsAtPred(Level_worldCenter(), 2000, function(obj)
        local dest
        while (dest == nil) do
            dest = Vector2(Random_rangef(lb.p1.x, lb.p2.x), Random_rangef(lb.p1.y, lb.p2.y))
            dest = World_freePoint(dest, 6)
        end
        Worm_beamTo(Phys_backlink(obj), dest)
        return true
    end, function(obj)
        return className(Phys_backlink(obj)) == "WormSprite"
    end)
end
