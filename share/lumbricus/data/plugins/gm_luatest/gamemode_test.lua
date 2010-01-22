-- Test file for lua gamemode
-- Currently just activates the first team

printf("{}", config)

addGlobalEventHandler("game_start", function(sender)
    Team_set_active(Control_teams()[1], true)

    -- for testing
    local status = TimeStatus_ctor()
    TimeStatus_set_showTurnTime(status, true)
    TimeStatus_set_showGameTime(status, true)
    raiseEvent(Game_globalEvents(), "game_hud_add", "timer", status)
end)

-- simulate() equivalent
addPeriodicTimer(timeSecs(1), function()
    printf("insert code here")
end)
