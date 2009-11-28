-- "shortcut" functions for server exec (you could also say "cheats")

function giveWeapon(name, amount)
    Team_addWeapon(Game_ownedTeam(), Gfx_findWeaponClass(name), amount)
end

function spawnSprite(name, pos, velocity)
    s = Game_createSprite(name)
    Obj_set_createdBy(s, Member_sprite(Team_get_current(Game_ownedTeam())))
    if (velocity) then
        Phys_setInitialVelocity(Sprite_get_physics(s), velocity)
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
                p = Sprite_get_physics(Member_sprite(m))
                Phys_applyDamage(p, Phys_get_lifepower(p) - 1, 2)
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
