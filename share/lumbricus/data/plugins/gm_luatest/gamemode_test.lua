-- Test file for lua gamemode
-- Currently just activates the first team

printf("{}", config)

addGlobalEventHandler("game_start", function(sender)
    Team.set_active(Control:teams()[1], true)

    -- for testing
    local status = TimeStatus_ctor()
    TimeStatus_set_showTurnTime(status, true)
    TimeStatus_set_showGameTime(status, true)
    raiseEvent(Game_globalEvents(), "game_hud_add", "timer", status)
end)

-- activate next when the current worm "disappears"
addGlobalEventHandler("team_set_active", function(sender, active)
    if not active then
        -- check until a member can be activated
        addPeriodicTimer(timeSecs(0.2), function(timer)
            for idx, t in ipairs(Control:teams()) do
                -- don't activate members that are moving
                if Team.alive(t) and Team.nextWasIdle(t, timeMsecs(500)) then
                    Team.set_active(t, true)
                    timer:cancel()
                    return
                end
            end
        end)
    end
end)

-- update health every 5s
addPeriodicTimer(timeSecs(5), function()
    addPeriodicTimer(Time.Null, function(timer)
        if not Control:checkDyingWorms() then
            timer:cancel()
        end
    end)
    Control:updateHealth()
end)
