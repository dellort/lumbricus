-- tool weapons (mostly trivial and/or implemented in D, spawn no sprites)

createWeapon {
    name = "girder",
    onCreateSelector = function(sprite)
        return GirderControl_ctor(sprite)
    end,
    onFire = function(shooter, fireinfo)
        local sel = Shooter_selector(shooter)
        if not sel then return end
        if GirderControl_fireCheck(sel, fireinfo, true) then
            Shooter_reduceAmmo(shooter)
        end
        Shooter_finished(shooter)
    end,
    value = 10,
    category = "worker",
    icon = "icon_girder",
    animation = "weapon_helmet",
    crateAmount = 3,
    fireMode = {
        point = "instant",
    }
}

createWeapon {
    name = "beamer",
    value = 10,
    category = "tools",
    icon = "icon_beamer",
    dontEndRound = true,
    deselectAfterFire = true,
    fireMode = {
        point = "instantFree"
    },
    animation = "weapon_beamer",
    onFire = function(shooter, fireinfo)
        Shooter_reduceAmmo(shooter)
        Shooter_finished(shooter) -- probably called by BeamHandler on the end?
        Worm_beamTo(Shooter_owner(shooter), fireinfo.pointto.pos)
    end
}

createWeapon {
    name = "drill",
    ctor = "DrillClass_ctor",
    value = 10,
    category = "worker",
    icon = "icon_drill",
    duration = time("5 s"),
    tunnelRadius = 9,
    interval = timeRange("100ms", "200ms"),
    animation = "weapon_drill",
    fireMode = {
    },
}

createWeapon {
    name = "blowtorch",
    ctor = "DrillClass_ctor",
    value = 10,
    category = "worker",
    icon = "icon_blowtorch",
    duration = time("5 s"),
    tunnelRadius = 9,
    interval = timeRange("50ms"),
    blowtorch = true,
    animation = "weapon_blowtorch",
    fireMode = {
        direction = "threeway"
    }
}

-- just a very specific helper function to help with the following weapons
-- will call action(team, member) on the current team/member
local function teamActionOnFire(action)
    return function(shooter, fireinfo)
        local team, member = currentTeamFromShooter(shooter)
        if team and member then
            Shooter_reduceAmmo(shooter)
            action(team, member)
        end
        Shooter_finished(shooter)
    end
end

createWeapon {
    name = "surrender",
    value = 10,
    category = "misc4",
    icon = "icon_surrender",
    animation = "weapon_surrender",
    onFire = teamActionOnFire(function(team)
        Team_surrenderTeam(team)
    end),
}

createWeapon {
    name = "skipturn",
    value = 10,
    category = "misc4",
    icon = "icon_skipgo",
    animation = "weapon_skipturn",
    onFire = teamActionOnFire(function(team)
        Team_skipTurn(team)
    end),
}

createWeapon {
    name = "wormselect",
    value = 10,
    category = "misc4",
    icon = "icon_changeworm",
    dontEndRound = true,
    deselectAfterFire = true,
    onFire = teamActionOnFire(function(team, member)
        WormSelectHelper_ctor(Game, member)
    end),
}

createWeapon {
    name = "hat",
    value = 0,
    category = "misc4",
    icon = "icon_unknown",
    animation = "weapon_hat",
    onFire = teamActionOnFire(function(team, member)
        -- "whatever"
        for k, t in ipairs(Control_teams()) do
            if t ~= team then
                for k2, m in ipairs(Team_getMembers(t)) do
                    Member_addHealth(m, -9999)
                end
            end
        end
    end),
}


createWeapon {
    name ="parachute",
    ctor = "ParachuteClass_ctor",
    value = 10,
    category = "tools",
    icon = "icon_parachute",
    allowSecondary = true,
    dontEndRound = true,
    sideForce = 3000,
}

createWeapon {
    name = "jetpack",
    ctor = "JetpackClass_ctor",
    value = 10,
    category = "tools",
    icon = "icon_jetpack",
    allowSecondary = true,
    dontEndRound = true,
    -- combined thrust time for both engines (i.e. fuel)
    maxTime = time("15 s"),
    -- force applied to the worm
    jetpackThrust = Vector2(4000, 10000),
    -- stop worm x movement when pressing fire again
    stopOnDisable = true,
}

createWeapon {
    name = "superrope",
    ctor = "RopeClass_ctor",
    value = 10,
    category = "tools",
    icon = "icon_rope",
    allowSecondary = true,
    dontEndRound = true,

    shootSpeed = 1000,
    maxLength = 1000,
    moveSpeed = 200,
    swingForce = 3000,
    swingForceUp = 2000,
    ropeColor = {0.8, 0.8, 0.8},
    ropeSegment = Gfx_resource("rope_segment"),

    animation = "weapon_rope",
    anchorAnim = Gfx_resource("rope_anchor"),

    fireMode = {
        direction = "any",
        throwStrengthFrom = 1000,
        throwStrengthTo = 1000,
    }
}

do
    local name = "beamlaser"
    local addlaser = getLaserEffect(time("2s"))

    local w = createWeapon {
        name = name,
        onFire = function(shooter, fireinfo)
            Shooter_finished(shooter)
            local hitpoint = castFireRay(shooter, fireinfo)
            if hitpoint then
                Shooter_reduceAmmo(shooter)
                Worm_beamTo(Shooter_owner(shooter), hitpoint)
                addlaser(fireinfo.pos, hitpoint)
            end
        end,
        category = "tools",
        value = 0,
        dontEndRound = true,
        animation = "weapon_sheeplauncher",
        icon = "icon_shotgun",
        fireMode = {
            direction = "any",
        }
    }
end
