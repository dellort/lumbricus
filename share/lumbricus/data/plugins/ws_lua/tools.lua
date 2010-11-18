-- tool weapons (mostly trivial and/or implemented in D, spawn no sprites)

createWeapon {
    name = "w_girder",
    onCreateSelector = function(sprite)
        return GirderControl.ctor(sprite)
    end,
    onFire = function(shooter, fireinfo)
        local sel = shooter:selector()
        if not sel then return end
        T(GirderControl, sel)
        if sel:fireCheck(fireinfo, true) then
            shooter:reduceAmmo()
            emitParticle("p_girder_place", fireinfo.pointto.pos)
        end
        shooter:finished()
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
    name = "w_beamer",
    value = 10,
    category = "tools",
    icon = "icon_beamer",
    dontEndRound = true,
    deselectAfterFire = true,
    fireMode = {
        point = "instantFree"
    },
    animation = "weapon_beamer",
    prepareParticle = "p_beam_select",
    onFire = function(shooter, fireinfo)
        -- can't use fireParticle as Shooter dies immediately
        emitShooterParticle("p_beam", shooter)
        shooter:reduceAmmo()
        shooter:finished() -- probably called by BeamHandler on the end?
        local worm = shooter:owner()
        T(Worm, worm)
        worm:beamTo(fireinfo.pointto.pos)
    end
}

createWeapon {
    name = "w_drill",
    ctor = DrillClass.ctor,
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
    name = "w_blowtorch",
    ctor = DrillClass.ctor,
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
local function teamActionOnFire(action, particle)
    return function(shooter, fireinfo)
        if particle then
            emitShooterParticle(particle, shooter)
        end
        local team, member = currentTeamFromShooter(shooter)
        if team and member then
            shooter:reduceAmmo()
            action(team, member)
        end
        shooter:finished()
    end
end

createWeapon {
    name = "w_surrender",
    value = 10,
    category = "misc4",
    icon = "icon_surrender",
    animation = "weapon_surrender",
    onFire = teamActionOnFire(function(team)
        team:surrenderTeam()
    end),
}

createWeapon {
    name = "w_skipturn",
    value = 10,
    category = "misc4",
    icon = "icon_skipgo",
    animation = "weapon_skipturn",
    onFire = teamActionOnFire(function(team)
        team:skipTurn()
    end),
}

createWeapon {
    name = "w_wormselect",
    value = 10,
    category = "misc4",
    icon = "icon_changeworm",
    dontEndRound = true,
    deselectAfterFire = true,
    onFire = teamActionOnFire(function(team, member)
        --xxx: we just need the 1-frame delay for this because onFire is
        --     called from doFire, which will set mMember.mWormAction = true
        --     afterwards and would make the resetActivity() call void
        addOnNextFrame(function()
            team:set_allowSelect(true)
            -- allowSelect is removed on activity
            member:control():resetActivity()
        end)
    end),
}

createWeapon {
    name = "w_justice",
    value = 10,
    category = "misc4",
    icon = "icon_scales",
    onFire = teamActionOnFire(function(myteam)
        -- xxx is this really so complicated?
        local teams = Control:teams()
        local sum = 0
        local count = 0
        for i, t in ipairs(teams) do
            local h = t:totalHealth()
            if h > 0 then
                sum = sum + h
                count = count + 1
            end
        end
        if count < 1 then
            return
        end
        -- set every team to average health
        local avg = sum/count
        local changed = 0 -- debugging
        for i, t in ipairs(teams) do
            -- distribute team health change over (alive) members
            local alive_worms = {}
            for i2, m in ipairs(t:members()) do
                if m:health() > 0 then
                    alive_worms[#alive_worms + 1] = m
                end
            end
            local perworm = avg / #alive_worms
            for i2, m in ipairs(alive_worms) do
                local h = m:health()
                m:addHealth(perworm - h)
                h = m:health() - h
                changed = changed - h
            end
        end
        -- number of health points that got lost due to integer rounding
        log.minor("heavenly injustice: {}", changed)
        -- xxx missing: force GUI to update the health points (actually, the
        --  game mode should do that automatically: 0. detect health point
        --  change, 1. wait for silence, 2. count down 3. give the GUI time
        --  4. continue game)
    end, "p_scales"),
}


createWeapon {
    name ="w_parachute",
    ctor = ParachuteClass.ctor,
    value = 10,
    category = "tools",
    icon = "icon_parachute",
    allowSecondary = true,
    dontEndRound = true,
    sideForce = 3000,
}

createWeapon {
    name = "w_jetpack",
    ctor = JetpackClass.ctor,
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
    name = "w_superrope",
    ctor = RopeClass.ctor,
    value = 10,
    category = "tools",
    icon = "icon_rope",
    fireParticle = "p_rope_fire",
    allowSecondary = true,
    dontEndRound = true,

    shootSpeed = 1000,
    maxLength = 1000,
    moveSpeed = 200,
    swingForce = 3000,
    swingForceUp = 2000,
    hitImpulse = 700,
    ropeColor = {0.8, 0.8, 0.8},
    ropeSegment = lookupResource("rope_segment"),
    impactParticle = lookupResource("p_rope_impact"),

    animation = "weapon_rope",
    anchorAnim = lookupResource("rope_anchor"),

    fireMode = {
        direction = "any",
        throwStrengthFrom = 1000,
        throwStrengthTo = 1000,
    }
}

local function freezeTeam(team, freeze)
    for i, m in ipairs(team:members()) do
        local worm = m:sprite()
        if not spriteIsGone(worm) then
            -- xxx worm dependency
            T(Worm, worm)
            worm:freeze(freeze)
        end
    end
end

createWeapon {
    name = "w_freeze",
    value = 10,
    category = "misc1",
    icon = "icon_freeze",
    animation = "weapon_freeze",
    onFire = teamActionOnFire(function(team, member)
        freezeTeam(team, true)
        -- end round
        team:set_active(false)
        -- add callback to unfreeze
        local function unfreeze(t, active)
            assert(t == team)
            if not active then
                return
            end
            removeInstanceEventHandler(team, "team_set_active", unfreeze)
            -- actual unfreeze
            freezeTeam(team, false)
        end
        addInstanceEventHandler(team, "team_set_active", unfreeze)
    end, "p_freeze"),
}

do
    local name = "laserbeamer"
    local addlaser = getLaserEffect(time("2s"))

    local w = createWeapon {
        name = "w_" .. name,
        onFire = function(shooter, fireinfo)
            shooter:finished()
            local sprite = shooter:owner()
            local hitpoint, normal = castFireRay(sprite, fireinfo.dir)
            -- xxx laser is inside the poor worm
            addlaser(fireinfo.pos, hitpoint)
            if normal then
                shooter:reduceAmmo()
                T(Worm, sprite)
                sprite:beamTo(hitpoint)
            end
        end,
        category = "tools",
        value = 10,
        dontEndRound = true,
        animation = "weapon_sheeplauncher",
        icon = "icon_shotgun",
        fireMode = {
            direction = "any",
        }
    }
end
